#!/usr/bin/env bash
# Configures unattended-upgrades to run a full weekly apt upgrade
# (all origins, not just security) with cleanup and an auto-reboot
# at a fixed off-hours time. Idempotent - safe to re-run.
#
# Usage:
#   sudo ./weekly-apt-updates-setup.sh
#
# Optional overrides (env vars):
#   UPGRADE_DAY=Sun        # systemd OnCalendar day-of-week
#   UPGRADE_TIME=02:30:00  # when the weekly upgrade run starts
#   REBOOT_TIME=03:30      # when to reboot afterward, if required
#
# Example for a different schedule:
#   sudo UPGRADE_DAY=Sat UPGRADE_TIME=01:00:00 REBOOT_TIME=02:00 ./weekly-apt-updates-setup.sh

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

UPGRADE_DAY="${UPGRADE_DAY:-Sun}"
UPGRADE_TIME="${UPGRADE_TIME:-02:30:00}"
REBOOT_TIME="${REBOOT_TIME:-03:30}"
CONF=/etc/apt/apt.conf.d/50unattended-upgrades

echo "==> Installing unattended-upgrades (no-op if already installed)"
apt-get update -qq
apt-get install -y unattended-upgrades update-notifier-common

echo "==> Writing /etc/apt/apt.conf.d/20auto-upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "==> Patching $CONF"
[[ -f "${CONF}.orig" ]] || cp "$CONF" "${CONF}.orig"

# Enable the regular "-updates" pocket (not just security) inside Allowed-Origins.
if grep -qE '^\s*"\$\{distro_id\}:\$\{distro_codename\}-updates";' "$CONF"; then
  :
elif grep -qE '^//\s*"\$\{distro_id\}:\$\{distro_codename\}-updates";' "$CONF"; then
  sed -i -E 's#^//(\s*"\$\{distro_id\}:\$\{distro_codename\}-updates";)#\1#' "$CONF"
else
  sed -i '/^Unattended-Upgrade::Allowed-Origins {/a\	"${distro_id}:${distro_codename}-updates";' "$CONF"
fi

set_uu_option() {
  local key="$1" value="$2"
  if grep -qE "^[[:space:]]*Unattended-Upgrade::${key}[[:space:]]" "$CONF"; then
    sed -i -E "s#^[[:space:]]*Unattended-Upgrade::${key}[[:space:]]+\"[^\"]*\";#Unattended-Upgrade::${key} \"${value}\";#" "$CONF"
  elif grep -qE "^//[[:space:]]*Unattended-Upgrade::${key}[[:space:]]" "$CONF"; then
    sed -i -E "s#^//[[:space:]]*Unattended-Upgrade::${key}[[:space:]]+\"[^\"]*\";#Unattended-Upgrade::${key} \"${value}\";#" "$CONF"
  else
    printf '\nUnattended-Upgrade::%s "%s";\n' "$key" "$value" >> "$CONF"
  fi
}

set_uu_option "Remove-Unused-Dependencies" "true"
set_uu_option "Remove-Unused-Kernel-Packages" "true"
set_uu_option "Automatic-Reboot" "true"
set_uu_option "Automatic-Reboot-WithUsers" "true"
set_uu_option "Automatic-Reboot-Time" "$REBOOT_TIME"

echo "==> Overriding apt-daily-upgrade.timer to run weekly (${UPGRADE_DAY} ${UPGRADE_TIME})"
mkdir -p /etc/systemd/system/apt-daily-upgrade.timer.d
cat > /etc/systemd/system/apt-daily-upgrade.timer.d/override.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=${UPGRADE_DAY} *-*-* ${UPGRADE_TIME}
RandomizedDelaySec=0
Persistent=false
EOF

systemctl daemon-reload
systemctl restart apt-daily-upgrade.timer

echo "==> Installing login banner (last run + last boot time) at /etc/update-motd.d/96-weekly-apt-status"
cat > /etc/update-motd.d/96-weekly-apt-status <<'EOF'
#!/bin/sh
# Shows the outcome of the last weekly apt-daily-upgrade.service run and the
# last boot time, so an admin logging in can tell whether the scheduled
# update/reboot actually happened.
SVC=apt-daily-upgrade.service
LAST=$(systemctl show "$SVC" -p ActiveExitTimestamp --value 2>/dev/null)
CODE=$(systemctl show "$SVC" -p ExecMainStatus --value 2>/dev/null)
BOOT=$(uptime -s 2>/dev/null)

if [ -n "$LAST" ] && [ "$LAST" != "n/a" ]; then
    if [ "$CODE" = "0" ]; then
        RESULT="OK"
    else
        RESULT="FAILED (exit $CODE) - check: sudo journalctl -u $SVC"
    fi
    echo "Weekly apt update: last run $LAST -- $RESULT"
fi

if [ -n "$BOOT" ]; then
    echo "System last booted: $BOOT"
fi
EOF
chmod 755 /etc/update-motd.d/96-weekly-apt-status
chown root:root /etc/update-motd.d/96-weekly-apt-status

echo "==> Done. Next scheduled run:"
systemctl list-timers apt-daily-upgrade.timer --all --no-pager

echo
echo "==> Sanity check (dry run, changes nothing):"
unattended-upgrade --dry-run --debug 2>&1 | tail -40

echo
echo "Setup complete. Logs will appear in /var/log/unattended-upgrades/ after the first real run."
