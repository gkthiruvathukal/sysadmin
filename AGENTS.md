# AGENTS.md — sysadmin working directory

Context for resuming work in this directory (`/home/gkt/Work/sysadmin`, not a
git repo) across sessions.

## Current project: weekly apt updates via unattended-upgrades

**Status: done and live on this server.** Fully configured, verified, and
already running on its own — nothing further is required unless the user
asks for a change.

- `weekly-apt-updates-setup.sh` — the idempotent setup script. Configures
  Ubuntu's stock `unattended-upgrades` to run a full weekly upgrade (not just
  security) with cleanup and a fixed-time auto-reboot, plus a login MOTD
  status banner. Safe to re-run any time, including on other servers.
- `README.md` — full documentation: install steps for other servers, what
  each changed file does, all status-check commands (with/without sudo), and
  the design rationale (why `-updates` origin, why
  `Automatic-Reboot-WithUsers`, why no passwordless sudo).

### Verified state on this server (as of 2026-09-27 ~00:11 CDT)
- `/etc/apt/apt.conf.d/20auto-upgrades` — exists, periodic hooks enabled.
- `/etc/apt/apt.conf.d/50unattended-upgrades` — patched (`-updates` origin,
  cleanup + auto-reboot options); original backed up as `.orig` alongside it.
- `/etc/systemd/system/apt-daily-upgrade.timer.d/override.conf` — weekly
  schedule active. Next run: **Sun 2026-09-27 02:30 CDT** (had not yet
  happened as of the last check in this session).
- `/etc/update-motd.d/96-weekly-apt-status` — installed. Shows last run
  timestamp/result + last boot time on every SSH login.

### To resume / check on this
Just ask, e.g. "did the weekly update run last night?" — a fresh session can
answer by running (all read-only, no sudo needed):
```
systemctl status apt-daily-upgrade.service --no-pager   # last run result
systemctl list-timers apt-daily-upgrade.timer            # next scheduled run
ls /var/run/reboot-required                                # exists = reboot still pending
```
For deeper detail (needs sudo, must be run by the user in a real terminal —
see gotcha below):
```
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
sudo tail -n 50 /var/log/unattended-upgrades/unattended-upgrades-dpkg.log
```

### To roll out on another server
```
scp weekly-apt-updates-setup.sh <host>:~/
ssh <host>
sudo ./weekly-apt-updates-setup.sh
```
Must be run from a real interactive terminal — see gotcha below. Optional
env vars `UPGRADE_DAY`, `UPGRADE_TIME`, `REBOOT_TIME` override the schedule
(see README for details/example).

## Gotcha learned this session: sudo needs a real tty

Neither Claude Code's Bash tool nor its `!`-prefixed bang-commands attach a
terminal, so `sudo` can never prompt for a password through either path —
it fails with `sudo: a password is required` or `sudo: a terminal is
required to authenticate`. Any privileged step (running the setup script,
editing files under `/etc`, etc.) has to be done by the user directly in
their own SSH/console session. Read-only checks (systemctl status,
`test -f`, reading world-readable files) work fine either way and don't hit
this — only root-only files/actions do.

**Decision this implies:** don't propose passwordless sudo (NOPASSWD) as a
workaround unless the user explicitly asks for it — they were asked about
this tradeoff earlier and preferred to keep sudo interactive/manual, since
the recurring job itself runs as root via systemd and never needed sudo at
all. The one-time setup step being manual is an accepted tradeoff, not an
open problem to solve.
