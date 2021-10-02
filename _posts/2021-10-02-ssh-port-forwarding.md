---
layout: post
title: "SSH Port Forwarding and the Command Cargo Cult"
description: "How the internet seems to be collectively using ssh wrong"
category:
tags: []
---


## Someone is Wrong on the Internet
If you look up how to only forward ports with `ssh`, you may come across
solutions like this:
```
ssh -nNT -L 8000:example.com:80 user@bastion.example.com
```
Or perhaps this, if you also wanted to send `ssh` to the background:
```
ssh -NT -L 3306:db.example.com:3306 example.com &
```

Both of these use at least one option that is entirely redundant,
and the second can cause `ssh` to fail to connect if you happen to be
using password authentication.
However, they seem to still persist in various articles about `ssh` port forwarding.
I myself was using the first variation until just recently, and I figured
I would write this up to inform others who might be still using these
solutions.

The correct option for this situation is not `-nNT` but simply
`-N`, as in:
```
ssh -N -L 8000:example.com:80 user@bastion.example.com
```
If you want to also send `ssh` to the background,
then you'll want to add `-f` instead of using your shell's built-in `&`
feature, because you can then input passwords into `ssh` if necessary[^1]

[^1]: Not that you SHOULD be using `ssh` with password authentication anyway, but people do.

Honestly, that's the point of this article, so you can stop here
if you want. If you're looking for a detailed explaination of what
each of these options actually does, or if you have no idea what
I'm talking about, read on!

## What is SSH Port Forwarding?

`ssh` is a powerful tool for remote access to servers,
allowing you to execute commands on a remote machine.
It can also forward ports
through a secure tunnel with the `-L` and `-R` options.
Basically, you can forward a connection to a local port to a remote server
like so:
```
ssh -L 8080:other.example.com:80 ssh.example.com
```
In this example, you connect to `ssh.example.com` and then `ssh` forwards
any traffic on your local machine port 8080[^2]
to `other.example.com` port 80 via `ssh.example.com`.
This is a really powerful feature, allowing you to jump[^3] inside your firewall
with just an `ssh` server exposed to the world.

It can work in reverse as well with the `-R` option, allowing connections
on a remote host in to a server running on your local machine.
For example, say you were running a website on your local machine on port 8080
but wanted it accessible on `example.com` port 80[^4].
You could use something like:
```
ssh -R 8080:example.com:80 example.com
```

[^2]: Only on your loopback address by default, so that you're not allowing random people on your network to use your tunnel.
[^3]: In fact, `ssh` even supports [Jump Hosts](https://man.openbsd.org/OpenBSD-6.9/ssh#J), allowing you to automatically forward an `ssh` connection through another machine.
[^4]: I can't say I recommend a setup like this for anything serious, as you'd need to `ssh` as root to forward ports less than 1024. SSH forwarding is not for permanent solutions, just short-lived connections to machines that would be otherwise inaccessible.

The trouble with `ssh` port forwarding is that, absent any additional options,
you also open a shell on the remote machine.
If you're planning to both work on a remote machine and use it to forward
some connection, this is fine, but if you just need to forward a port quickly
and don't care about a shell at that moment, it can be annoying, especially since
if the shell closes `ssh` will close the forwarding port as well.

This is where the `-N` option comes in.

## SSH just forwarding ports
In the `ssh` manual page[^5], `-N` is explained like so:

> Do not execute a remote command.  This is useful for just forwarding ports.

[^5]: Specifically, my source is the ssh(1) manual page in OpenSSH 8.4, shipped as 1:8.4p1-5 in Debian bullseye.

This is all we need. It instructs `ssh` to run no commands on the remote server,
just forward the ports specified in the `-L` or `-R` options.
But people seem to think that there are a bunch of other necessary options,
so what do those do?

## SSH and stdin
`-n` controls how `ssh` interacts with [standard input](https://en.wikipedia.org/wiki/Standard_streams),
specifically telling it not to:

> Redirects stdin from /dev/null (actually, prevents reading from stdin).  This must be used when ssh is run in the
> background.  A common trick is to use this to run X11 programs on a remote machine.  For example, ssh -n
> shadows.cs.hut.fi emacs & will start an emacs on shadows.cs.hut.fi, and the X11 connection will be automatically for‐
> warded over an encrypted channel.  The ssh program will be put in the background.  (This does not work if ssh needs to
> ask for a password or passphrase; see also the -f option.)

## SSH passwords and backgrounding
`-f` sends `ssh` to background, freeing up the terminal in which you ran `ssh`
to do other things.

> Requests ssh to go to background just before command execution.  This is useful if ssh is going to ask for passwords
> or passphrases, but the user wants it in the background.  This implies -n.  The recommended way to start X11 programs
> at a remote site is with something like ssh -f host xterm.

As indicated in the description of `-n`, this does the same thing as using
[the shell's `&` feature](https://tldp.org/LDP/abs/html/special-chars.html#BGJOB)
with `-n`, but allows you to put in any necessary passwords first.

## SSH and pseudo-terminals
`-T` is a little more complicated than the others and has a very short
explanation:

> Disable pseudo-terminal allocation.

It has a counterpart in `-t`, which is explained a little better:

> Force pseudo-terminal allocation.  This can be used to execute arbitrary screen-based programs on a remote machine,
> which can be very useful, e.g. when implementing menu services.  Multiple -t options force tty allocation, even if ssh
> has no local tty.

As the description of `-t` indicates, `ssh` is allocating a pseudo-terminal on
the remote machine, not the local one.
However, I have confirmed[^6] that `-N` doesn't allocate a pseudo-terminal either,
since it doesn't run any commands.
Thus this option is entirely unnecessary.

[^6]: I just forwarded ports with `-N` and then logged in to that same machine and looked at psuedo-terminal allocations via `ps ux`. No terminal is associated with `ssh` connections using just the `-N` option.

### What's a pseudo-terminal?

This is a bit complicated, but basically it's an interface used in UNIX-like
systems, like Linux or BSD, that pretends to be a terminal
(thus pseudo-terminal).
Programs like your shell, or any text-based menu system made in libraries
like ncurses, expect to be connected to one (when used interactively at least).
Basically it fakes as if the input it is given
(over the network, in the case of `ssh`) was typed on a physical terminal
device and do things like raise an interrupt (SIGINT) if Ctrl+C is pressed.

## Why?

I don't know why these incorrect uses of `ssh` got passed around as correct,
but I suspect it's a form of [cargo cult](https://en.wikipedia.org/wiki/Cargo_cult_programming),
where we use example commands others provide and don't question what they do.
One stack overflow answer I read that provided these options seemed to think
`-T` was disabling the local pseudo-terminal, which might go some way towards
explaining why they thought it was necessary.

I guess the moral of this story is to question everything and actually read
the manual, instead of just googling it.
