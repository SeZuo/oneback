# OneBack

A one-tap floating Back button for Android apps on **Sailfish OS (Android AppSupport)**. Together with one config line, it replaces the big bar at the bottom of every Android app that holds only a back button.

| | |
|---|---|
| Tap | Back |
| Drag | Move the button (position is remembered) |
| Long press | Hide it for 10 seconds |
| Landscape | Hidden automatically |

Tested on the Jolla Phone (2026), Sailfish OS 5.2.0.22, AppSupport (Android 15).

## Privacy / permissions

OneBack is an Android **accessibility service**, which is how it can send a system-wide Back to other apps.

- It **can't read screen content** (`canRetrieveWindowContent="false"`) and has no internet permission.
- It asks for no other permissions. The button is an accessibility overlay, so "display over other apps" isn't needed.
- The whole app is about 150 lines of Java: [`BackService.java`](src/dev/local/oneback/BackService.java).

## Install

1. Download `oneback.apk` from the releases and open it on the phone (e.g. from `~/Downloads` in the file manager).
2. Open **OneBack** from the app grid. It only opens Android's accessibility settings. Switch on **"OneBack floating back button"** there.
3. Check that the button works.

## Hide the Android navigation bar

Do this only after OneBack works, because otherwise Android apps have no system Back at all.

As root (`devel-su`), create `/etc/appsupport.conf.d/90-hide-navbar.conf`:

```
[Config]
CustomProperties=qemu.hw.mainkeys=1
```

Then go to Settings → Android AppSupport → **Stop**, then **Start**.

`qemu.hw.mainkeys=1` is an old Android override that means "this device has hardware keys", so Android draws no navigation bar. AppSupport passes it to Android as a system property. Nothing in the Android image is modified.

Check that it's active:

```
grep mainkeys /tmp/appsupport/defaultuser/generated_props
```

## Undo

- **Bar:** delete `/etc/appsupport.conf.d/90-hide-navbar.conf` (as root) and Stop/Start AppSupport.
- **OneBack:** switch it off in the accessibility settings (open OneBack from the app grid), or uninstall it in Settings → Apps.

While the bar is hidden, don't switch OneBack off, or you'll only have the apps' own back arrows.

## Build

You need the Android SDK (build-tools 36.0.0, platform android-36) and a JDK. Gradle isn't needed.

```
./build.sh          # -> build/oneback.apk
```

The script runs `aapt2 → javac → d8 → zipalign → apksigner`. The SDK path defaults to `~/Android/Sdk`; override it with `ANDROID_HOME`. On the first run it creates a signing key, `oneback.keystore`. Keep it private and don't lose it: updates must be signed with the same key, or Android won't install them over an existing install.

## License

MIT, see [LICENSE](LICENSE).
