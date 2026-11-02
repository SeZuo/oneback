/*
 * OneBack section in Settings > Android AppSupport.
 *
 * Loaded by the AppSupport settings page, which shows every .qml in its plugins/ folder.
 * Shows whether OneBack is installed and switched on, opens it, installs or updates the APK bundled
 * in this package, and hides or shows the Android navigation bar. Root work is done by
 * OneBack's own systemd units (allowed by /usr/share/polkit-1/rules.d/49-oneback.rules);
 * AppSupport is restarted the same way the page's own Stop/Start button does it.
 *
 * MIT licensed, part of https://github.com/lorenz-graf/oneback
 */
import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import com.jolla.apkd 1.0
import ".." // AppSupportStatus.qml from the AppSupport settings page

Column {
    id: root

    width: parent ? parent.width : 0
    bottomPadding: Theme.paddingLarge

    readonly property string bundledVersion: "@VERSION@"
    readonly property string user: AppUtils.currentUser
    readonly property string desktopFile: StandardPaths.home
            + "/.local/share/applications/apkd_launcher_dev_local_oneback-dev_local_oneback_MainActivity.desktop"
    // Written by oneback-check@<user>.service: on / off / unknown, read from Android's own
    // enabled_accessibility_services (the page can't read that without root).
    readonly property string a11yFile: "/run/oneback/a11y-" + user
    readonly property string ourConf: "/etc/appsupport.conf.d/90-oneback-navbar.conf"
    readonly property string handConf: "/etc/appsupport.conf.d/90-hide-navbar.conf" // from the README
    readonly property string generatedProps: "/tmp/appsupport/" + user + "/generated_props"

    property string installedVersion: ""   // "" = not installed
    property string a11yState: ""          // on / crashed / off / unknown (see /usr/libexec/oneback/check)
    property bool backgroundAllowed: true  // Settings > Apps > OneBack: run in background
    // Without background running Sailfish stops OneBack as soon as it leaves the foreground,
    // which kills the service, so only count it as on with both.
    readonly property bool serviceOn: a11yState === "on" && backgroundAllowed
    property bool hideWanted: false        // our config file exists
    property bool handHidden: false        // the hand-made file from the README hides it
    property bool handOther: false         // ... and holds other settings, so it can't be removed
    property bool hideApplied: false       // running AppSupport has mainkeys=1
    property bool busy: false
    property bool restartRequested: false
    property string error: ""

    readonly property bool installed: installedVersion !== ""
    // Hidden by either file. Turning the switch off removes ours, and the hand-made one too
    // when it only holds the navbar setting (see /usr/libexec/oneback/navbar).
    readonly property bool hidden: hideWanted || handHidden
    readonly property bool needsRestart: appSupport.running && hidden !== hideApplied

    function readFile(path, done) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                done(xhr.responseText ? xhr.responseText : "")
            }
        }
        xhr.open("GET", "file://" + path)
        xhr.send()
    }

    function refresh() {
        readFile(desktopFile, function(text) {
            var m = text.match(/^X-apkd-packageVersion=(.*)$/m)
            installedVersion = m ? m[1].trim() : ""
        })
        readFile(a11yFile, function(text) { a11yState = text.trim() })
        if (installed) {
            apkdUser.typedCall("getAppStartOnBootup", [{ "type": "s", "value": "dev.local.oneback" }],
                function(allowed) { backgroundAllowed = allowed }, function() { })
        }
        readFile(ourConf, function(text) { hideWanted = text.indexOf("qemu.hw.mainkeys=1") >= 0 })
        readFile(handConf, function(text) {
            handHidden = text.indexOf("qemu.hw.mainkeys=1") >= 0
            handOther = text.split("\n").some(function(line) {
                line = line.trim()
                return line !== "" && line.charAt(0) !== "#" && line !== "[Config]"
                        && line !== "CustomProperties=qemu.hw.mainkeys=1"
            })
        })
        readFile(generatedProps, function(text) {
            hideApplied = text.indexOf("qemu.hw.mainkeys=1") >= 0
        })
    }

    function startUnit(name) {
        busy = true
        error = ""
        systemd.typedCall("StartUnit", [
            { "type": "s", "value": name },
            { "type": "s", "value": "replace" }
        ], function() {
            settle.restart()
        }, function(err) {
            busy = false
            error = "Didn't work: " + err
        })
    }

    function restartAppSupport() {
        restartRequested = true
        apkd.typedCall("controlService", [
            { "type": "b", "value": false },
            { "type": "s", "value": user }
        ])
    }

    // Ask the root helper to re-read the accessibility setting; refresh() picks up its file.
    function checkA11y() {
        systemd.typedCall("StartUnit", [
            { "type": "s", "value": "oneback-check@" + user + ".service" },
            { "type": "s", "value": "replace" }
        ], function() { }, function(err) { console.warn("OneBack: check:", err) })
    }

    Component.onCompleted: { checkA11y(); refresh() }

    // Things change outside this page (OneBack switched on, install finished, ...).
    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.visible && Qt.application.active
        onTriggered: { root.checkA11y(); root.refresh() }
    }

    Timer {
        id: settle
        interval: 1500
        onTriggered: {
            root.busy = false
            root.refresh()
        }
    }

    DBusInterface {
        id: systemd
        bus: DBus.SystemBus
        service: "org.freedesktop.systemd1"
        path: "/org/freedesktop/systemd1"
        iface: "org.freedesktop.systemd1.Manager"
    }

    // Opening an Android app from here takes two calls: lipstick (the home screen) has to be
    // told first that the app is launching, so it prepares and shows a window for it; then
    // apkd starts the app. launchApp alone starts it in Android but nothing appears on screen.
    function openOneBack() {
        lipstick.typedCall("notifyLaunching", [{ "type": "s", "value": desktopFile }],
            function() { launch() }, function(err) { console.warn("OneBack: notifyLaunching:", err); launch() })
        function launch() {
            apkdUser.typedCall("launchApp", [{ "type": "s", "value": "dev.local.oneback" }],
                function() { }, function(err) { error = "Couldn't open OneBack: " + err })
        }
    }

    DBusInterface {
        id: lipstick
        bus: DBus.SessionBus
        service: "org.nemomobile.lipstick"
        path: "/LauncherModel"
        iface: "org.nemomobile.lipstick.LauncherModel"
    }

    DBusInterface {
        id: apkdUser
        bus: DBus.SessionBus
        service: "com.jolla.apkd"
        path: "/com/jolla/apkd"
        iface: "com.jolla.apkd"
    }

    DBusInterface {
        id: apkd
        bus: DBus.SystemBus
        service: "com.jolla.apkd.control"
        path: "/com/jolla/apkd"
        iface: "com.jolla.apkd.control"
    }

    AppSupportStatus {
        id: appSupport
        // Restart = stop, then start once it has stopped.
        onStateChanged: {
            if (root.restartRequested && !running && !transitioning) {
                root.restartRequested = false
                apkd.typedCall("controlService", [
                    { "type": "b", "value": true },
                    { "type": "s", "value": root.user }
                ])
            }
            root.refresh()
        }
    }

    SectionHeader {
        text: "OneBack"
    }

    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Theme.highlightColor
        text: {
            if (!root.installed)
                return "OneBack isn't installed. Install it again with the button below; it comes with this package."
            if (root.installedVersion !== root.bundledVersion)
                return "OneBack " + root.installedVersion + " is installed. This package includes version "
                        + root.bundledVersion + "."
            if (!appSupport.running || root.a11yState === "unknown")
                return "OneBack is installed. Start Android AppSupport to see whether it's switched on."
            if (!root.backgroundAllowed)
                return "OneBack isn't allowed to run in the background, so Sailfish stops it whenever you leave it. Allow it below."
            if (root.a11yState === "crashed")
                return "OneBack is switched on, but Android stopped it. Open OneBack, go to the accessibility settings and switch it off and on again."
            if (!root.serviceOn)
                return "OneBack is installed, but switched off in the accessibility settings. Open OneBack to switch it on."
            return "OneBack is installed and switched on."
        }
    }

    Item { width: 1; height: Theme.paddingMedium }

    ButtonLayout {
        visible: root.installed
        Button {
            enabled: appSupport.running
            text: "Open OneBack"
            onClicked: root.openOneBack()
        }
    }

    Item { width: 1; height: Theme.paddingMedium; visible: root.installed }

    ButtonLayout {
        visible: root.installed && !root.backgroundAllowed
        Button {
            text: "Allow in background"
            // Same call as the switch in Settings > Apps > OneBack.
            onClicked: apkdUser.typedCall("setAppStartOnBootup", [
                { "type": "s", "value": "dev.local.oneback" },
                { "type": "b", "value": true }
            ], function() { root.refresh() }, function(err) { root.error = "Didn't work: " + err })
        }
    }

    Item { width: 1; height: Theme.paddingMedium; visible: root.installed && !root.backgroundAllowed }

    ButtonLayout {
        visible: !root.installed || root.installedVersion !== root.bundledVersion
        Button {
            enabled: !root.busy && appSupport.running
            text: root.installed ? "Update OneBack" : "Install OneBack"
            onClicked: root.startUnit("oneback-install@" + root.user + ".service")
        }
    }

    Label {
        visible: (!root.installed || root.installedVersion !== root.bundledVersion) && !appSupport.running
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
        text: "Start Android AppSupport first. OneBack is also installed automatically the next time it starts."
    }

    // On = the bar is shown (Android's default). Off = hidden, OneBack does Back instead.
    TextSwitch {
        text: "Android navigation bar"
        description: root.hidden || root.installed && root.serviceOn
                     ? "Turn off to hide the bar at the bottom of Android apps and use the OneBack button for Back instead."
                     : "Can only be turned off while OneBack is on, so Android apps always have a Back."
        automaticCheck: false
        checked: !root.hidden
        busy: root.busy
        // Hiding needs OneBack on; showing the bar again is always allowed.
        enabled: !root.busy && (root.hidden || root.installed && root.serviceOn)
        // The hide helper checks again itself and refuses while OneBack is off.
        onClicked: root.startUnit(root.hidden ? "oneback-navbar-show.service"
                                              : "oneback-navbar-hide@" + root.user + ".service")
    }

    Label {
        visible: root.hideApplied && !root.serviceOn
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Theme.errorColor
        text: "The navigation bar is hidden but OneBack is off, so Android apps have no Back. Switch OneBack on, or turn the navigation bar back on and restart."
    }

    Label {
        // Only when the switch can't undo it: the hand-made file has other settings too.
        visible: root.handHidden && root.handOther
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
        text: "The bar is also hidden by " + root.handConf + ", which has other settings in it, so this switch leaves it alone. Remove the qemu.hw.mainkeys line there (as root) to show the bar again."
    }

    Label {
        visible: root.needsRestart || root.restartRequested
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Theme.highlightColor
        text: "Restart Android AppSupport to apply this. Running Android apps are closed."
    }

    Item {
        visible: root.needsRestart || root.restartRequested
        width: 1
        height: Theme.paddingLarge
    }

    ButtonLayout {
        visible: root.needsRestart || root.restartRequested
        Button {
            enabled: !appSupport.transitioning && !root.restartRequested
            text: "Restart Android AppSupport"
            onClicked: root.restartAppSupport()
        }
    }

    Label {
        visible: root.error !== ""
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: Theme.errorColor
        text: root.error
    }
}
