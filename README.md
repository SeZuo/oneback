# OneBack

A one-tap floating Back button for Android apps on **Sailfish OS (Android AppSupport)**. Together with one config line, it replaces the big bar at the bottom of every Android app that holds only a back button.

| | |
|---|---|
| Tap, or swipe starting on the button | Back |
| Long press | The button grows and turns blue (moving is armed) |
| … then drag | Move the button (position is remembered) |
| … then release without dragging | Hide it for a few seconds (10 by default) |
| Landscape | Hidden automatically |

Tap and swipe are both on by default. Either one can be switched off in the settings, but not both. Swipes count in the directions you pick (default: left and right; the direction is the one the swipe mostly goes in).

Tested on the Jolla Phone (2026), Sailfish OS 5.2.0.22, AppSupport (Android 15).

## Privacy / permissions

OneBack is an Android **accessibility service**, which is how it can send a system-wide Back to other apps.

- It **can't read screen content** (`canRetrieveWindowContent="false"`) and has no internet permission.
- It asks for no other permissions. The button is an accessibility overlay, so "display over other apps" isn't needed.
- The button is [`BackService.java`](src/dev/local/oneback/BackService.java), about 200 lines; the settings screen is [`MainActivity.java`](src/dev/local/oneback/MainActivity.java).

## Install

### Sailfish package (recommended)

The package `oneback-<version>-1.noarch.rpm` brings OneBack and a **OneBack section in Settings → Android AppSupport**. Nothing has to be done in a terminal afterwards.

1. Install the package. Until it's on OpenRepos/Storeman: download it from the releases and install it as root:
   ```
   devel-su pkcon install-local oneback-<version>-1.noarch.rpm
   ```
2. OneBack is installed into AppSupport automatically (right away if AppSupport is running, otherwise the next time it starts) and allowed to run in the background.
3. Settings → Android AppSupport → **OneBack** → **Open OneBack** → **Turn on in accessibility settings**, and switch on **"OneBack floating back button"**.
4. Back in Settings, turn **Android navigation bar** off and tap **Restart Android AppSupport**.

The switch can only be turned off while OneBack is on and allowed in the background, so Android apps always keep a Back. The section also reinstalls OneBack if it was uninstalled, and warns if it stopped. Updating the package updates OneBack. Details: [`sailfish/README.md`](sailfish/README.md).

### APK only

1. Download `oneback.apk` from the releases and open it on the phone (e.g. from `~/Downloads` in the file manager).
2. Open **OneBack** from the app grid and tap **Turn on in accessibility settings**. Switch on **"OneBack floating back button"** there.
3. Settings → Apps → OneBack: switch on **"Allow application background services to start on bootup"**. Without it, Sailfish stops OneBack as soon as you leave it, and the button disappears.
4. Check that the button works.

## Settings

The OneBack app shows whether the button is on and has a blank test page to leave with the button. You can choose whether tap, swipe or both mean Back, and which swipe directions count. It also lets you set the button's size, opacity and how long a long press hides it. Changes apply to the button right away. It can also move the button back to its default position.

## Hide the Android navigation bar by hand

With the Sailfish package, use its switch instead. Without it: do this only after OneBack works, because otherwise Android apps have no system Back at all.

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

- **Bar (package):** turn **Android navigation bar** on in Settings → Android AppSupport → OneBack and restart AppSupport.
- **Bar (by hand):** delete `/etc/appsupport.conf.d/90-hide-navbar.conf` (as root) and Stop/Start AppSupport. If the package is installed, its switch also removes this file when it holds nothing else.
- **Package:** uninstall it in Storeman or with `devel-su pkcon remove oneback`. That removes its config file, so the bar comes back after the next AppSupport restart. OneBack itself stays installed.
- **OneBack:** switch it off in the accessibility settings (OneBack app → Accessibility settings), or uninstall it in Settings → Apps.

While the bar is hidden, don't switch OneBack off, or you'll only have the apps' own back arrows.

## Build

You need the Android SDK (build-tools 36.0.0, platform android-36) and a JDK. Gradle isn't needed.

```
./build.sh                  # -> build/oneback.apk
sailfish/build-rpm.sh       # -> sailfish/build/oneback-<version>-1.noarch.rpm (needs rpmbuild)
```

The script runs `aapt2 → javac → d8 → zipalign → apksigner`. The SDK path defaults to `~/Android/Sdk`; override it with `ANDROID_HOME`. On the first run it creates a signing key, `oneback.keystore`. Keep it private and don't lose it: updates must be signed with the same key, or Android won't install them over an existing install.

## License

MIT, see [LICENSE](LICENSE).
