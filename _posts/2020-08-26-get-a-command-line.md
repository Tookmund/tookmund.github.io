---
layout: post
tag: ACM@WM
---

How to access a command line on your laptop without installing Linux.

Linux is great, and I recommend trying it out, whether on real hardware
or in a virtual machine, to anyone interested in Computer Science.

However, the process can be quite involved, and sometimes you don't want to
change your whole operating system or sort out installing virtual machines.

Fortunately, these days you can try out one of Linux's greatest features, the
command line, without going through all that hassle.

## Mac
If you have a Mac, all you need to do is open `Terminal.app`, which is usually
found under `/Applications/Utilities`. Note that Mac now defaults to zsh
instead of bash, which is usually the shell used on Linux.
This shouldn't matter, but it's something you should be aware of.

## Windows
On Windows, things are much more complex. There's always [Powershell](https://docs.microsoft.com/en-us/powershell/),
but if you want a true [Unix shell](https://en.wikipedia.org/wiki/Unix_shell)
experience like you'd get on Linux,
you'll need to install the [Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/install-win10).
This allows you to run Linux programs on your Windows 10 computer.

This boils down to opening Powershell
(open the start menu, search for "powershell") as an administrator
(right-click, then "Run as Administrator," then click "Yes" or enter an
administrator's password when the [UAC prompt](https://docs.microsoft.com/en-us/windows/security/identity-protection/user-account-control/how-user-account-control-works#the-uac-user-experience)
appears).
In this new Powershell window, you need to run the following command to enable WSL:
```
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
```
When this command executes successfully you should see the following output:
![WSL Sucess](/assets/WSL.png)

After this output appears, you'll need to reboot your machine before you can
continue.

Once your machine is rebooted, you need to install a Linux distribution.
Different communities and companies ship their own versions of Linux and the
various services and utilities required to use it, and these versions are
called "distributions."

If you're not sure which one to use, I would recommend [Ubuntu](https://www.microsoft.com/store/apps/9n6svws3rx71),
as it was the distribution first integrated into WSL, and it's a common
distribution for new users.

After installing your chosen distribution, you'll need to perform the first-time
setup. You'll just need to run it, as it is now installed as a program on your
computer, and then it will walk you through the setup process, which requires
you to create [a new user account for your Linux distribution](https://docs.microsoft.com/en-us/windows/wsl/user-support).

This does not need to be the same as your Windows username and password,
and it's probably safer if it isn't.
You'll need to remember that password for running administrative commands with
`sudo`.
