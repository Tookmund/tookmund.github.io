---
layout: post
title: "AAC and Debian"
description: "The current state of the AAC codec in Debian, or why my Apple AirPods don't work"
tags: [debian,bluetooth,patents]
---

Currently, in a default installation of Debian with the GNOME desktop,
Bluetooth headphones that require the AAC codec[^apple] cannot be used.
[As the Debian wiki outlines](https://wiki.debian.org/BluetoothUser/a2dp#AAC_codec),
using the AAC codec over Bluetooth, while technically supported by
PipeWire, is explicitly disabled in Debian at this time.
This is because the `fdk-aac` library needed to enable this support is currently
in the `non-free` component of the repository, meaning that PipeWire, which
is in the `main` component, cannot depend on it.

[^apple]: Such as, for example, any Apple AirPods, which only support AAC AFAICT.

# How to Fix it Yourself

If what you, like me, need is simply for Bluetooth Audio to work with AAC
in Debian's default desktop environment[^default],
then you'll need to rebuild the `pipewire` package to include the
AAC codec. While the current version in Debian `main` has been built with AAC
deliberately disabled, it is trivial to enable if you can install a version
of the `fdk-aac` library.

[^default]: Which, as of Debian 12 is GNOME 3 under Wayland with PipeWire.

**I preface this with the usual caveats when it comes to patent
and licensing controversies. I am not a lawyer, building this package and/or
using it could get you into legal trouble.**

These instructions have only been tested on an up-to-date copy of Debian 12.

1. Install `pipewire`'s build dependencies
```
sudo apt install build-essential devscripts
sudo apt build-dep pipewire
```

2. Install `libfdk-aac-dev`
```
sudo apt install libfdk-aac-dev
```
If the above doesn't work you'll likely need to enable non-free and try again
```
sudo sed -i 's/main/main non-free/g' /etc/apt/sources.list
sudo apt update
```
Alternatively, if you wish to ensure you are maximally license-compliant and
patent un-infringing[^ianal],
you can instead build `fdk-aac-free` which includes only those components
of AAC that are known to be patent-free[^ianal].
This is what should eventually end up in Debian to resolve this problem
(see below).
```
sudo apt install git-buildpackage
mkdir fdk-aac-source
cd fdk-aac-source
git clone https://salsa.debian.org/multimedia-team/fdk-aac
cd fdk-aac
gbp buildpackage
sudo dpkg -i ../libfdk-aac2_*deb ../libfdk-aac-dev_*deb
```

3. Get the `pipewire` source code
```
mkdir pipewire-source
cd pipewire-source
apt source pipewire
```
This will create a bunch of files within the `pipewire-source` directory,
but you'll only need the `pipewire-<version>` folder, this contains all the
files you'll need to build the package, with all the debian-specific patches
already applied.
Note that you don't want to run the `apt source` command as root, as it will
then create files that your regular user cannot edit.

4. Fix the dependencies and build options
To fix up the build scripts to use the fdk-aac library,
you need to save the following as `pipewire-source/aac.patch`
```
--- debian/control.orig
+++ debian/control
@@ -40,8 +40,8 @@
                modemmanager-dev,
                pkg-config,
                python3-docutils,
-               systemd [linux-any]
-Build-Conflicts: libfdk-aac-dev
+               systemd [linux-any],
+               libfdk-aac-dev
 Standards-Version: 4.6.2
 Vcs-Browser: https://salsa.debian.org/utopia-team/pipewire
 Vcs-Git: https://salsa.debian.org/utopia-team/pipewire.git
--- debian/rules.orig
+++ debian/rules
@@ -37,7 +37,7 @@
 		-Dauto_features=enabled \
 		-Davahi=enabled \
 		-Dbluez5-backend-native-mm=enabled \
-		-Dbluez5-codec-aac=disabled \
+		-Dbluez5-codec-aac=enabled \
 		-Dbluez5-codec-aptx=enabled \
 		-Dbluez5-codec-lc3=enabled \
 		-Dbluez5-codec-lc3plus=disabled \
```
Then you'll need to run `patch` from within the `pipewire-<version>` folder
created by `apt source`:
```
patch -p0 < ../aac.patch
```

5. Build `pipewire`
```
cd pipewire-*
debuild
```
Note that you will likely see an error from `debsign` at the end of this process,
this is harmless, you simply don't have a GPG key set up to sign your
newly-built package[^gpg-key]. Packages don't need to be signed to be installed,
and debsign uses a somewhat non-standard signing process that dpkg does not
check anyway.

[^gpg-key]: And if you DO have a key setup with `debsign` you almost certainly don't need these instructions.

6. Install `libspa-0.2-bluetooth`
```
sudo dpkg -i libspa-0.2-bluetooth_*.deb
```

7. Restart PipeWire and/or Reboot
```
sudo reboot
```
Theoretically there's a set of services to restart here that would
get pipewire to pick up the new library, probably just pipewire itself.
But it's just as easy to restart and ensure everything is using the correct
library.

# Why

This is a slightly unusual situation, as the `fdk-aac` library is licensed
under what
[even the GNU project](https://www.gnu.org/licenses/license-list.html#fdk)
acknowledges is a free software license.
However, [this license](https://android.googlesource.com/platform/external/aac/+/master/NOTICE)
explicitly informs the user that they need to acquire
a patent license to use this software[^correction]:

> 3\.    NO PATENT LICENSE
>
> NO EXPRESS OR IMPLIED LICENSES TO ANY PATENT CLAIMS, including without
> limitation the patents of Fraunhofer, ARE GRANTED BY THIS SOFTWARE LICENSE.
> Fraunhofer provides no warranty of patent non-infringement with respect to this
> software.
> You may use this FDK AAC Codec software or modifications thereto only for
> purposes that are authorized by appropriate patent licenses.

To quote the GNU project:
> Because of this, and because the license author is a known patent aggressor,
> we encourage you to be careful about using or redistributing software under
> this license: you should first consider whether the licensor might aim to
> lure you into patent infringement.

[^correction]: This was originally phrased as "explicitly does not grant any patent rights." It was [pointed out on Hacker News](https://news.ycombinator.com/item?id=39503761) that this is not exactly what it says, as it also includes a specific note that you'll need to acquire your own patent license. I've now quoted the relevant section of the license for clarity.


AAC is covered by a number of patents, which expire at some point in the 2030s[^patentexpire].
As such the current version of the library is potentially legally dubious to ship with
any other software, as it could be considered patent-infringing[^ianal].

[^ianal]: I'm not a lawyer, I don't know what kinds of infringement might or might not be possible here, do your own research, etc.

[^patentexpire]: Wikipedia claims the "base" patents expire in 2031, with the extensions expiring in 2038, but its [source for these claims](https://hydrogenaud.io/index.php/topic,121109.0.html) is some guy's spreadsheet in a forum. The same discussion also brings up Wikipedia's claim and casts some doubt on it, so I'm not entirely sure what's correct here, but I didn't feel like doing a patent deep-dive today. If someone can provide a clear answer that would be much appreciated.

## Fedora's solution

Since 2017, Fedora has included a modified version of the library
as fdk-aac-free, see the [announcement](https://lists.fedoraproject.org/archives/list/devel@lists.fedoraproject.org/thread/F64JBJI2IZFT2A5QDXGHNMPALCQIVJAX/) and the [bugzilla bug requesting review](https://bugzilla.redhat.com/show_bug.cgi?id=1501522).

This version of the library includes only the AAC LC profile, which is believed
to be entirely patent-free[^ianal].

Based on this, there is an open bug report in Debian requesting that the
[`fdk-aac` package be moved to the main component](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=981285)
and that the
[`pipwire` package be updated to build against it](https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1021370).

## The Debian NEW queue

To resolve these bugs, a version of `fdk-aac-free` has been uploaded to Debian
by Jeremy Bicha.
However, to make it into Debian proper, it must first pass through the
[ftpmaster's NEW queue](https://ftp-master.debian.org/new.html).
The [current version of fdk-aac-free](https://ftp-master.debian.org/new/fdk-aac-free_2.0.2-3.html)
has been in the NEW queue since July 2023.

Based on conversations in some of the bugs above, it's been there since at least 2022[^jbicha].

[^jbicha]: According to Jeremy Bícha: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1021370#17

I hope this helps anyone stuck with AAC to get their hardware working for them
while we wait for the package to eventually make it through the NEW queue.

[Discuss on Hacker News](https://news.ycombinator.com/item?id=39503266)
