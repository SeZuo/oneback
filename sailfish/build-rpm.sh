#!/bin/sh
# Builds the Sailfish package: sailfish/build/oneback-<version>-1.noarch.rpm
# Builds the APK first (../build.sh) and takes the version from there, so APK and RPM
# always match. Needs rpmbuild (Arch: pacman -S rpm-tools). Sailfish has rpm 4.16, so the
# package is written in rpm v4 format with a gzip payload (rpm 6 defaults to v6 + zstd), and
# the directory macros are set to Sailfish's values (read with rpm --eval on the phone), since
# the build host's can differ (Arch: _sharedstatedir=/usr/com).
set -eu
cd "$(dirname "$0")"

../build.sh >/dev/null
VERSION=$(sed -n 's/.*--version-name \([0-9.]*\).*/\1/p' ../build.sh)

TOP=$(pwd)/build
rm -rf "$TOP" && mkdir -p "$TOP/SOURCES"
cp oneback-plugin.qml navbar.sh install.sh check.sh uninstall.sh ./*.service appsupport-oneback.conf 49-oneback.rules \
    "$TOP/SOURCES/"
cp ../build/oneback.apk ../LICENSE "$TOP/SOURCES/"

rpmbuild -bb --quiet \
    --define "_topdir $TOP" \
    --define "oneback_version $VERSION" \
    --define "_binary_payload w9.gzdio" \
    --define "_rpmformat 4" \
    --define "_prefix /usr" --define "_datadir /usr/share" --define "_libexecdir /usr/libexec" \
    --define "_sysconfdir /etc" --define "_unitdir /usr/lib/systemd/system" \
    rpm/oneback.spec
mv "$TOP"/RPMS/noarch/*.rpm "$TOP/"
echo "built: $(ls "$TOP"/*.rpm)"
