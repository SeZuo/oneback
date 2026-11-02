# OneBack for Sailfish OS: the OneBack APK plus a switch in Settings > Android AppSupport
# that hides the Android navigation bar. Built by ../build-rpm.sh (noarch, no compiled code).
# Conventions: docs.sailfishos.org/Reference/Software_Packaging (Fedora guidelines + Sailfish changes).
# Sailfish defines %%_unitdir (systemd rpm macros); rpmbuild outside the SDK may not.
%{!?_unitdir:%global _unitdir /usr/lib/systemd/system}

Name:       oneback
Version:    %{oneback_version}
Release:    1
Summary:    Floating Back button for Android apps, and a switch to hide the navigation bar
License:    MIT
URL:        https://github.com/lorenz-graf/oneback
BuildArch:  noarch
Requires:   polkit
Requires:   systemd

%description
Installs OneBack, a floating Back button for Android apps (AppSupport), and adds a
OneBack section to Settings > Android AppSupport. There you can hide the Android
navigation bar, which then only holds a back button. The APK is installed into
AppSupport automatically, now or the next time AppSupport starts, and is updated
together with this package.

Uninstalling removes the switch and shows the navigation bar again after the next
AppSupport restart. OneBack itself stays installed (remove it in Settings > Apps).

%prep
cp %{_sourcedir}/LICENSE .

%build

%install
S=%{_sourcedir}
P=%{buildroot}%{_datadir}/jolla-settings/pages/android-runtime/plugins
install -D -m 0644 $S/oneback.apk                 %{buildroot}%{_datadir}/oneback/oneback.apk
echo %{version} >                                 %{buildroot}%{_datadir}/oneback/version
install -D -m 0644 $S/oneback-plugin.qml          $P/oneback.qml
sed -i 's/@VERSION@/%{version}/' $P/oneback.qml
install -D -m 0755 $S/navbar.sh                   %{buildroot}%{_libexecdir}/oneback/navbar
install -D -m 0755 $S/install.sh                  %{buildroot}%{_libexecdir}/oneback/install
install -D -m 0755 $S/check.sh                    %{buildroot}%{_libexecdir}/oneback/check
install -D -m 0644 $S/oneback-navbar-hide@.service %{buildroot}%{_unitdir}/oneback-navbar-hide@.service
install -D -m 0644 $S/oneback-check@.service      %{buildroot}%{_unitdir}/oneback-check@.service
install -D -m 0644 $S/oneback-navbar-show.service %{buildroot}%{_unitdir}/oneback-navbar-show.service
install -D -m 0644 $S/oneback-install@.service    %{buildroot}%{_unitdir}/oneback-install@.service
install -D -m 0644 $S/appsupport-oneback.conf     %{buildroot}%{_unitdir}/appsupport@.service.d/90-oneback.conf
install -D -m 0644 $S/49-oneback.rules            %{buildroot}%{_datadir}/polkit-1/rules.d/49-oneback.rules
install -d -m 0755 %{buildroot}/var/lib/oneback
# Written at runtime by the navbar helper; listed as %%ghost so rpm knows it belongs here.
install -d -m 0755 %{buildroot}%{_sysconfdir}/appsupport.conf.d
touch %{buildroot}%{_sysconfdir}/appsupport.conf.d/90-oneback-navbar.conf

%post
systemctl daemon-reload >/dev/null 2>&1 || :
# Install or update the APK for every AppSupport user (now if running, else at next start).
%{_libexecdir}/oneback/install --all-users >/dev/null 2>&1 || :

%postun
if [ "$1" -eq 0 ]; then
    # Uninstalled: the bar comes back after the next AppSupport restart.
    rm -f %{_sysconfdir}/appsupport.conf.d/90-oneback-navbar.conf
    rm -rf /var/lib/oneback /run/oneback
fi
systemctl daemon-reload >/dev/null 2>&1 || :

%files
%license LICENSE
%dir %{_datadir}/oneback
%dir %{_libexecdir}/oneback
%{_datadir}/oneback/oneback.apk
%{_datadir}/oneback/version
%{_datadir}/jolla-settings/pages/android-runtime/plugins/oneback.qml
%{_libexecdir}/oneback/navbar
%{_libexecdir}/oneback/install
%{_libexecdir}/oneback/check
%{_unitdir}/oneback-navbar-hide@.service
%{_unitdir}/oneback-check@.service
%{_unitdir}/oneback-navbar-show.service
%{_unitdir}/oneback-install@.service
%{_unitdir}/appsupport@.service.d/90-oneback.conf
%{_datadir}/polkit-1/rules.d/49-oneback.rules
%dir /var/lib/oneback
%ghost %{_sysconfdir}/appsupport.conf.d/90-oneback-navbar.conf
