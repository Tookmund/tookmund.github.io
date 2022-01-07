---
layout: post
title: "Linux Hibernation Documentation"
description: "How does hibernating a computer work anyway?"
category:
tags: [hibernate]
---

Recently I've been curious about how hibernation works on Linux,
as it's an interesting interaction between hardware and software.
There are some notes in the [Arch wiki](https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate)
and the [kernel documentation](https://www.kernel.org/doc/html/latest/power/swsusp.html)
(as well as some kernel documentation on [debugging hibernation](https://www.kernel.org/doc/html/latest/power/basic-pm-debugging.html)
and on [sleep states more generally](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html)),
and of course the [ACPI Specification](https://uefi.org/specs/ACPI/6.4/)

## The Formal Definition
ACPI (Advanced Configuration and Power Interface) is,
[according to the spec](https://uefi.org/specs/ACPI/6.4/Frontmatter/Overview/Overview.html),
"an architecture-independent power management and configuration framework that
forms a subsystem within the host OS" which defines "a hardware register set to
define power states."

ACPI defines four [global system states](https://uefi.org/specs/ACPI/6.4/02_Definition_of_Terms/Definition_of_Terms.html#global-system-state-definitions)
G0, working/on, G1, sleeping, G2, soft off, and G3, mechanical off[^mechoff].
Within G1 there are 4 [sleep states](https://uefi.org/specs/ACPI/6.4/16_Waking_and_Sleeping/sleeping-states.html),
numbered S1 through S4.
There are also S0 and S5, which are equivalent to G0 and G2 respectively[^gstates].

[^mechoff]: The difference between soft and mechanical off is that mechanical off is "entered and left by a mechanical means (for example, turning off the system’s power through the movement of a large red switch)"

[^gstates]: It's unclear to me why G and S states overlap like this. I assume this is a relic of an older spec that only had S states, but I have not as yet found any evidence of this. If someone has any information on this, please [let me know](mailto:hibernate@tookmund.com) and I'll update this footnote.

### Sleep
[According to the spec](https://uefi.org/specs/ACPI/6.4/16_Waking_and_Sleeping/sleeping-states.html),
the ACPI S1-S4 states all do the same thing from the operating system's perspective, but each saves progressively more power,
so the operating system is expected to pick the deepest of these states when entering sleep.
However, most operating systems[^machibernate] distinguish between S1-S3, which are typically referred to as sleep or suspend,
and S4, which is typically referred to as hibernation.

[^machibernate]: Of the operating systems I know of that support ACPI sleep states (I checked Windows, Mac, Linux, and the three BSDs[^netbsd]), only MacOS does not allow the user to deliberately enable hibernation, instead supporting a [hybrid suspend](#hybrid-suspend) it calls [safe sleep](https://support.apple.com/guide/mac-help/what-is-safe-sleep-mh10328/mac)

[^netbsd]: Interestingly NetBSD has a setting to enable hibernation, but [does not actually support hibernation](https://www.netbsd.org/docs/guide/en/chap-power.html#chap-power-acpi-sleep-states)

### S1: CPU Stop and Cache Wipe
The CPU caches are wiped and then the CPU is stopped, which the spec notes is equivalent to the WBINVD instruction followed by
the STPCLK signal on x86.
However, nothing is powered off.

### S2: Processor Power off
The system stops the processor and most system clocks (except the real time clock),
then powers off the processor.
Upon waking, the processor will not continue what it was doing before, but instead use its reset vector[^resetvector].

[^resetvector]: "The reset vector of a processor is the default location where, upon a reset, the processor will go to find the first instruction to execute. In other words, the reset vector is a pointer or address where the processor should always begin its execution. This first instruction typically branches to the system initialization code." [Xiaocong Fan, Real-Time Embedded Systems, 2015](https://www.sciencedirect.com/topics/engineering/reset-vector)

### S3: Suspend/Sleep (Suspend-to-RAM)
Mostly equivalent to S2, but hardware ensures that only memory and whatever other hardware memory requires are powered.

### S4: Hibernate (Suspend-to-Disk)
In this state, all hardware is completely powered off and an image of the system is written to disk,
to be restored from upon reapplying power.
Writing the system image to disk can be handled by the operating system if supported, or by the firmware.

## Linux Sleep States
Linux has its own [set of sleep states](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html)
which mostly correspond with ACPI states.

### Suspend-to-Idle
This is a software only sleep that puts all hardware into the lowest power state it can, suspends timekeeping,
and [freezes userspace processes](https://www.kernel.org/doc/html/latest/power/freezing-of-tasks.html).

All userspace and some kernel threads[^kernelnofreeze], except those tagged with `PF_NOFREEZE`,
are frozen before the system enters a sleep state.
Frozen tasks are sent to the `__refrigerator()`, where they set `TASK_UNINTERRUPTIBLE` and
`PF_FROZEN` and infinitely loop until `PF_FROZEN` is unset[^freezer].

This prevents these tasks from doing anything during the imaging process.
Any userspace process running on a different CPU while the kernel is trying to create a memory image would cause havoc.
This is also done because any filesystem changes made during this would be lost and could cause the filesystem and its related
in-memory structures to become inconsistent.
Also, creating a hibernation image requires about 50% of memory free, so no tasks should be allocating memory,
which freezing also prevents.

[^kernelnofreeze]: All kernel threads are tagged with `PF_NOFREEZE` by default, so they must specifically opt-in to task freezing.

[^freezer]: This is not from the docs, but from [`kernel/freezer.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/kernel/freezer.c?h=v5.15&id=8bb7eca972ad531c9b149c0a51ab43a417385813#n55) which also notes "Refrigerator is place where frozen processes are stored :-)."

### Standby
This is equivalent to [ACPI S1](#s1-cpu-stop-and-cache-wipe).

### Suspend-to-RAM
This is equivalent to [ACPI S3](#s3-suspendsleep-suspend-to-ram).

### Hibernation
Hibernation is mostly equivalent to [ACPI S4](#s4-hibernate-suspend-to-disk)
but does not require S4, only requiring "low-level code for resuming the system to be present for the underlying CPU architecture"
according to the [Linux sleep state docs](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html#hibernation).

To hibernate, everything is stopped and the kernel takes a snapshot of memory.
Then, the system writes out the memory image to disk.
Finally, the system either enters S4 or turns off completely.

When the system restores power it boots a new kernel, which looks for a hibernation image and loads it into memory.
It then overwrites itself with the hibernation image and jumps to a resume area of the original kernel[^lowlevelresume].
The resumed kernel restores the system to its previous state and resumes all processes.

[^lowlevelresume]: This is the operation that [requires](https://www.kernel.org/doc/html/latest/admin-guide/pm/sleep-states.html#hibernation) "special architecture-specific low-level code".

### Hybrid Suspend
Hybrid suspend does not correspond to an official ACPI state, but instead is effectively a combination
of S3 and S4.
The system writes out a hibernation image, but then enters suspend-to-RAM. 
If the system wakes up from suspend it will discard the hibernation image,
but if the system loses power it can safely restore from the hibernation image.
