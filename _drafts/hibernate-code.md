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

### Show and Store Functions
These two files are defined using the `power_attr` macro:
```
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

autosleep is a mechanisms [originally from Android](https://lwn.net/Articles/479841/)
that sends the entire system to either suspend or hibernate whenever it is
not actively working on anything.

TODO: Wakelocks

## The Steps of Hibernation

### Check if Hibernation is Available
We begin by confirming that we actually can perform hibernation,
via the `hibernation_available` function.
```
if (!hibernation_available()) {
	pm_pr_dbg("Hibernation not available.\n");
	return -EPERM;
}
```
```
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
TODO
```
unsigned int lock_system_sleep(void)
{
	unsigned int flags = current->flags;
	current->flags |= PF_NOFREEZE;
	mutex_lock(&system_transition_mutex);
	return flags;
}
EXPORT_SYMBOL_GPL(lock_system_sleep);
```
#define PF_NOFREEZE		0x00008000	/* This thread should not be frozen */
```

Then we grab the hibernate-specific semaphore to ensure no one can open a
snapshot or resume from it while we perform hibernation.
Additionally this lock is used to prevent ` hibernate_quiet_exec`,
which is used by the `nvdimm` driver to active its firmware with all
processes and devices frozen, ensuring it is the only thing running at that
time.

```
bool hibernate_acquire(void)
{
	return atomic_add_unless(&hibernate_atomic, -1, 0);
}
```

### Prepare Console
`pm_prepare_console`

### Notify PM Call Chain
`pm_notifier_call_chain_robust(PM_HIBERNATION_PREPARE, PM_POST_HIBERNATION)`

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
