#!/bin/bash
# Build APK tanpa Gradle: aapt2 + javac + d8 + apksigner (JDK17, build-tools 33.0.2, android-33)
set -euo pipefail
cd "$(dirname "$0")"
SDK=${SDK:-$HOME/tools/android-sdk}; BT=$SDK/build-tools/33.0.2; AJ=$SDK/platforms/android-33/android.jar
export JAVA_HOME=${JAVA_HOME:-$HOME/tools/jdk17}; export PATH=$JAVA_HOME/bin:$PATH
rm -rf build && mkdir -p build/classes build/dex
$BT/aapt2 link -I $AJ --manifest AndroidManifest.xml -o build/base.apk
javac -source 8 -target 8 -bootclasspath $AJ -classpath $AJ:$BT/core-lambda-stubs.jar -d build/classes -Xlint:-options $(find src -name '*.java')
$BT/d8 --lib $AJ --min-api 29 --output build/dex $(find build/classes -name '*.class')
cp build/base.apk build/unsigned.apk && python3 -c "import zipfile;zipfile.ZipFile('build/unsigned.apk','a').write('build/dex/classes.dex','classes.dex')"
$BT/zipalign -f 4 build/unsigned.apk build/aligned.apk
[ -f debug.keystore ] || keytool -genkeypair -keystore debug.keystore -storepass android -keypass android -alias poc -keyalg RSA -keysize 2048 -validity 3650 -dname "CN=magnon-poc" >/dev/null 2>&1
$BT/apksigner sign --ks debug.keystore --ks-pass pass:android --key-pass pass:android --out ../magnon-poc-examine.apk build/aligned.apk
$BT/apksigner verify ../magnon-poc-examine.apk && ls -l ../magnon-poc-examine.apk && sha256sum ../magnon-poc-examine.apk
