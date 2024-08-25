---
layout: post
title: "Linux Hibernation Code Begins"
description: "How does hibernation work on Linux?"
category:
tags: [hibernate]
---
## Begin True Hibernation

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
