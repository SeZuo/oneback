#!/bin/sh
# Builds OneBack without Gradle: aapt2 -> javac -> d8 -> zipalign -> apksigner.
# Output: build/oneback.apk. Signing key: oneback.keystore (created on first run, keep it:
# updates must be signed with the same key or Android refuses to install over the old version).
set -eu
cd "$(dirname "$0")"

SDK=${ANDROID_HOME:-$HOME/Android/Sdk}
BT=$SDK/build-tools/36.0.0
JAR=$SDK/platforms/android-36/android.jar
MIN=24
TARGET=35   # Android 15 = AppSupport on SFOS 5.x

rm -rf build && mkdir -p build/gen build/classes build/dex

"$BT/aapt2" compile --dir res -o build/res.zip
"$BT/aapt2" link -I "$JAR" --manifest AndroidManifest.xml -o build/base.apk build/res.zip \
    --java build/gen --min-sdk-version $MIN --target-sdk-version $TARGET \
    --version-code 6 --version-name 1.5

javac --release 17 -classpath "$JAR" -d build/classes \
    $(find src build/gen -name '*.java')

"$BT/d8" --release --lib "$JAR" --min-api $MIN --output build/dex \
    $(find build/classes -name '*.class')

cp build/base.apk build/unsigned.apk
python3 -I -c 'import zipfile,sys; zipfile.ZipFile(sys.argv[1],"a",zipfile.ZIP_DEFLATED).write(sys.argv[2],"classes.dex")' \
    build/unsigned.apk build/dex/classes.dex
"$BT/zipalign" -f -p 4 build/unsigned.apk build/aligned.apk

if [ ! -f oneback.keystore ]; then
    keytool -genkeypair -keystore oneback.keystore -storepass oneback -keypass oneback \
        -alias oneback -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=OneBack local"
fi
"$BT/apksigner" sign --ks oneback.keystore --ks-pass pass:oneback --key-pass pass:oneback \
    --out build/oneback.apk build/aligned.apk
"$BT/apksigner" verify build/oneback.apk
echo "built: $(pwd)/build/oneback.apk"
