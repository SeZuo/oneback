#!/bin/sh
# Root helper: install the OneBack APK bundled in this package into a user's AppSupport.
#   install.sh <user>     install now (retries while Android is still starting)
#   install.sh --all-users  from the RPM scriptlet: mark every AppSupport user as pending
#                           and install right away where AppSupport is running. Pending
#                           installs run when AppSupport starts (appsupport@.service drop-in).
set -u
APK=/usr/share/oneback/oneback.apk
VERSION=$(cat /usr/share/oneback/version)
STATE=/var/lib/oneback
SVC=dev.local.oneback/dev.local.oneback.BackService

# After (re)installing, Android may keep OneBack enabled but marked as crashed (its process
# died while bound) and won't start it again. Switching it off and on clears that; do the same
# here, but only if the user had it on. Never switches OneBack on by itself.
repair_a11y() {
    A="lxc-attach -P /tmp/appsupport -n $1 --"
    v=$($A /system/bin/settings get secure enabled_accessibility_services 2>/dev/null) || return 0
    case ":$v:" in *":$SVC:"*) ;; *) return 0 ;; esac
    [ "$(/usr/libexec/oneback/check "$1")" = crashed ] || return 0
    without=$(printf '%s' ":$v:" | sed "s|:$SVC:|:|; s|^:*||; s|:*\$||")
    if [ -n "$without" ]; then
        $A /system/bin/settings put secure enabled_accessibility_services "$without"
    else
        $A /system/bin/settings delete secure enabled_accessibility_services
    fi
    sleep 2
    $A /system/bin/settings put secure enabled_accessibility_services "$v"
    sleep 2
    /usr/libexec/oneback/check "$1" >/dev/null
}

if [ "${1:-}" = "--all-users" ]; then
    mkdir -p "$STATE"
    rm -f "$STATE"/pending-*      # drop stale ones (e.g. non-user accounts from older versions)
    for home in /home/*; do
        u=${home##*/}
        uid=$(id -u "$u" 2>/dev/null) || continue
        # Sailfish user accounts only (AppSupport's own accounts are 500000+)
        [ "$uid" -ge 100000 ] && [ "$uid" -lt 200000 ] || continue
        touch "$STATE/pending-$u"
        if systemctl -q is-active "appsupport@$u.service"; then
            # restart, not start: an install still running from the previous package
            # version would otherwise keep going with the old script and APK.
            systemctl --no-block restart "oneback-install@$u.service"
        fi
    done
    exit 0
fi

u=${1:?usage: install.sh <user>|--all-users}
uid=$(id -u "$u" 2>/dev/null) || { echo "no such user: $u" >&2; exit 2; }

# appsupport-pm talks to AppSupport over the user's session bus, which a systemd unit
# doesn't have. Use that user's bus (it exists while they are logged in).
export XDG_RUNTIME_DIR=/run/user/$uid
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/dbus/user_bus_socket

# Already this version: don't reinstall (that would restart OneBack for no reason), but
# still repair a crashed service, e.g. after the user uninstalled and reinstalled it.
if appsupport-pm -i "$u" listFull 2>/dev/null | grep -q "^dev\.local\.oneback;.*;$VERSION;"; then
    rm -f "$STATE/pending-$u"
    repair_a11y "$u"
    exit 0
fi

# Fresh install (not an update): allow OneBack to run in the background (Settings > Apps >
# OneBack). Sailfish force-stops Android apps without it as soon as they leave the
# foreground ("sfos_background_denied"), which kills the accessibility service. Updates
# keep whatever the user chose.
fresh=yes
appsupport-pm -i "$u" listFull 2>/dev/null | grep -q '^dev\.local\.oneback;' && fresh=no

i=0
while [ $i -lt 12 ]; do
    if appsupport-pm -i "$u" install "$APK"; then
        rm -f "$STATE/pending-$u"
        if [ $fresh = yes ]; then
            gdbus call --session --dest com.jolla.apkd --object-path /com/jolla/apkd \
                --method com.jolla.apkd.setAppStartOnBootup dev.local.oneback true >/dev/null 2>&1 || :
        fi
        sleep 3     # let Android settle before looking at the accessibility state
        repair_a11y "$u"
        exit 0
    fi
    i=$((i + 1))
    sleep 10
done
echo "OneBack install for $u failed; it stays pending until AppSupport starts again" >&2
exit 1
