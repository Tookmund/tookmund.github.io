---
layout: post
title: "Linux Hibernation Code"
description: "How does hibernation work on Linux?"
category:
tags: [hibernate]
---

Now that I've [explored the hibernation documentation on Linux](/2022/01/hibernate-docs)
hibernation, it's time for me to dive into the code.

## A Starting Point for Investigation: `/sys/power/state` and `/sys/power/disk`

These two system files exist to [allow debugging of hibernation](https://www.kernel.org/doc/html/latest/power/basic-pm-debugging.html),
and thus control the exact state used directly.
Writing specific values to the `state` file controls the exact sleep mode used
and `disk` controls the specific hibernation mode.

This is extremely handy as an entrypoint to understand how these systems work,
since I can just follow what happens when they are written to.

This article has been written using Linux version 6.9.9,
the source of which can be found in many places, but can be navigated
easily through the Bootlin Elixir Cross-Referencer:

https://elixir.bootlin.com/linux/v6.9.9/source

Each code snippet will begin with a comment giving
the file path and the line number of the beginning of the snippet.

### Show and Store Functions
These two files are defined using the `power_attr` macro:
```
// kernel/power/power.h:80
#define power_attr(_name) \
static struct kobj_attribute _name##_attr = {   \
    .attr   = {             \
        .name = __stringify(_name), \
        .mode = 0644,           \
    },                  \
    .show   = _name##_show,         \
    .store  = _name##_store,        \
}
```

`show` is called on reads and `store` on writes.

`state_show` is a little boring for our purposes, as it just prints all the
available sleep states.

```
// kernel/power/main.c:657
/*
 * state - control system sleep states.
 *
 * show() returns available sleep state labels, which may be "mem", "standby",
 * "freeze" and "disk" (hibernation).
 * See Documentation/admin-guide/pm/sleep-states.rst for a description of
 * what they mean.
 *
 * store() accepts one of those strings, translates it into the proper
 * enumerated value, and initiates a suspend transition.
 */
static ssize_t state_show(struct kobject *kobj, struct kobj_attribute *attr,
			  char *buf)
{
	char *s = buf;
#ifdef CONFIG_SUSPEND
	suspend_state_t i;

	for (i = PM_SUSPEND_MIN; i < PM_SUSPEND_MAX; i++)
		if (pm_states[i])
			s += sprintf(s,"%s ", pm_states[i]);

#endif
	if (hibernation_available())
		s += sprintf(s, "disk ");
	if (s != buf)
		/* convert the last space to a newline */
		*(s-1) = '\n';
	return (s - buf);
}
```

`state_store`, however, provides our entry point.
If the string "disk" is written to the `state` file, it calls `hibernate()`.
This is our entry point.

```
// kernel/power/main.c:715
static ssize_t state_store(struct kobject *kobj, struct kobj_attribute *attr,
			   const char *buf, size_t n)
{
	suspend_state_t state;
	int error;

	error = pm_autosleep_lock();
	if (error)
		return error;

	if (pm_autosleep_state() > PM_SUSPEND_ON) {
		error = -EBUSY;
		goto out;
	}

	state = decode_state(buf, n);
	if (state < PM_SUSPEND_MAX) {
		if (state == PM_SUSPEND_MEM)
			state = mem_sleep_current;

		error = pm_suspend(state);
	} else if (state == PM_SUSPEND_MAX) {
		error = hibernate();
	} else {
		error = -EINVAL;
	}

 out:
	pm_autosleep_unlock();
	return error ? error : n;
}
```

Could we have figured this out just via function names?
Sure, but this way we know for sure that nothing else is happening before this
function is called.

Interestingly, it grabs the `pm_autosleep_lock` before checking the current
state.

autosleep is a mechanism [originally from Android](https://lwn.net/Articles/479841/)
that sends the entire system to either suspend or hibernate whenever it is
not actively working on anything.

TODO: Wakelocks

## The Steps of Hibernation

### Hibernation Kernel Config

It's important to note that most of the hibernate specific functions below
do nothing unless you've defined `CONFIG_HIBERNATION` in your Kconfig.
As an example, `hibernate` itself is defined as the following if
`CONFIG_HIBERNATE` is not set.

```
// include/linux/suspend.h:407
static inline int hibernate(void) { return -ENOSYS; }
```

### Check if Hibernation is Available
We begin by confirming that we actually can perform hibernation,
via the `hibernation_available` function.

```
// kernel/power/hibernate.c:742
if (!hibernation_available()) {
	pm_pr_dbg("Hibernation not available.\n");
	return -EPERM;
}
```

```
// kernel/power/hibernate.c:92
bool hibernation_available(void)
{
	return nohibernate == 0 &&
		!security_locked_down(LOCKDOWN_HIBERNATION) &&
		!secretmem_active() && !cxl_mem_active();
}
```

`nohibernate` is controlled by the kernel command line, it's set via
either `nohibernate` or `hibernate=no`.

`security_locked_down` is a hook for Linux Security Modules to prevent
hibernation. This is used to prevent hibernating to an unencrypted storage
device, as specified in the manual page `kernel_lockdown(7)`.
Interestingly, either level of lockdown, integrity or confidentiality,
locks down hibernation because with the ability to hibernate you can extract
bascially anything from memory and even reboot into a modified kernel image.

`secretmem_active` checks whether there is any active use of
`memfd_secret`, and if so it prevents hibernation.
`memfd_secret` returns a file descriptor that can be mapped into a process
but is specifically unmapped from the kernel's memory space.
Hibernating with memory that not even the kernel is supposed to
access would expose that memory to whoever could access the hibernation image.
This particular feature of secret memory was apparently
[controversial](https://lwn.net/Articles/865256/), though not as
controversial as performance concerns around fragmentation when unmapping
kernel memory
([which did not end up being a real problem](https://lwn.net/Articles/865256/)).

`cxl_mem_active` just checks whether any CXL memory is active.
A full explanation is provided in the
[commit introducing this check](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=9ea4dcf49878bb9546b8fa9319dcbdc9b7ee20f8)
but there's also a shortened explanation from `cxl_mem_probe` that
sets the relevant flag when initializing a CXL memory device.

```
// drivers/cxl/mem.c:186
* The kernel may be operating out of CXL memory on this device,
* there is no spec defined way to determine whether this device
* preserves contents over suspend, and there is no simple way
* to arrange for the suspend image to avoid CXL memory which
* would setup a circular dependency between PCI resume and save
* state restoration.
```

### Check Compression

The next check is for whether compression support is enabled, and if so
whether the requested algorithm is enabled.

```
// kernel/power/hibernate.c:747
/*
 * Query for the compression algorithm support if compression is enabled.
 */
if (!nocompress) {
	strscpy(hib_comp_algo, hibernate_compressor, sizeof(hib_comp_algo));
	if (crypto_has_comp(hib_comp_algo, 0, 0) != 1) {
		pr_err("%s compression is not available\n", hib_comp_algo);
		return -EOPNOTSUPP;
	}
}
```

The `nocompress` flag is set via the `hibernate` command line parameter,
setting `hibernate=nocompress`.

If compression is enabled, then `hibernate_compressor` is copied to
`hib_comp_algo`. This synchronizes the current requested compression
setting (`hibernate_compressor`) with the current compression setting
(`hib_comp_algo`).

Both values are character arrays of size `CRYPTO_MAX_ALG_NAME`
(128 in this kernel).

```
// kernel/power/hibernate.c:50
static char hibernate_compressor[CRYPTO_MAX_ALG_NAME] = CONFIG_HIBERNATION_DEF_COMP;

/*
 * Compression/decompression algorithm to be used while saving/loading
 * image to/from disk. This would later be used in 'kernel/power/swap.c'
 * to allocate comp streams.
 */
char hib_comp_algo[CRYPTO_MAX_ALG_NAME];
```

`hibernate_compressor` defaults to `lzo` if enabled, otherwise to `lz4` if
enabled[^choicedefault]. It can be overwritten using the `hibernate.compressor` setting to
either `lzo` or `lz4`.

[^choicedefault]: Kconfig defaults to the [first default found](https://www.kernel.org/doc/html/v6.9/kbuild/kconfig-language.html)

```
// kernel/power/Kconfig:95
choice
	prompt "Default compressor"
	default HIBERNATION_COMP_LZO
	depends on HIBERNATION

config HIBERNATION_COMP_LZO
	bool "lzo"
	depends on CRYPTO_LZO

config HIBERNATION_COMP_LZ4
	bool "lz4"
	depends on CRYPTO_LZ4

endchoice

config HIBERNATION_DEF_COMP
	string
	default "lzo" if HIBERNATION_COMP_LZO
	default "lz4" if HIBERNATION_COMP_LZ4
	help
	  Default compressor to be used for hibernation.
```

```
// kernel/power/hibernate.c:1425
static const char * const comp_alg_enabled[] = {
#if IS_ENABLED(CONFIG_CRYPTO_LZO)
	COMPRESSION_ALGO_LZO,
#endif
#if IS_ENABLED(CONFIG_CRYPTO_LZ4)
	COMPRESSION_ALGO_LZ4,
#endif
};

static int hibernate_compressor_param_set(const char *compressor,
		const struct kernel_param *kp)
{
	unsigned int sleep_flags;
	int index, ret;

	sleep_flags = lock_system_sleep();

	index = sysfs_match_string(comp_alg_enabled, compressor);
	if (index >= 0) {
		ret = param_set_copystring(comp_alg_enabled[index], kp);
		if (!ret)
			strscpy(hib_comp_algo, comp_alg_enabled[index],
				sizeof(hib_comp_algo));
	} else {
		ret = index;
	}

	unlock_system_sleep(sleep_flags);

	if (ret)
		pr_debug("Cannot set specified compressor %s\n",
			 compressor);

	return ret;
}
static const struct kernel_param_ops hibernate_compressor_param_ops = {
	.set    = hibernate_compressor_param_set,
	.get    = param_get_string,
};

static struct kparam_string hibernate_compressor_param_string = {
	.maxlen = sizeof(hibernate_compressor),
	.string = hibernate_compressor,
};
```


We then check whether the requested algorithm is supported via `crypto_has_comp`.
If not, we bail out of the whole operation with `EOPNOTSUPP`.

As part of `crypto_has_comp` we perform any needed initialization of the
algorithm, loading kernel modules and running initialization code as needed[^larval].

[^larval]: Including checking whether the algorithm is larval? Which appears to me that it requires additional setup, but is an interesting choice of name for such a state.

### Grab Locks

The next step is to grab the sleep and hibernation locks via
`lock_system_sleep` and `hibernate_acquire`.
```
// kernel/power/hibernate.c:758
sleep_flags = lock_system_sleep();
/* The snapshot device should not be opened while we're running */
if (!hibernate_acquire()) {
	error = -EBUSY;
	goto Unlock;
}
```

First, `lock_system_sleep` marks the current thread as not freezable, which
will be important later. It then grabs the `system_transistion_mutex`,
which locks taking snapshots or modifying how they are taken,
resuming from a hibernation image, entering any suspend state, or rebooting.

The kernel also issues a warning if the `gfp` mask is changed via either
`pm_restore_gfp_mask` or `pm_restrict_gfp_mask`
without holding the `system_transistion_mutex`.
TODO: GFP Masks

```
// kernel/power/main.c:52
unsigned int lock_system_sleep(void)
{
	unsigned int flags = current->flags;
	current->flags |= PF_NOFREEZE;
	mutex_lock(&system_transition_mutex);
	return flags;
}
EXPORT_SYMBOL_GPL(lock_system_sleep);
```

```
// include/linux/sched.h:1633
#define PF_NOFREEZE		0x00008000	/* This thread should not be frozen */
```

It then returns and captures the previous state of the threads flags
in `sleep_flags`.
This is used later to remove `PF_NOFREEZE` if it wasn't previously set on the
current thread.

Then we grab the hibernate-specific semaphore to ensure no one can open a
snapshot or resume from it while we perform hibernation.
Additionally this lock is used to prevent ` hibernate_quiet_exec`,
which is used by the `nvdimm` driver to active its firmware with all
processes and devices frozen, ensuring it is the only thing running at that
time.

```
// kernel/power/hibernate.c:82
bool hibernate_acquire(void)
{
	return atomic_add_unless(&hibernate_atomic, -1, 0);
}
```

### Prepare Console
The kernel next calls `pm_prepare_console`.
This function only does anything if `CONFIG_VT_CONSOLE_SLEEP` has been set.

This prepares the virtual terminal for a suspend state, switching away to
a console used only for the suspend state if needed.

```
// kernel/power/console.c:130
void pm_prepare_console(void)
{
	if (!pm_vt_switch())
		return;

	orig_fgconsole = vt_move_to_console(SUSPEND_CONSOLE, 1);
	if (orig_fgconsole < 0)
		return;

	orig_kmsg = vt_kmsg_redirect(SUSPEND_CONSOLE);
	return;
}
```

The first thing is to check whether we actually need to switch the VT
```
// kernel/power/console.c:94
/*
 * There are three cases when a VT switch on suspend/resume are required:
 *   1) no driver has indicated a requirement one way or another, so preserve
 *      the old behavior
 *   2) console suspend is disabled, we want to see debug messages across
 *      suspend/resume
 *   3) any registered driver indicates it needs a VT switch
 *
 * If none of these conditions is present, meaning we have at least one driver
 * that doesn't need the switch, and none that do, we can avoid it to make
 * resume look a little prettier (and suspend too, but that's usually hidden,
 * e.g. when closing the lid on a laptop).
 */
static bool pm_vt_switch(void)
{
	struct pm_vt_switch *entry;
	bool ret = true;

	mutex_lock(&vt_switch_mutex);
	if (list_empty(&pm_vt_switch_list))
		goto out;

	if (!console_suspend_enabled)
		goto out;

	list_for_each_entry(entry, &pm_vt_switch_list, head) {
		if (entry->required)
			goto out;
	}

	ret = false;
out:
	mutex_unlock(&vt_switch_mutex);
	return ret;
}
```

There is an explanation of the conditions under which a switch is performed
in the comment above the function, but we'll also walk through the steps here.

Firstly we grab the `vt_switch_mutex` to ensure nothing will modify the list
while we're looking at it.

We then examine the `pm_vt_switch_list`.
This list is used to indicate the drivers that require a switch during suspend.
They register this requirement, or the lack thereof, via
`pm_vt_switch_required`.

```
// kernel/power/console.c:31
/**
 * pm_vt_switch_required - indicate VT switch at suspend requirements
 * @dev: device
 * @required: if true, caller needs VT switch at suspend/resume time
 *
 * The different console drivers may or may not require VT switches across
 * suspend/resume, depending on how they handle restoring video state and
 * what may be running.
 *
 * Drivers can indicate support for switchless suspend/resume, which can
 * save time and flicker, by using this routine and passing 'false' as
 * the argument.  If any loaded driver needs VT switching, or the
 * no_console_suspend argument has been passed on the command line, VT
 * switches will occur.
 */
void pm_vt_switch_required(struct device *dev, bool required)
```

Next, we check `console_suspend_enabled`. This is set to false
by the kernel parameter `no_console_suspend`, but defaults to true.

Finally, if there are any entries in the `pm_vt_switch_list`, then we
check to see if any of them require a VT switch.

Only if none of these conditions apply, then we return false.

If a VT switch is in fact required, then we move first the currently active
virtual terminal/console[^console] (`vt_move_to_console`)
and then the current location of kernel messages (`vt_kmsg_redirect`)
to the `SUSPEND_CONSOLE`.
The `SUSPEND_CONSOLE` is the last entry in the list of possible
consoles, and appears to just be a black hole to throw away messages.

[^console]: Annoyingly this code appears to use the terms "console" and "virtual terminal" interchangeably.

```
// kernel/power/console.c:16
#define SUSPEND_CONSOLE	(MAX_NR_CONSOLES-1)
```

Interestingly, these are separate functions because you can use
`TIOCL_SETKMSGREDIRECT` to send kernel messages to a specific virtual terminal,
but by default its the same as the currently active console.

TODO: TIOCL

The locations of the previously active console and the previous kernel
messages location are stored in `orig_fgconsole` and `orig_kmsg`, to
restore the state of the console and kernel messages after the machine wakes
up again.
Interestingly, this means `orig_fgconsole` also ends up storing any errors,
so has to be checked to ensure it's not less than zero before we try to do
anything with the kernel messages on both suspend and resume.

```
// drivers/tty/vt/vt_ioctl.c:1268
/* Perform a kernel triggered VT switch for suspend/resume */

static int disable_vt_switch;

int vt_move_to_console(unsigned int vt, int alloc)
{
	int prev;

	console_lock();
	/* Graphics mode - up to X */
	if (disable_vt_switch) {
		console_unlock();
		return 0;
	}
	prev = fg_console;

	if (alloc && vc_allocate(vt)) {
		/* we can't have a free VC for now. Too bad,
		 * we don't want to mess the screen for now. */
		console_unlock();
		return -ENOSPC;
	}

	if (set_console(vt)) {
		/*
		 * We're unable to switch to the SUSPEND_CONSOLE.
		 * Let the calling function know so it can decide
		 * what to do.
		 */
		console_unlock();
		return -EIO;
	}
	console_unlock();
	if (vt_waitactive(vt + 1)) {
		pr_debug("Suspend: Can't switch VCs.");
		return -EINTR;
	}
	return prev;
}
```

Unlike most other locking functions we've seen so far, `console_lock`
needs to be careful to ensure nothing else is panicking and needs to
dump to the console before grabbing the semaphore for the console
and setting a couple flags.

Panics are tracked via an atomic integer set to the id of the processor
currently panicking.
```
// kernel/printk/printk.c:2649
/**
 * console_lock - block the console subsystem from printing
 *
 * Acquires a lock which guarantees that no consoles will
 * be in or enter their write() callback.
 *
 * Can sleep, returns nothing.
 */
void console_lock(void)
{
	might_sleep();

	/* On panic, the console_lock must be left to the panic cpu. */
	while (other_cpu_in_panic())
		msleep(1000);

	down_console_sem();
	console_locked = 1;
	console_may_schedule = 1;
}
EXPORT_SYMBOL(console_lock);
```

```
// kernel/printk/printk.c:362
/*
 * Return true if a panic is in progress on a remote CPU.
 *
 * On true, the local CPU should immediately release any printing resources
 * that may be needed by the panic CPU.
 */
bool other_cpu_in_panic(void)
{
	return (panic_in_progress() && !this_cpu_in_panic());
}
```

```
// kernel/printk/printk.c:345
static bool panic_in_progress(void)
{
	return unlikely(atomic_read(&panic_cpu) != PANIC_CPU_INVALID);
}
```

```
// kernel/printk/printk.c:350
/* Return true if a panic is in progress on the current CPU. */
bool this_cpu_in_panic(void)
{
	/*
	 * We can use raw_smp_processor_id() here because it is impossible for
	 * the task to be migrated to the panic_cpu, or away from it. If
	 * panic_cpu has already been set, and we're not currently executing on
	 * that CPU, then we never will be.
	 */
	return unlikely(atomic_read(&panic_cpu) == raw_smp_processor_id());
}
```

`console_locked` is a debug value, used to indicate that the lock should be
held, and our first indication that this whole virtual terminal system is
more complex than might initially be expected.
```
// kernel/printk/printk.c:373
/*
 * This is used for debugging the mess that is the VT code by
 * keeping track if we have the console semaphore held. It's
 * definitely not the perfect debug tool (we don't know if _WE_
 * hold it and are racing, but it helps tracking those weird code
 * paths in the console code where we end up in places I want
 * locked without the console semaphore held).
 */
static int console_locked;
```

`console_may_schedule` is used to see if we are permitted to sleep
and schedule other work while we hold this lock.
As we'll see later, the virtual terminal subsystem is not re-entrant,
so there's all sorts of hacks in here to ensure we don't leave important
code sections that can't be safely resumed.

#### Disable VT Switch
As the comment below lays out, when another program is handling graphical
display anyway, there's no need to do any of this, so the kernel provides
a switch to turn the whole thing off.
Interestingly, this appears to only be used by three drivers,
so the specific hardware support required must not be particularly common.
```
drivers/gpu/drm/omapdrm/dss
drivers/video/fbdev/geode
drivers/video/fbdev/omap2
```

```
// drivers/tty/vt/vt_ioctl.c:1308
/*
 * Normally during a suspend, we allocate a new console and switch to it.
 * When we resume, we switch back to the original console.  This switch
 * can be slow, so on systems where the framebuffer can handle restoration
 * of video registers anyways, there's little point in doing the console
 * switch.  This function allows you to disable it by passing it '0'.
 */
void pm_set_vt_switch(int do_switch)
{
	console_lock();
	disable_vt_switch = !do_switch;
	console_unlock();
}
EXPORT_SYMBOL(pm_set_vt_switch);
```

The rest of the `vt_switch_console` function is pretty normal,
however, simply allocating space if needed to create the requested
virtual terminal
and then setting the current virtual terminal via `set_console`.

#### Virtual Terminal Set Console
With `set_console`, we begin (as if we haven't been already) to enter the
madness that is the virtual terminal subsystem.
As mentioned previously, modifications to its state must be made very
carefully, as other stuff happening at the same time could create complete
messes.

All this to say, calling `set_console` does not actually perform any
work to change the state of the current console.
Instead it indicates what changes it wants and then schedules that work.
```
// drivers/tty/vt/vt.c:3153
int set_console(int nr)
{
	struct vc_data *vc = vc_cons[fg_console].d;

	if (!vc_cons_allocated(nr) || vt_dont_switch ||
		(vc->vt_mode.mode == VT_AUTO && vc->vc_mode == KD_GRAPHICS)) {

		/*
		 * Console switch will fail in console_callback() or
		 * change_console() so there is no point scheduling
		 * the callback
		 *
		 * Existing set_console() users don't check the return
		 * value so this shouldn't break anything
		 */
		return -EINVAL;
	}

	want_console = nr;
	schedule_console_callback();

	return 0;
}
```

The check for `vc->vc_mode == KD_GRAPHICS` is where most end-user graphical
desktops will bail out of this change, as they're in graphics mode and don't
need to switch away to the suspend console.

TODO: VT_AUTO and vt_dont_switch

However, if you do run your machine from a virtual terminal, then we
indicate to the system that we want to change to the requested virtual terminal
via the `want_console` variable
and schedule a callback via `schedule_console_callback`.

```
// drivers/tty/vt/vt.c:315
void schedule_console_callback(void)
{
	schedule_work(&console_work);
}
```

`console_work` is a workqueue created via the `DECLARE_WORK` macro.

#### Workqueues
```
// drivers/tty/vt/vt.c:183
static DECLARE_WORK(console_work, console_callback);
```

```
// include/linux/workqueue.h:242
#define DECLARE_WORK(n, f)						\
	struct work_struct n = __WORK_INITIALIZER(n, f)
```

TODO: Workqueues

#### Console Callback
```
// drivers/tty/vt/vt.c:3109
/*
 * This is the console switching callback.
 *
 * Doing console switching in a process context allows
 * us to do the switches asynchronously (needed when we want
 * to switch due to a keyboard interrupt).  Synchronization
 * with other console code and prevention of re-entrancy is
 * ensured with console_lock.
 */
static void console_callback(struct work_struct *ignored)
{
	console_lock();

	if (want_console >= 0) {
		if (want_console != fg_console &&
		    vc_cons_allocated(want_console)) {
			hide_cursor(vc_cons[fg_console].d);
			change_console(vc_cons[want_console].d);
			/* we only changed when the console had already
			   been allocated - a new console is not created
			   in an interrupt routine */
		}
		want_console = -1;
	}
...
```

`console_callback` first looks to see if there is a console change wanted
via `want_console` and then changes to it if it's not the current console and
has been allocated already.
We do first remove any cursor state with `hide_cursor`.

```
// drivers/tty/vt/vt.c:841
static void hide_cursor(struct vc_data *vc)
{
	if (vc_is_sel(vc))
		clear_selection();

	vc->vc_sw->con_cursor(vc, false);
	hide_softcursor(vc);
}
```

TODO: Full VT Deep dive?

### Notify PM Call Chain
```
// kernel/power/hibernate.c:767
pm_notifier_call_chain_robust(PM_HIBERNATION_PREPARE, PM_POST_HIBERNATION)
```

### Sync Filesystems
`ksys_sync_helper` - Sync all filesystems

### Freeze Userspace Processes
`freeze_processes` - Send every process to the refrigerator
`try_to_freeze_tasks(true)` - Freeze only userspace

### Lock Hotplug
`lock_device_hotplug`

### Allocate Memory Bitmaps
`create_basic_memory_bitmaps`

### Create Hibernation Image
`hibernation_snapshot`
`platform_begin` - `hibernation_ops->begin(PMSG_FREEZE)`
`hibernate_preallocate_memory`
`freeze_kernel_threads`
`dpm_prepare`
`suspend_console`
`pm_restrict_gfp_mask`
`dpm_suspend(PMSG_FREEZE)`
`create_image` - begin image creation process
`trace_suspend_resume`

### System Restore Point
`save_processor_state` - Arch-specific storage of CPU state
`swsusp_arch_suspend` - Save registers into the `saved_context` structure,
in its `pt_regs` substructure.


### Find and Copy All Important Pages
`swsusp_save` - create in-memory copy of all important pages.
`drain_local_pages`
`count_data_pages`
`count_highmem_pages`
`swsusp_alloc(&copy_bm, nr_pages, nr_highmem)`
`copy_data_pages(&copy_bm, &orig_bm)`

### Write Out All Important Pages to Swap
`swsusp_write` - swap out in-memory copy out to swapspace, along with an image header.

### Power Off
`swsusp_free`
`power_down`

### Restore from a Hibernation Image
`swsusp_swap_check` - Called before saving image, uses either configured
resume device, or just the first swap found.
`software_resume` - Resume from saved image
`swsusp_check` - Check for hibernation header with signature

## How to find a hibernate swap partition
## How to find a hibernate swap file
## How does hibernate data end up on disk


## Hibernation Modes

### Platform

### Shutdown

### Reboot

### Suspend
Requires `CONFIG_SUSPEND`

### Test Resume

## Linux Suspend 2 vs suspend 1

https://www.kernel.org/doc/html/latest/power/swsusp.html
https://www.kernel.org/doc/html/latest/power/basic-pm-debugging.html
https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html
