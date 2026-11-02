# OneBack for Sailfish OS (RPM)

One package for Storeman/OpenRepos that brings everything:

- **OneBack APK**, installed into Android AppSupport automatically: right away if AppSupport is running, otherwise the next time it starts. Updating the package updates OneBack.
- **A OneBack section in Settings → Android AppSupport**: shows whether OneBack is installed and on, can install/update and open it, and has an **Android navigation bar** switch (on = shown, the default). Turning it off is only possible while OneBack is on, so Android apps always have a Back. A button restarts AppSupport to apply the change.

## How it works

| File | Purpose |
|---|---|
| `/usr/share/oneback/oneback.apk` | The bundled APK |
| `/usr/share/jolla-settings/pages/android-runtime/plugins/oneback.qml` | The settings section. The AppSupport page loads every `.qml` in `plugins/` (Jolla's Bluetooth and mobile-data packages use the same folder) |
| `/usr/libexec/oneback/navbar` + `oneback-navbar-hide@.service`, `oneback-navbar-show.service` | Root helper: writes or deletes `/etc/appsupport.conf.d/90-oneback-navbar.conf` (`CustomProperties=qemu.hw.mainkeys=1`). Hiding refuses unless OneBack is on (it runs the check itself) |
| `/usr/libexec/oneback/check` + `oneback-check@.service` | Root helper: reads `enabled_accessibility_services` from the user's AppSupport container and writes `on`/`off`/`unknown` to `/run/oneback/a11y-<user>` for the page |
| `/usr/libexec/oneback/install` + `oneback-install@.service` | Root helper: `appsupport-pm -i <user> install` of the bundled APK |
| `/usr/libexec/oneback/uninstall` + `oneback-uninstall@.service` | Root helper for the **Uninstall OneBack** button: shows the bar, restarts AppSupport, uninstalls the app, removes the package, in that order so Android apps never lose their Back |
| `appsupport@.service.d/90-oneback.conf` | When AppSupport starts with an install pending (`/var/lib/oneback/pending-<user>`), runs the install |
| `/usr/share/polkit-1/rules.d/49-oneback.rules` | Lets the user at the device **start** exactly these units (install only for their own user). Nothing else |

The helpers take no input from the caller, so the polkit rule can't be used for anything but these three actions. AppSupport is restarted through `com.jolla.apkd.control.controlService`, the same D-Bus call as the Stop/Start button on that page.

Whether OneBack is on is read from Android's own setting, not from anything OneBack writes: a file left behind by the app would be stale whenever Android kills it (AppSupport restart, update).

## Uninstall

The package has no icon in the app grid, so it's uninstalled from its own section: **Uninstall OneBack** at the bottom of Settings → Android AppSupport → OneBack. It shows the bar again, restarts AppSupport, uninstalls the OneBack app and removes the package, in that order.

Removing the package any other way (Storeman, `devel-su pkcon remove oneback`) deletes the config file too, so the bar comes back after the next AppSupport restart, but leaves the OneBack app installed (remove it in Settings → Apps once the bar is back).

## Build

```
pacman -S rpm-tools     # once (Arch)
./build-rpm.sh          # -> sailfish/build/oneback-<version>-1.noarch.rpm
```

It builds the APK first and uses its version, so APK and package always match. The spec is `rpm/oneback.spec` (Sailfish convention) and follows [Sailfish's packaging conventions](https://docs.sailfishos.org/Reference/Software_Packaging/) (Fedora guidelines with a few changes).

The official way to build Sailfish packages is the Sailfish SDK (`sfdk build` in this folder), which builds against the real target. `build-rpm.sh` uses plain `rpmbuild` instead, which works here because the package is `noarch` (QML, shell, systemd units, APK), but has to make up for the differences to the target:

- rpm v4 format with a gzip payload, because Sailfish has rpm 4.16 (rpm 6 defaults to v6 + zstd)
- directory macros set to Sailfish's values (`rpm --eval` on the phone), because the build host's can differ (Arch: `%_sharedstatedir` is `/usr/com`)

Chum isn't an option as it stands: it builds everything from source on OBS, which has no Android SDK for the APK.
