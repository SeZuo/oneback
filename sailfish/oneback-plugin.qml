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
    property bool uninstalling: false
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
            // Just started: Android is still booting and can report OneBack as off for a while.
            if (running && !transitioning) {
                root.settling = true
                settleAfterStart.restart()
            }
            root.refresh()
        }
    }

    // While AppSupport stops, starts or has only just started, the files the page reads are
    // stale (generated_props from the last run, accessibility state not readable yet), so
    // warnings about OneBack's state wait until it's up.
    property bool settling: false
    readonly property bool appSupportReady: appSupport.running && !appSupport.transitioning
                                            && !restartRequested && !settling
    readonly property bool appSupportChanging: appSupport.transitioning || restartRequested || settling

    Timer {
        id: settleAfterStart
        interval: 20000
        onTriggered: { root.settling = false; root.checkA11y(); root.refresh() }
    }

    function setBackground(allowed) {
        error = ""
        // Same call as the switch in Settings > Apps > OneBack.
        apkdUser.typedCall("setAppStartOnBootup", [
            { "type": "s", "value": "dev.local.oneback" },
            { "type": "b", "value": allowed }
        ], function() { root.refresh() }, function(err) { root.error = "Didn't work: " + err })
    }

    function uninstall() {
        uninstalling = true
        error = ""
        systemd.typedCall("StartUnit", [
            { "type": "s", "value": "oneback-uninstall@" + user + ".service" },
            { "type": "s", "value": "replace" }
        ], function() { }, function(err) {
            root.uninstalling = false
            root.error = "Didn't work: " + err
        })
    }

    // Layout follows Jolla's own sections (e.g. Backup in Settings > Sailfish OS updates):
    // one short hint, settings as switches, actions as icon rows. A row either acts right away
    // (open, restart) or opens its own page (uninstall, confirmed there with Accept).

    SectionHeader {
        text: "OneBack"
    }

    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: implicitHeight + Theme.paddingSmall
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        // Red while OneBack isn't working yet (the cases below that need the user to act);
        // the usual description colour when it works or the text is only informational.
        readonly property bool needsSetup: !root.uninstalling
                && (!root.installed
                    || root.installedVersion === root.bundledVersion && root.appSupportReady
                       && root.a11yState !== "" && root.a11yState !== "unknown" && !root.serviceOn)
        color: needsSetup ? Theme.errorColor : Theme.secondaryHighlightColor
        text: {
            if (root.uninstalling)
                return "Uninstalling: Android AppSupport restarts with the navigation bar, then OneBack and this section are removed. This takes a minute."
            if (!root.installed)
                return "OneBack isn't installed. It comes with this package, install it again below."
            if (root.installedVersion !== root.bundledVersion)
                return "OneBack " + root.installedVersion + " is installed. This package includes version "
                        + root.bundledVersion + "."
            if (root.appSupportChanging)
                return "Android AppSupport is restarting. OneBack's state shows here once it's up."
            if (!appSupport.running || root.a11yState === "unknown")
                return "OneBack is installed. Start Android AppSupport to see whether it's switched on."
            if (!root.backgroundAllowed)
                return "OneBack isn't allowed to run in the background, so Sailfish stops it whenever you leave it. Switch on Run in background below."
            if (root.a11yState === "crashed")
                return "OneBack is switched on, but Android stopped it. Open OneBack, go to the accessibility settings and switch it off and on again."
            if (!root.serviceOn)
                return "OneBack is switched off in the accessibility settings. Open OneBack to switch it on."
            return "OneBack is installed and switched on."
        }
    }

    BackgroundItem {
        id: openRow
        visible: root.installed
        enabled: appSupport.running && !root.uninstalling
        height: Math.max(implicitHeight, openLabel.height + 2 * Theme.paddingSmall)
        onClicked: root.openOneBack()

        Icon {
            id: openIcon
            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: "image://theme/icon-m-android"
            highlighted: openRow.highlighted
            opacity: openRow.enabled ? 1.0 : Theme.opacityLow
        }
        Label {
            id: openLabel
            anchors {
                left: openIcon.right
                leftMargin: Theme.paddingMedium
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            wrapMode: Text.Wrap
            color: openRow.highlighted ? Theme.highlightColor : Theme.primaryColor
            opacity: openRow.enabled ? 1.0 : Theme.opacityLow
            text: "Open OneBack"
        }
    }

    BackgroundItem {
        id: installRow
        visible: !root.installed || root.installedVersion !== root.bundledVersion
        enabled: !root.busy && appSupport.running && !root.uninstalling
        height: Math.max(implicitHeight, installLabel.height + 2 * Theme.paddingSmall)
        onClicked: root.startUnit("oneback-install@" + root.user + ".service")

        Icon {
            id: installIcon
            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: "image://theme/icon-m-device-download"
            highlighted: installRow.highlighted
            opacity: installRow.enabled ? 1.0 : Theme.opacityLow
        }
        Label {
            id: installLabel
            anchors {
                left: installIcon.right
                leftMargin: Theme.paddingMedium
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            wrapMode: Text.Wrap
            color: installRow.highlighted ? Theme.highlightColor : Theme.primaryColor
            opacity: installRow.enabled ? 1.0 : Theme.opacityLow
            text: root.installed ? "Update OneBack" : "Install OneBack"
        }
    }

    Label {
        visible: installRow.visible && !appSupport.running
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
        text: "Start Android AppSupport first. OneBack is also installed automatically the next time it starts."
    }

    // The two switches are laid out like the page's own AppSupportSwitch (icon on the right,
    // description below at full width), which can't show the busy spinner the bar switch needs.

    // Settings > Apps > OneBack has the same switch.
    Column {
        visible: root.installed
        width: parent.width
        bottomPadding: Theme.paddingLarge + Theme.paddingMedium
        spacing: Theme.paddingMedium

        IconTextSwitch {
            id: backgroundSwitch
            text: "Run in background"
            icon.source: "image://theme/icon-m-battery"
            automaticCheck: false
            checked: root.backgroundAllowed
            enabled: !root.uninstalling
            onClicked: root.setBackground(!root.backgroundAllowed)
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            opacity: backgroundSwitch.enabled ? 1.0 : Theme.opacityLow
            text: "Needed for the Back button: without it, Sailfish stops OneBack whenever you leave it."
        }
    }

    // On = the bar is shown (Android's default). Off = hidden, OneBack does Back instead.
    Column {
        width: parent.width
        bottomPadding: Theme.paddingLarge + Theme.paddingMedium
        spacing: Theme.paddingMedium

        IconTextSwitch {
            id: navbarSwitch
            text: "Android navigation bar"
            icon.source: "image://theme/icon-m-back"
            automaticCheck: false
            checked: !root.hidden
            busy: root.busy
            // Hiding needs OneBack on; showing the bar again is always allowed.
            enabled: !root.busy && !root.uninstalling && (root.hidden || root.installed && root.serviceOn)
            // The hide helper checks again itself and refuses while OneBack is off.
            onClicked: root.startUnit(root.hidden ? "oneback-navbar-show.service"
                                                  : "oneback-navbar-hide@" + root.user + ".service")
        }

        Label {
            x: Theme.horizontalPageMargin
            width: parent.width - 2 * Theme.horizontalPageMargin
            wrapMode: Text.Wrap
            font.pixelSize: Theme.fontSizeExtraSmall
            color: Theme.secondaryHighlightColor
            opacity: navbarSwitch.enabled || root.busy ? 1.0 : Theme.opacityLow
            text: root.hidden || root.installed && root.serviceOn
                  ? "Turn off to hide the bar at the bottom of Android apps and use the OneBack button for Back instead."
                  : "Can only be turned off while OneBack is on, so Android apps always have a Back."
        }
    }

    Label {
        visible: root.appSupportReady && root.hideApplied && !root.serviceOn && !root.uninstalling
            && root.a11yState !== "" && root.a11yState !== "unknown"
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: implicitHeight + Theme.paddingLarge
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
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
        visible: (root.needsRestart || root.restartRequested) && !root.uninstalling
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        height: implicitHeight + Theme.paddingSmall
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryHighlightColor
        text: "Restart Android AppSupport to apply this. Running Android apps are closed."
    }

    BackgroundItem {
        id: restartRow
        visible: (root.needsRestart || root.restartRequested) && !root.uninstalling
        enabled: !appSupport.transitioning && !root.restartRequested
        height: Math.max(implicitHeight, restartLabel.height + 2 * Theme.paddingSmall)
        onClicked: root.restartAppSupport()

        Icon {
            id: restartIcon
            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: "image://theme/icon-m-reload"
            highlighted: restartRow.highlighted
            opacity: restartRow.enabled ? 1.0 : Theme.opacityLow
        }
        Label {
            id: restartLabel
            anchors {
                left: restartIcon.right
                leftMargin: Theme.paddingMedium
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            wrapMode: Text.Wrap
            color: restartRow.highlighted ? Theme.highlightColor : Theme.primaryColor
            opacity: restartRow.enabled ? 1.0 : Theme.opacityLow
            text: root.restartRequested ? "Restarting Android AppSupport…" : "Restart Android AppSupport"
        }
    }

    BackgroundItem {
        id: uninstallRow
        enabled: !root.busy && !root.uninstalling
        height: Math.max(implicitHeight, uninstallLabel.height + 2 * Theme.paddingSmall)
        onClicked: pageStack.animatorPush(uninstallDialog)

        Icon {
            id: uninstallIcon
            x: Theme.horizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            source: "image://theme/icon-m-delete"
            highlighted: uninstallRow.highlighted
            opacity: uninstallRow.enabled ? 1.0 : Theme.opacityLow
        }
        Label {
            id: uninstallLabel
            anchors {
                left: uninstallIcon.right
                leftMargin: Theme.paddingMedium
                right: parent.right
                rightMargin: Theme.horizontalPageMargin
                verticalCenter: parent.verticalCenter
            }
            wrapMode: Text.Wrap
            color: uninstallRow.highlighted ? Theme.highlightColor : Theme.primaryColor
            opacity: uninstallRow.enabled ? 1.0 : Theme.opacityLow
            text: "Uninstall OneBack"
        }
    }

    // Own page for the one destructive action; Accept (or swiping forward) uninstalls.
    Component {
        id: uninstallDialog

        Dialog {
            onAccepted: root.uninstall()

            Column {
                width: parent.width

                DialogHeader {
                    acceptText: "Uninstall"
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    text: "Uninstall OneBack?"
                }

                Item { width: 1; height: Theme.paddingLarge }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    color: Theme.highlightColor
                    text: "The navigation bar is shown again, Android AppSupport restarts (running Android apps are closed), and OneBack and its section in these settings are removed."
                }

                Item { width: 1; height: Theme.paddingLarge }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    wrapMode: Text.Wrap
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.secondaryHighlightColor
                    text: "Accept to uninstall, or go back to keep OneBack."
                }
            }
        }
    }

    Label {
        visible: root.error !== ""
        x: Theme.horizontalPageMargin
        width: parent.width - 2 * Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.errorColor
        text: root.error
    }
}
