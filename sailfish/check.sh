#!/bin/sh
# Root helper: is OneBack running as an accessibility service for <user>?
#   on       enabled in the accessibility settings (and not crashed)
#   crashed  enabled, but its process died while bound (uninstall/reinstall, or Sailfish
#            stopping it because background running isn't allowed), and Android won't
#            start it again until it's switched off and on
# From "dumpsys accessibility": "Enabled services" and "Crashed services" list components;
# "Bound services" lists labels only, so it isn't used.
#   off      not enabled
#   unknown  AppSupport not running
# Prints the state and writes it to /run/oneback/a11y-<user> for the settings page
# (which can't read Android's settings without root).
set -u
u=${1:?usage: check.sh <user>}
id -u "$u" >/dev/null 2>&1 || { echo "no such user: $u" >&2; exit 2; }
SVC=dev.local.oneback/dev.local.oneback.BackService

if d=$(lxc-attach -P /tmp/appsupport -n "$u" -- /system/bin/dumpsys accessibility 2>/dev/null) \
        && [ -n "$d" ]; then
    line() { printf '%s\n' "$d" | grep -m1 "$1" || true; }
    case "$(line 'Enabled services:')" in
        *"$SVC"*)
            case "$(line 'Crashed services:')" in
                *"$SVC"*) state=crashed ;;
                *)        state=on ;;
            esac ;;
        *)  state=off ;;
    esac
else
    state=unknown
fi

mkdir -p /run/oneback
printf '%s\n' "$state" > "/run/oneback/a11y-$u.tmp"
mv "/run/oneback/a11y-$u.tmp" "/run/oneback/a11y-$u"
echo "$state"
