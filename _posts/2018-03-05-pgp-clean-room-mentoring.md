---
layout: post
title: "PGP Clean Room: GSoC Mentors Wanted"
description: "Mentors Wanted for PGP Clean Room in Debian's GSoC 2018"
category: 
tags: [debian]
date: 2018-03-05 20:57:00 -0500
---


I am a prospective GSoC student and I would be very interested in working on 
the [PGP Clean Room project](https://wiki.debian.org/SummerOfCode2018/Projects/CleanRoomForPGPKeyManagement) 
for Debian this summer. Unfortunately the current confirmed mentor, Daniel 
Pocock, is involved in the admin team and possibly in multiple other GSoC
projects as well. So I am looking for another mentor who would be willing to
help me on this project.

The Problems of PGP
-------------------
PGP is essential to Debian and many other free software projects. It secures 
almost everything these projects distribute on the Internet. But for new users 
it can be difficult to set up. It typically requires complex command line 
interactions that the user doesn't really understand, leading to much 
confusion and silly mistakes. Best practice is to generate the keys offline
and store them on a set of separate storage devices, but there isn't currently
a tool to handle this well at all. I eventually got TAILS to serve this
purpose but it was more difficult than it should have been.


What the PGP Clean Room will do
-------------------------------
The PGP Clean room will walk new users through setting up a set of USB
flash drives or sd cards as a raid disk, generating new PGP keys,
storing them there, and then exporting subkeys either on a separate USB
stick or a security key like a Yubikey. I'd also like to add the ability
to do things like revoke keys or extend expiration dates for them
through the application. Additionally, I would like to add an 
import feature for new keys and support for X.509 key management.
My current plan is to write a [python-newt](https://packages.debian.org/stretch/python3-newt)
application for this and use [GPGME's python bindings](https://packages.debian.org/stretch/python3-gpgme)
to generate the keys.

My Qualifications
-----------------

I am currently a package maintainer for 
[a couple packages](https://qa.debian.org/developer.php?email=tookmund%40gmail.com)
in Debian.
I'm a freshman intending to major in Computer Science at the College of
William and Mary in Virginia, USA. I've taken a few college-level CS 
classes, but as can been seen from 
[my Github profile](https://github.com/Tookmund), I'm mostly self-taught.

I've started working on this a little bit and published it on
[Debian's Gitlab](https://salsa.debian.org/tookmund-guest/make-pgp-clean-room).


Links
-----

[PGP Clean Room GSoC Project](https://wiki.debian.org/SummerOfCode2018/Projects/CleanRoomForPGPKeyManagement)

[PGP Clean Room Wiki Page](https://wiki.debian.org/OpenPGP/CleanRoomLiveEnvironment)

[GSoC Mentor's Guide](https://google.github.io/gsocguides/mentor/)

