---
layout: post
title: "The Unexpected Importance of the Trailing Slash"
description: "The Unexpected Importance of the Trailing Slash in Directory Paths"
category:
tags:
---

For many using Unix-derived systems today, we take for granted
that `/some/path` and `/some/path/` are the same.
Most shells will even add a trailing slash for you when you press the Tab key
after the name of a directory or a symlink to one.

However, many programs treat them as subtly different in certain cases,
which I outline below, as all three have tripped me up
in various ways[^threetrailing].

[^threetrailing]: I'm sure there are probably more than just these three cases, but these are the three I'm familar with. If you know of more, please [tell me about them!](mailto:trailingslash@tookmund.com).

## POSIX Symlinks

The first use of the trailing slash in a distinguishing way is recorded in
[POSIX](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap04.html#tag_04_13)[^posixadditional]
which states[^historical]:
> When the final component of a pathname is a symbolic link, the standard requires that a trailing <slash> causes the link to be followed. This is the behavior of historical implementations. For example, for /a/b and /a/b/, if /a/b is a symbolic link to a directory, then /a/b refers to the symbolic link, and /a/b/ refers to the directory to which the symbolic link points.

[^posixadditional]: Some additional relevant sections are the [Path Resolution Appendix](https://pubs.opengroup.org/onlinepubs/9699919799/xrat/V4_xbd_chap04.html#tag_21_04_13) and the section on [Symbolic Links](https://pubs.opengroup.org/onlinepubs/9699919799/xrat/V4_xbd_chap03.html#tag_21_03_00_75).

[^historical]: The sentence "This is the behavior of historical implementations" implies that this probably originated in some ancient Unix derivative, possibly BSD or even the original Unix. I don't really have a source on that though, so please [reach out](mailto:trailingslash@tookmund.com) if you happen to have any more knowledge on what this refers to.


This leads to some unusual consequences.
For example, if you have the following structure
(which will be used in all shell examples throughout this article):
```
$ ls -la
total 12
drwxr-xr-x   3 jacob jacob 4096 Mar 29 23:06 .
drwxr-xr-x 166 jacob jacob 4096 Mar 29 22:22 ..
drwxr-xr-x   2 jacob jacob 4096 Mar 29 23:07 a
lrwxrwxrwx   1 jacob jacob    1 Mar 29 22:22 b -> a
$ ls a
afile
```

And then do the following:
```
rm -rvf b/
```

The output may not be what you expect:
```
removed 'b/afile'
```

Whereas if you remove the trailing slash, you just remove the symlink:
```
$ rm -rvf b
removed 'b'
```

The `find` command acts the same way, not treating the symlink as a directory
unless the trailing slash is added:
```
$ find b -name afile
$ find b/ -name afile
b/afile
```

On Linux[^renametrailing], `mv` will not "rename the indirectly referenced directory and not the symbolic link,"
despite the [coreutils documentation's claims to the contrary](https://www.gnu.org/software/coreutils/manual/html_node/Trailing-slashes.html),

[^renametrailing]: ["unless the source is a directory trailing slashes give -ENOTDIR"](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/fs/namei.c#n4797)

```
$ mv b/ c
mv: cannot move 'b/' to 'c': Not a directory
$ mkdir c
$ mv b/ c
mv: cannot move 'b/' to 'c/b': Not a directory
$ mv b/ c/
mv: cannot move 'b/' to 'c/b': Not a directory
$ mv b c
$ ls c
b
```
This is probably for the best, as it is very confusing behavior,
but deviates from the behavior of other Unixes, such as Solaris or FreeBSD,
where this works just fine[^otherunixes]:
```
$ mv b/ c
$ ls
b	c
```

[^otherunixes]: I installed and tested FreeBSD 12.0 and OmniOS 5.11 to verify this

The trailing slash does also have one advantage with `mv`, even on Linux,
in that is it does not allow you to move a file to a non-existant directory,
or move a file that you expect to be a directory that isn't.
```
$ mv a/afile d/
mv: cannot move 'a/afile' to 'd/': Not a directory
$ touch d
$ mv d/ a
mv: cannot stat 'd/': Not a directory
$ mv d a
$ ls a
afile  d
```

## rsync

The command `rsync` handles a trailing slash in an unusual way that
trips up many new users.
The [rsync man page](https://linux.die.net/man/1/rsync) notes:
> A trailing slash on the source changes this behavior to avoid creating an additional directory  level  at  the  destination.
> You can think of a trailing / on a source as meaning "copy the contents of this directory" as opposed to "copy the directory
> by name", but in both cases the attributes of the containing directory are transferred to the containing  directory  on  the
> destination.

That is to say, a command that looks like this:
```
rsync -av /a/b /a
```
does nothing, as `b` already exists in `a`, while the following command:
```
rsync -av /a/b/ /a
```
copies the CONTENTS of directory `b` to directory `a`

## Dockerfile COPY
The Dockerfile `COPY` command also cares about the presence of the trailing slash,
using it to determine whether the destination should be considered a file or directory.

The [Docker documentation](https://docs.docker.com/engine/reference/builder/#copy)
explains the rules of the command thusly:
>	COPY [--chown=<user>:<group>] <src>... <dest>
...
>   If `<src>` is a directory, the entire contents of the directory are copied, including filesystem metadata.
>
>    Note: The directory itself is not copied, just its contents.
>
>    If `<src>` is any other kind of file, it is copied individually along with its metadata. In this case, if `<dest>` ends with a trailing slash `/`, it will be considered a directory and the contents of `<src>` will be written at `<dest>/base(<src>)`.
>
>    If multiple `<src>` resources are specified, either directly or due to the use of a wildcard, then `<dest>` must be a directory, and it must end with a slash `/`.
>
>    If `<dest>` does not end with a trailing slash, it will be considered a regular file and the contents of `<src>` will be written at `<dest>`.
>
>    If `<dest>` doesn’t exist, it is created along with all missing directories in its path.

