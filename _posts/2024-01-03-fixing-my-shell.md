---
layout: post
title: Fixing My Shell
description: Correctly setting up my shell initialization files, and how you can too!
---

For an embarassingly long time, my shell has unnecessarily tried to
initialize a console font in every kind of interactive terminal.

This leaves the following error message in my terminal:
```
Couldn't get a file descriptor referring to the console.
```

It even shows up twice when running tmux!

Clearly I've done something horrible to my configuration,
and now I've got to clean it up.

## How does Shell Initialization Work?

The precise files a shell reads at start-up is somewhat complex, and defined
by this excellent chart [^chart]:

![Shell Startup Flowchart](/assets/shell-startup-actual.svg)

[^chart]: This chart comes from the excellent [Shell Startup Scripts](https://blog.flowblok.id.au/2013-02/shell-startup-scripts.html) article by Peter Ward. I've generated the SVG from the [graphviz source](https://heptapod.host/flowblok/shell-startup/-/blob/branch/default/diagram/impl-actual.dot) linked in the article.

For the purposes of what I'm trying to fix, there are two paths that matter.
 - Interactive login shell startup
 - Interactive non-login shell startup

As you can see from the above, trying to distinguish these two paths in `bash`
is an absolute mess.
`zsh`, in contrast, is much cleaner and allows for a clear distinction
between these two cases, with login shell configuration files as a superset of
configuration files used by non-login shells.

## How did we get here?

I keep my configuration files in a [config](https://github.com/tookmund/config)
repository.

Some time ago I got quite frustrated at this whole shell initialization thing,
and just linked everything together in one `profile` file:
```
.mkshrc -> config/profile
.profile -> config/profile
```

This appears to have created this mess.

## Move to ZSH

I've wanted to move to `zsh` for a while, and took this opportunity to do so.
So my new configuration files are `.zprofile` and `.zshrc` instead of `.mkshrc`
and `.profile`
(though I'm going to retain those symlinks to allow my old configurations to
continue working).

[`mksh`](http://www.mirbsd.org/mksh.htm) is a nice simple shell,
but using `zsh` here allows for more consistency
between my home and `$WORK` environments, and will allow a lot more powerful
extensions.

## Updating my Prompt
ZSH prompts use a totally different configuration via variable expansion.
However, it also uses the `PROMPT` variable, so I set that to the needed
values for `zsh`.

There's an excellent ZSH prompt generator at
[https://zsh-prompt-generator.site](https://zsh-prompt-generator.site/)
that I used to get these variables, though I'm sure they're in the `zsh`
documentation somewhere as well.

I wanted a simple prompt with user (`%n`), host (`%m`), and path (`%d`).
I also wanted a `%` at the end to distinguish this from other shells.
```
PROMPT="%n@%m%d%% "
```

### Fixing `mksh` prompts

This worked but surprisingly `mksh` also looks at `PROMPT`,
leaving my `mksh` prompt as the literal prompt string without expansion.

Fixing this requires setting up a proper `shrc` and linking it to
`.mkshrc` and `.zshrc`.

I chose to move my existing `aliases` script to this file,
as it also broke in non-login shells when moved to `profile`.

Within this new `shrc` file we can check what shell we're running via `$0`:
```
if [ "$0" = "/bin/zsh" ] || [ "$0" = "zsh" ] || [ "$0" = "-zsh" ]
```

I chose to add plain `zsh` here in case I run it manually for whatever reason.
I also added `-zsh` to support tmux as that's what it presents as `$0`.
This also means you'll need to be careful to quote `$0` or you'll get fun shell
errors.

There's probably a better way to do this, but I couldn't find something that
was compatible with POSIX shell, which is what most of this has to be written
in to be compatible with `mksh` and `zsh`[^korn].

[^korn]: Technically it has be compatible with Korn shell, but a quick google seems to suggest that that's actually a subset of POSIX shell.

We can then setup different prompts for each:
```
if [ "$0" = "/bin/zsh" ] || [ "$0" = "zsh" ] || [ "$0" = "-zsh" ]
then
	PROMPT="%n@%m%d%% "
else
	# Borrowed from
	# http://www.unixmantra.com/2013/05/setting-custom-prompt-in-ksh.html
	PS1='$(id -un)@$(hostname -s)$PWD$ '
fi
```

## Setting Console Font in a Better Way

I've been setting console font via `setfont` in my `.profile` for a while.
I'm not sure where I picked this up, but it's not the right way.
I even tried to only run this in a console with `-t` but that only
checks that output is a terminal, not specifically a console.
```
if [ -t 1 ]
then
	setfont /usr/share/consolefonts/Lat15-Terminus20x10.psf.gz
fi
```

This also only runs once the console is logged into,
instead of initializing it on boot.
The correct way to set this up, on Debian-based systems,
is reconfiguring `console-setup` like so:
```
dpkg-reconfigure console-setup
```

From there you get a menu of encoding, character set, font, and then font size
to configure for your consoles.

## VIM mode

To enable VIM mode for ZSH, you simply need to set:
```
bindkeys -v
```

This allows you to edit your shell commands with basic VIM keybinds.

## Getting back Ctrl + Left Arrow and Ctrl + Right Arrow

Moving around one word at a time with Ctrl and the arrow keys is broken by
vim mode unfortunately, so we'll need to re-enable it:
```
bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word
```

## Better History Search

But of course we're now using `zsh` so we can do better than just the same
configuration as we had before.

There's an excellent substring history search plugin that we can just
source without a plugin manager[^plugin]
```
source $HOME/config/zsh-history-substring-search.zsh
# Keys are weird, should be ^[[ but it's not
bindkey '^[[A' history-substring-search-up
bindkey '^[OA' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey '^[OB' history-substring-search-down
```

For some reason my system uses `^[OA` and `^[OB` as up and down keys.
It seems `^[[A` and `^[[B` are the defaults, so I've left them in,
but I'm confused as to what differences would lead to this.
If you know, please [let me know](mailto:fixmyshell@tookmund.com)
and I'll add a footnote to this article explaining it.

Back to history search.
For this to work, we also need to setup history logging:
```
export SAVEHIST=1000000
export HISTFILE=$HOME/.zsh_history
export HISTFILESIZE=1000000
export HISTSIZE=1000000
```

[^plugin]: I use oh-my-zsh at `$WORK` but for now I'm going to simplify my personal configuration. If I end up using a lot of plugins I'll reconsider this.

## Why did it show up twice for tmux?

Because `tmux` creates a login shell.
Adding:
```
echo PROFILE
```
to `profile` and:
```
echo SHRC
```
to `shrc` confirms this with:
```
PROFILE
SHRC
SHRC
```

For now, `profile` sources `shrc` so that running twice is expected.

But after this exploration and diagram,
it's clear we don't need that for `zsh`.
Removing this will break remote bash shells (see above diagram),
but I can live without those on my development laptop.

Removing that line results in the expected output for a new terminal:
```
SHRC
```
And the full output for a new tmux session or console:
```
PROFILE
SHRC
```

So finally we're back to a normal state!

This post is a bit unfocused but I hope it helps someone else repair or enhance
their shell environment.

If you liked this[^typo], or know of any other ways to manage this I could use,
let me know at [fixmyshell@tookmund.com](mailto:fixmyshell@tookmund.com).

[^typo]: Or if you've found any typos or other issues that I should fix.
