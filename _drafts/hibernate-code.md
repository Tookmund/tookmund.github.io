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

## The Steps of Hibernation

### Check if Hibernation is Available
`hibernation_available`
```
bool hibernation_available(void)
{
	return nohibernate == 0 &&
		!security_locked_down(LOCKDOWN_HIBERNATION) &&
		!secretmem_active() && !cxl_mem_active();
}
```

### Grab Locks

`lock_system_sleep`

`hibernate_acquire`


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
