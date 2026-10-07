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
  schedule active (Sun 02:30 CDT).
- `/etc/update-motd.d/96-weekly-apt-status` — installed. Shows last run
  timestamp/result + last boot time on every SSH login.

### Check on 2026-10-06
- Runs on Sun 2026-09-27 02:32 and Sun 2026-10-04 02:30 both succeeded
  (exit 0, per `/var/log/apt/history.log*`). No reboot pending; the Oct 4 run
  did not need one (system was already rebooted manually 2026-10-02 21:06
  after a manual `apt upgrade`).
- **Bug found & fixed in the script (not yet applied on this server):** the
  MOTD banner read `ActiveExitTimestamp`, which is never set for this
  `Type=oneshot` service, so the "last run" line never printed. Changed to
  `ExecMainExitTimestamp`. To apply: user re-runs
  `sudo ./weekly-apt-updates-setup.sh` in a real terminal.
- `last reboot` (wtmp) is stale on this host — use `uptime -s` for boot time.

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

## In progress (2026-10-06): publish this repo to GitHub

Goal: public repo `gkthiruvathukal/sysadmin` so other servers can
`git clone` / `git pull` it over SSH.

- Repo contents checked for secrets (full history): none. User approved public.
- Remote already added: `origin` → `git@github.com:gkthiruvathukal/sysadmin.git`
  (user wants SSH URLs, not HTTPS — keys for github.com are on their servers).
- SSH to GitHub works from this server (`ssh -T git@github.com` → authenticated
  as gkthiruvathukal).
- **Blocked:** repo doesn't exist on GitHub yet, and `gh` can't create it —
  `GH_TOKEN` in the user's shell env is invalid and overrides the saved login,
  and `~/.config/gh/hosts.yml` (last written 2025-07-19) is also invalid. User
  is removing `GH_TOKEN` and re-running `gh auth login` in their own terminal.

Next steps once `gh auth status` is OK (run `gh` with `env -u GH_TOKEN` if
Claude Code was started while the old token was still exported):
```
gh repo create gkthiruvathukal/sysadmin --public
git push -u origin main
git status -sb; git ls-remote origin   # confirm tracking + remote matches local
```
(Don't use `--source . --push` with `gh repo create` — it would try to add a
remote that already exists.)
