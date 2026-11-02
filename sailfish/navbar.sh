#!/bin/sh
# Root helper: hide or show the Android navigation bar by writing or deleting one
# AppSupport config file. Started only through oneback-navbar-hide@<user>.service and
# oneback-navbar-show.service, which the polkit rule lets the logged-in user start.
#   navbar hide <user>   refuses unless OneBack is on in <user>'s accessibility settings
#                        and allowed to run in the background, so Android apps keep a Back
#   navbar show
# Takes effect after Android AppSupport is restarted.
set -eu
CONF=/etc/appsupport.conf.d/90-oneback-navbar.conf
# The file OneBack's README tells people to create by hand. "show" removes it too, but only
# if it holds nothing but the navbar setting, so no other setting is ever lost.
HAND=/etc/appsupport.conf.d/90-hide-navbar.conf

only_navbar() {
    [ -f "$1" ] || return 1
    rest=$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$1" \
        | grep -v -x -e '\[Config\]' -e 'CustomProperties=qemu.hw.mainkeys=1' || true)
    [ -z "$rest" ]
}

case "${1:-}" in
    hide)
        u=${2:?usage: $0 hide <user>}
        if [ "$(/usr/libexec/oneback/check "$u")" != on ]; then
            echo "OneBack isn't on in the accessibility settings of $u: not hiding the bar" >&2
            exit 1
        fi
        # Without background running Sailfish stops OneBack whenever it leaves the foreground.
        uid=$(id -u "$u")
        bg=$(DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/dbus/user_bus_socket \
            gdbus call --session --dest com.jolla.apkd --object-path /com/jolla/apkd \
            --method com.jolla.apkd.getAppStartOnBootup dev.local.oneback 2>/dev/null || true)
        if [ "$bg" != "(true,)" ]; then
            echo "OneBack isn't allowed to run in the background for $u: not hiding the bar" >&2
            exit 1
        fi
        mkdir -p /etc/appsupport.conf.d
        printf '%s\n' \
            '# Written by OneBack (Settings > Android AppSupport > OneBack).' \
            '# qemu.hw.mainkeys=1 tells Android the device has hardware keys, so it draws no' \
            '# navigation bar. Removed again when the switch is turned off or OneBack is uninstalled.' \
            '[Config]' \
            'CustomProperties=qemu.hw.mainkeys=1' > "$CONF.tmp"
        mv "$CONF.tmp" "$CONF"
        ;;
    show)
        rm -f "$CONF"
        if only_navbar "$HAND"; then
            rm -f "$HAND"
        fi
        ;;
    *)
        echo "usage: $0 hide <user> | show" >&2
        exit 2
        ;;
esac
