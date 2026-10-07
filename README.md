# Weekly apt updates (unattended-upgrades)

Configures the standard Ubuntu `unattended-upgrades` package to run a **weekly**,
**full-package** upgrade (not just security) with dependency/kernel cleanup and
an **automatic reboot at a fixed off-hours time** when one is required.

No cron job, no passwordless sudo. The recurring job runs entirely as root via
its own systemd timer — once set up, it needs no user, no password, and no
Claude Code involvement to keep running.

## Install on a new server

1. Copy `weekly-apt-updates-setup.sh` to the target server.
2. `chmod +x weekly-apt-updates-setup.sh`
3. Run it **in a real interactive terminal** (an SSH session or the console)
   as root:

   ```
   sudo ./weekly-apt-updates-setup.sh
   ```

   This has to be an actual terminal with a tty attached — `sudo` needs to
   prompt for your password, and that prompt doesn't work over a
   non-interactive shell (a raw SSH `-c` command, an editor's "run" button, an
   AI assistant's tool call without a pty, etc.). If you see
   `sudo: a password is required` or `sudo: a terminal is required to
   authenticate`, that's why — just run it from a normal terminal instead.

4. The script is idempotent — safe to re-run any time (e.g. after changing
   the schedule below).

### Custom schedule

Override the day/time via environment variables:

```
sudo UPGRADE_DAY=Sat UPGRADE_TIME=01:00:00 REBOOT_TIME=02:00 ./weekly-apt-updates-setup.sh
```

- `UPGRADE_DAY` — systemd `OnCalendar` day-of-week (default `Sun`)
- `UPGRADE_TIME` — when the weekly upgrade run starts, `HH:MM:SS` (default `02:30:00`)
- `REBOOT_TIME` — when to reboot afterward if one is required, `HH:MM` (default `03:30`)

## What it changes

| File | Purpose |
|---|---|
| `/etc/apt/apt.conf.d/20auto-upgrades` | Turns on the periodic hooks (`APT::Periodic::Update-Package-Lists`, `APT::Periodic::Unattended-Upgrade`). Without this file, the timers fire but never actually call `unattended-upgrade`. |
| `/etc/apt/apt.conf.d/50unattended-upgrades` | Enables the `-updates` origin (regular packages, not just security), and sets `Remove-Unused-Dependencies`, `Remove-Unused-Kernel-Packages`, `Automatic-Reboot`, `Automatic-Reboot-WithUsers`, and `Automatic-Reboot-Time`. A one-time backup of the original file is saved as `50unattended-upgrades.orig` alongside it. |
| `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` | Replaces the stock **daily** schedule of `apt-daily-upgrade.timer` with a single **weekly** slot. `apt-daily.timer` (package list refresh, twice a day) is left untouched — harmless, and `unattended-upgrade` refreshes lists itself anyway. |
| `/etc/update-motd.d/96-weekly-apt-status` | New login banner: states the upgrade schedule in plain words (e.g. "every Sunday at 02:30 CDT", plus the reboot time), and shows the timestamp/result of the last `apt-daily-upgrade.service` run and the system's last boot time, so an SSH login tells you whether last Sunday's update (and reboot, if one happened) actually went through. |

## How you'll know it ran

Three banners show up automatically when you SSH in — no email, no polling required:

1. **`92-unattended-upgrades`** (ships with the package) — shows a note if there are updates unattended-upgrades is managing. Silent when there's nothing to report.
2. **`98-reboot-required`** (ships with `update-notifier-common`) — prints `*** System restart required ***` if a reboot is currently pending. Since `/var/run/reboot-required` lives on tmpfs, this clears itself the moment the reboot happens — so if you log in and *don't* see it after Sunday night, the reboot already completed.
3. **`96-weekly-apt-status`** (added by this setup) — the persistent one: always shows the last run's timestamp and success/failure, plus the system's last boot time, e.g.:
   ```
   System upgrades run automatically every Sunday at 02:30 CDT;
   if an upgrade requires a reboot, the system reboots at 03:30 CDT.
   Weekly apt update: last run Sun 2026-09-27 02:30:41 CDT -- OK
   System last booted: 2026-09-27 03:31:02
   ```
   If the boot time lines up with just after the update timestamp, the scheduled reboot happened. If `ExecMainStatus` isn't `0`, it'll say `FAILED` and point you at `sudo journalctl -u apt-daily-upgrade.service`.

## Checking status

**No sudo needed:**

```
systemctl list-timers apt-daily-upgrade.timer     # next/last scheduled run
systemctl status apt-daily-upgrade.timer           # timer active state
systemctl status apt-daily-upgrade.service          # result of the LAST run — look for SUCCESS vs a failed exit code
```

`apt-daily-upgrade.service` is the most useful "did it actually work" check —
it shows the exit status of the most recent upgrade attempt.

**Needs sudo** (the log directory is root-only, mode `0700`):

```
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log        # what was checked/decided
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log   # actual dpkg output if packages were upgraded
```

**Reboot pending check** (no sudo):

```
ls /var/run/reboot-required   # exists only if a reboot is needed; absent = nothing pending
```

**Dry run** (makes no changes, confirms config without waiting for the schedule):

```
sudo unattended-upgrade --dry-run --debug
```

## Design notes

- **All packages, not just security** — the `-updates` origin was deliberately
  enabled so this behaves like a full `apt upgrade`, not the more conservative
  security-only default. `-proposed` and `-backports` are left disabled as too
  unstable/optional for something unattended.
- **`Automatic-Reboot-WithUsers "true"`** — without it, a pending reboot is
  silently skipped if anyone happens to be logged in (e.g. over SSH) when the
  job runs. Since these are headless servers normally administered over SSH,
  skipping would mean reboots effectively never happen. This trades a small
  chance of an SSH session getting cut off (at the scheduled off-hours time)
  for actually getting the reboot done.
- **Why no passwordless sudo** — the recurring job is entirely root's own
  systemd timer, so it was never needed for that. It's only relevant for
  re-running the *setup* script itself, which is intentionally left as a
  manual, interactive, one-time step per server.
