---
layout: post
title: "Regular Reboots"
description: "Let your systems manage themselves"
tags: [sysadmin,systemd,cron,reboot,state]
---

Uptime is often considered a measure of system reliability,
an indication that the running software is stable and can be counted on.

However, this hides the insidious build-up of state throughout the system as
it runs, the slow drift from the expected to the strange.

As Nolan Lawson highlights in an excellent post entitled
[Programmers are bad at managing state](https://nolanlawson.com/2020/12/29/programmers-are-bad-at-managing-state/),
state is the most challenging part of programming.
It's why "did you try turning it off and on again" is a classic tech support
response to any problem.

<blockquote class="twitter-tweet"><p lang="en" dir="ltr">You: uptime<br><br>Me: Every machine gets rebooted at 1AM to clear the slate for maintenance, and at 3:30AM to push through any pending updates.</p>&mdash; <a href="https://twitter.com/SwiftOnSecurity/status/1343079557910433797">@SwiftOnSecurity, December 27, 2020</a></blockquote>

In addition to the problem of state, installing regular updates periodically
requires a reboot, even if the rest of the process is automated through a
tool like [unattended-upgrades](https://wiki.debian.org/UnattendedUpgrades).

For my personal homelab, I manage a handful of different machines running
various services.

I used to just schedule a day to update and reboot all of them, but that
got very tedious very quickly.

I then moved the reboot to a cronjob,
and then recently to a systemd timer and service.

I figure that laying out my path to better management of this might help
others, and will almost certainly lead to someone telling me a better way
to do this.

<blockquote class="twitter-tweet"><p lang="en" dir="ltr">Ultimately, uptime only measures the duration since you last proved you can turn the machine on and have it boot.</p>&mdash; <a href="https://twitter.com/SwiftOnSecurity/status/728812283535626242">@SwiftOnSecurity, May 7, 2016</a></blockquote>

## Stage One: Reboot Cron

The first, and easiest approach, is a simple cron job.
Just adding the following line to `/var/spool/cron/crontabs/root`[^cronoptions]
is enough to get your machine to reboot once a month[^monthly] on the 6th at 8:00 AM[^cronformat]:
```
0 8 6 * * reboot
```

I had this configured for many years and it works well.
But you have no indication as to whether it succeeds except for checking
your uptime regularly yourself.

[^monthly]: Why once a month? Mostly to avoid regular disruptions, but still be reasonably timely on updates.

[^cronoptions]: You could also add a line to `/etc/crontab` or drop a script into `/etc/cron.monthly` depending on your system.

[^cronformat]: If you're looking to understand the cron time format I recommend [crontab guru](https://crontab.guru/).

## Stage Two: Reboot systemd Timer

The next evolution of this approach for me was to use a systemd timer.
I created a `regular-reboot.timer` with the following contents:
```
[Unit]
Description=Reboot on a Regular Basis

[Timer]
Unit=regular-reboot.service
OnBootSec=1month

[Install]
WantedBy=timers.target
```

This timer will trigger the `regular-reboot.service` systemd unit
when the system reaches one month of uptime.

I've seen some guides to creating timer units recommend adding
a `Wants=regular-reboot.service` to the `[Unit]` section,
but this has the consequence of running that service every time it starts the
timer. In this case that will just reboot your system on startup which is
not what you want.

Care needs to be taken to use the `OnBootSec` directive instead of
`OnCalendar` or any of the other time specifications, as your system could
reboot, discover its still within the expected window and reboot again.
With `OnBootSec` your system will not have that problem.
Technically, this same problem could have occurred with the cronjob approach,
but in practice it never did, as the systems took long enough to come back
up that they were no longer within the expected window for the job.

I then added the `regular-reboot.service`:
```
[Unit]
Description=Reboot on a Regular Basis
Wants=regular-reboot.timer

[Service]
Type=oneshot
ExecStart=shutdown -r 02:45
```

You'll note that this service is actually scheduling a specific reboot time
via the shutdown command instead of just immediately rebooting.
This is a bit of a hack needed because I can't control when the timer
runs exactly when using `OnBootSec`.
This way different systems have different reboot times so that everything
doesn't just reboot and fail all at once. Were something to fail to come
back up I would have some time to fix it, as each machine has a few hours
between scheduled reboots.


One you have both files in place, you'll simply need to reload configuration
and then enable and start the timer unit:
```
systemctl daemon-reload
systemctl enable --now regular-reboot.timer
```

You can then check when it will fire next:
```
# systemctl status regular-reboot.timer
● regular-reboot.timer - Reboot on a Regular Basis
     Loaded: loaded (/etc/systemd/system/regular-reboot.timer; enabled; preset: enabled)
     Active: active (waiting) since Wed 2024-03-13 01:54:52 EDT; 1 week 4 days ago
    Trigger: Fri 2024-04-12 12:24:42 EDT; 2 weeks 4 days left
   Triggers: ● regular-reboot.service

Mar 13 01:54:52 dorfl systemd[1]: Started regular-reboot.timer - Reboot on a Regular Basis.
```

### Sidenote: Replacing all Cron Jobs with systemd Timers
More generally, I've now replaced all cronjobs on my personal systems with
systemd timer units, mostly because I can now actually track failures via
`prometheus-node-exporter`. There are plenty of ways to hack in cron support
to the node exporter, but just moving to systemd units provides both
support for tracking failure and logging,
both of which make system administration much easier when things inevitably
go wrong.

## Stage Three: Monitor that it's working

The final step here is confirm that these units actually work, beyond just
firing regularly.

I now have the following rule in my `prometheus-alertmanager` rules:
```
  - alert: UptimeTooHigh
    expr: (time() - node_boot_time_seconds{job="node"}) / 86400 > 35
    annotations:
      summary: "Instance {{ $labels.instance }} Has Been Up Too Long!"
      description: "Instance {{ $labels.instance }} Has Been Up Too Long!"
```

This will trigger an alert anytime that I have a machine up for more than 35
days. This actually helped me track down one machine that I had forgotten to
set up this new unit on[^configmanagement].

[^configmanagement]: In the long term I really should set up something like ansible to automatically push fleetwide changes like this but with fewer machines than fingers this seems like overkill.

## Not everything needs to scale
![Is It Worth The Time](https://imgs.xkcd.com/comics/is_it_worth_the_time.png)

One of the most common fallacies programmers fall into is that we will jump
to automating a solution before we stop and figure out how much time it would even save.

In taking a slow improvement route to solve this problem for myself,
I've managed not to invest too much time[^article] in worrying about this
but also achieved a meaningful improvement beyond my first approach of doing it
all by hand.

[^article]: Of course by now writing about it, I've probably doubled the amount of time I've spent thinking about this topic but oh well...
