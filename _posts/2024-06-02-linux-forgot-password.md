---
layout: post
title: What to Do When You Forget Your Root Password
description: How to recover with physical access to any linux machine, including Raspbian / Raspberry Pi OS
category: 
tags:
  - raspberry pi
  - linux
  - root
  - password
---

Forgetting your root password would initially seem like a problem requiring
a full re-install, one that you can't easily recover from without wiping
everything away.

Forgetting your user password can of course be solved by changing it as root,
as in the following, which changes the password for user `jacob`:
```
# passwd jacob
```
but only the `root` user can change their own password,
so you need to somehow get `root` access in order to do so.

## Changing Root's Password with Sudo
This one is probably obvious, but if you have a user with the ability to use
`sudo`, then you can change `root`'s password without access to the `root`
account by running:
```
$ sudo passwd
```
which will reset the password for the `root` account without requiring the
existing password.

## Boot Directly to a Shell

Getting `root` access to any Linux machine you have physical access to
is surprisingly simple.
You can just boot the machine directly into a `root` shell without any access
control, i.e. passwords.

### Why You Should Always Encrypt Your Storage[^encrypt]

[^encrypt]: Not that this is the only reason, anyone with physical access to your machine could also boot it into another operating system they control, or just remove your storage device and put it into another computer, or probably other things I'm not thinking of now. You should always encrypt your devices.

To boot directly to a shell you need to append the following text to
the [kernel command line](https://www.kernel.org/doc/html/v4.14/admin-guide/kernel-parameters.html):
```
init=/bin/sh
```
(You could use pretty much any program here, but you're putting your system into a weird state doing this, and so I'd recommend the simplest approach.)

### GRUB

GRUB will allow you to edit boot parameters on startup using the `e`
key. You'll then be presented with a editor[^emacs] that you can
use to change the kernel command line by appending to the `linux` line.

[^emacs]: The editor uses emacs-like keybindings. [The manual](https://www.gnu.org/software/grub/manual/grub/grub.html#Command_002dline-interface) includes a list of all the options available.

E.g. If your editor looks like this:
```
        load_video
        insmod gzio
        if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
        insmod part_gpt
        insmod ext2
        search --no-floppy --fs-uuid --set=root abcd1234-5678-0910-1112-abcd12345678
        echo    'Loading Linux 6.1.0-21-amd64 ...'
        linux   /boot/vmlinuz-6.1.0-21-amd64 root=UUID=abcd1234-5678-0910-1112-abcd12345678 ro  quiet
        echo    'Loading initial ramdisk ...'
        initrd  /boot/initrd.img-6.1.0-21-amd64
```
Then you would add `init=/bin/sh` like so:
```
        load_video
        insmod gzio
        if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
        insmod part_gpt
        insmod ext2
        search --no-floppy --fs-uuid --set=root abcd1234-5678-0910-1112-abcd12345678
        echo    'Loading Linux 6.1.0-21-amd64 ...'
        linux   /boot/vmlinuz-6.1.0-21-amd64 root=UUID=abcd1234-5678-0910-1112-abcd12345678 ro  quiet init=/bin/sh
        echo    'Loading initial ramdisk ...'
        initrd  /boot/initrd.img-6.1.0-21-amd64
```

Once you've edited it you can start your machine with `Ctrl+x`, as you can
see from the prompt text under the editor.

### Raspberry Pi `cmdline.txt`
On a Raspberry Pi you'll want to append the above to only line of the
`cmdline.txt` file on the boot partition of the SD card.
This is the first partition of the disk, the one that is `FAT32`.

You'll need to do this on another machine, since if you had `root` access
to edit `cmdline.txt` you could also just change your password.

As it is a `FAT32` partition on an SD card, it should be editable on any other
machine that supports SD cards.

E.g. If your `cmdline.txt` looks like this
```
console=serial0,115200 console=tty1 root=PARTUUID=fb33757d-02 rootfstype=ext4 fsck.repair=yes rootwait quiet
```
Then you would add `init=/bin/sh` like so:
```
console=serial0,115200 console=tty1 root=PARTUUID=fb33757d-02 rootfstype=ext4 fsck.repair=yes rootwait quiet init=/bin/sh
```

## Mount Read / Write

Since you're replacing the [init process](https://en.wikipedia.org/wiki/Init)
of the machine with a shell, no other processes will be running.

Also, your root filesystem will be mounted read-only,
as `init` is expected to remount it read-write as needed.
```
# mount -o remount,rw /
```

## Change Root Password

Once you've remounted the root filesystem, all that's needed is to
run the `passwd` command.
```
# passwd
```
Since you're running the command as `root` you won't need to provide your
existing password, and will only need to type a new password twice.

Now of course you simply need to remember that password in order to
ensure you don't need to do this again.

## Reboot Safely

You now cannot follow the standard reboot process here, as you're only running
one process.

Therefore it's important to put your root filesystem back into read-only before
powering off your machine:
```
# mount -o remount,ro /
```

Once you've done that you just need to hold down the power button until the
machine completely powers off or pull the plug.

And then you're done! Boot the computer again and you'll have everything
working as normal, with a `root` password you remember.
