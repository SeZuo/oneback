# OneBack

A one-tap floating Back button for Android apps on **Sailfish OS (Android AppSupport)**. Together with one config line, it replaces the big bar at the bottom of every Android app that holds only a back button.

| | Tap mode (default) | Swipe mode |
|---|---|---|
| Back | Tap | Swipe starting on the button (any direction) |
| Move the button (position is remembered) | Drag | Long press, then drag |
| Hide it for a few seconds (10 by default) | Long press | Long press and release |

In swipe mode a plain tap does nothing. In landscape the button is hidden automatically.

Tested on the Jolla Phone (2026), Sailfish OS 5.2.0.22, AppSupport (Android 15).

## Privacy / permissions

OneBack is an Android **accessibility service**, which is how it can send a system-wide Back to other apps.

- It **can't read screen content** (`canRetrieveWindowContent="false"`) and has no internet permission.
- It asks for no other permissions. The button is an accessibility overlay, so "display over other apps" isn't needed.
- The button is [`BackService.java`](src/dev/local/oneback/BackService.java), about 200 lines; the settings screen is [`MainActivity.java`](src/dev/local/oneback/MainActivity.java).

## Install

1. Download `oneback.apk` from the releases and open it on the phone (e.g. from `~/Downloads` in the file manager).
2. Open **OneBack** from the app grid and tap **Turn on in accessibility settings**. Switch on **"OneBack floating back button"** there.
3. Check that the button works.

## Settings

The OneBack app shows whether the button is on, switches between tap mode and swipe mode, and has a blank test page to leave with the button. It also lets you set the button's size, opacity and how long a long press hides it. Changes apply to the button right away. It can also move the button back to its default position.

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
- **OneBack:** switch it off in the accessibility settings (OneBack app → Accessibility settings), or uninstall it in Settings → Apps.

While the bar is hidden, don't switch OneBack off, or you'll only have the apps' own back arrows.

## Build

You need the Android SDK (build-tools 36.0.0, platform android-36) and a JDK. Gradle isn't needed.

```
./build.sh          # -> build/oneback.apk
```

The script runs `aapt2 → javac → d8 → zipalign → apksigner`. The SDK path defaults to `~/Android/Sdk`; override it with `ANDROID_HOME`. On the first run it creates a signing key, `oneback.keystore`. Keep it private and don't lose it: updates must be signed with the same key, or Android won't install them over an existing install.

## License

MIT, see [LICENSE](LICENSE).
