#!/bin/sh
# Root helper: remove OneBack completely, in an order that never leaves Android apps
# without a Back:
#   1. show the navigation bar again (delete the config file)
#   2. restart AppSupport so the bar is actually back (same D-Bus call as the
#      Stop/Start button in Settings), wait until it runs again
#   3. uninstall the OneBack app
#   4. remove this package (the settings section goes with it)
# Started only through oneback-uninstall@<user>.service (polkit: the user at the device,
# for their own user).
set -u
u=${1:?usage: uninstall.sh <user>}
uid=$(id -u "$u" 2>/dev/null) || { echo "no such user: $u" >&2; exit 2; }
export XDG_RUNTIME_DIR=/run/user/$uid
export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/dbus/user_bus_socket
UNIT=appsupport@$u.service

control() { # start|stop AppSupport for $u, like the Settings button
    [ "$1" = start ] && on=true || on=false
    gdbus call --system --dest com.jolla.apkd.control --object-path /com/jolla/apkd \
        --method com.jolla.apkd.control.controlService "$on" "$u" >/dev/null
}
wait_for() { # wait until AppSupport is in state $1 (or failed), up to 3 minutes
    i=0
    while [ $i -lt 90 ]; do
        st=$(systemctl is-active "$UNIT")
        [ "$st" = "$1" ] && return 0
        [ "$st" = failed ] && return 1
        sleep 2
        i=$((i + 1))
    done
    return 1
}

echo "OneBack uninstall for $u: showing the navigation bar"
/usr/libexec/oneback/navbar show

echo "restarting AppSupport"
if [ "$(systemctl is-active "$UNIT")" = active ]; then
    control stop
    wait_for inactive || echo "AppSupport didn't stop cleanly, starting it anyway" >&2
fi
control start
if wait_for active; then
    i=0
    while [ $i -lt 24 ]; do   # Android may still be booting
        if ! appsupport-pm -i "$u" listFull 2>/dev/null | grep -q '^dev\.local\.oneback;'; then
            echo "OneBack app not installed (anymore)"
            break
        fi
        appsupport-pm -i "$u" uninstall dev.local.oneback && echo "OneBack app uninstalled" && break
        i=$((i + 1))
        sleep 5
    done
else
    echo "AppSupport didn't start: OneBack app left installed (remove it in Settings > Apps)" >&2
fi

echo "removing the package"
pkcon --noninteractive remove oneback || rpm -e oneback
