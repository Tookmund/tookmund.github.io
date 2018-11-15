---
layout: post
title: "PGP Clean Room Beta"
description: "Beta for my GSOC project now available! Testers wanted!"
category: 
tags: [debian]
date: 2018-07-16 21:10:00 -0400
---


My Google Summer of Code 2018 Project is finally far enough along that I feel that it should have a proper public beta.

PGP Clean Room
--------------
This summer I'm working on the PGP Clean Room Live CD project. The goal of this project is to make it easy to create and maintain
an offline GPG key. It creates and backs up your GPG key to USB drives which can be stored in a safe place, and exports subkeys for you to use,
either via an export USB or a PGP smartcard. It also allows you to sign other people's keys, revoke your own keys, and change your keys expiration dates. The live system
is built on [live-build](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html)
with an [added python application](https://salsa.debian.org/tookmund-guest/pgpcr) (using [GPGME](https://www.gnupg.org/software/gpgme/index.html) to manage keys) and all networking functionality removed.

Testers Wanted
--------------
I would love to get some feedback on this build and how it could be improved.
You can report bugs via [salsa.d.o](https://salsa.debian.org/tookmund-guest/pgpcr/issues)

Downloads
---------

Prebuilt ISOs are available [here](http://pgpcr.ouvaton.org/pgpcr-beta2.iso) ([sig](http://pgpcr.ouvaton.org/pgpcr-beta2.iso.sig))
or on [Google Drive](https://drive.google.com/open?id=1vVydysUFuim5q2upymP98u-IuI6qQ-wH) ([sig](https://drive.google.com/open?id=1wYt508w5lpwh1Fuw3_qE74EYXAKHocxw))

The source code is available on [salsa.d.o](https://salsa.debian.org/tookmund-guest/make-pgp-clean-room)

Screenshots
-----------

![main menu](/assets/pgpcr/beta2-mainmenu.png)
Main Menu

![load menu](/assets/pgpcr/beta2-loadmenu.png)
Load Menu

![advanced menu](/assets/pgpcr/beta2-advancedmenu.png)
Advanced Menu

![signing subkey](/assets/pgpcr/beta2-signingsubkey.png)
Signing subkey

![subkey algorithm](/assets/pgpcr/beta2-subkeyalgorithm.png)
Picking subkey algorithm

![pick disk](/assets/pgpcr/beta2-pickdisk.png)
Picking a backup disk (in QEMU)
