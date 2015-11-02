#!/bin/bash
LIST_BINARY_EXTENSIONS="dylib so 0 vis pvr"
TEMP="$(mktemp -d)"
OUTPUT="$TEMP/out"
mkdir "$OUTPUT"
CURRENT_PATH="$(pwd)"
cd "$TEMP"
if [[ "$#" -lt 3 ]]; then
  echo "Usage: "$(basename "$0")" (file name/url) (Developer Identity) (.mobileprovision file) [(new app id)]"
  exit
fi

Extension="${1##*.}"

if [[ "$1" == http*://* && ("$Extension" == "deb" || "$Extension" == "ipa")]]; then
  curl "$1" > "app.$Extension"
else
  if [[ "$Extension" != "app" ]]; then
    cp "$1" "app.$Extension"
  fi
fi

case "$Extension" in
  deb )
    ar -x "app.$Extension"
    tar --lzma -xvf data.tar.lzma
    mv Applications/ "$OUTPUT/Payload/"
    ;;
  ipa )
  	cd "$OUTPUT"
    unzip "$TEMP/app.$Extension"
    ;;
  app )
  	cd "$OUTPUT"
    mkdir Payload
    cp -r "$1" "Payload"
    ;;
  *) echo "Filetype not supported"; exit
esac

AppBundleName="$(ls "$OUTPUT/Payload/" | sort -n | head -1)"

EntitlementsPlist="$OUTPUT/entitlements.plist"

AppIdentifier="$(defaults read $OUTPUT/Payload/$AppBundleName/Info.plist CFBundleIdentifier)"
CFBundleName="$(defaults read $OUTPUT/Payload/$AppBundleName/Info.plist CFBundleName)"
CFBundleExecutable="$(defaults read $OUTPUT/Payload/$AppBundleName/Info.plist CFBundleExecutable)"

cp "$3" "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision"
MobileProvisionIdentifier="$(egrep -a -A 2 application-identifier $OUTPUT/Payload/$AppBundleName/embedded.mobileprovision | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //')"
TeamIdentifier="$(egrep -a -A 2 com.apple.developer.team-identifier $OUTPUT/Payload/$AppBundleName/embedded.mobileprovision | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //' | xargs)"

MobileProvisionIdentifier=${MobileProvisionIdentifier#*.}
if [ "$MobileProvisionIdentifier" != "*" ]; then
  defaults write "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$MobileProvisionIdentifier"
  AppIdentifier="$MobileProvisionIdentifier"
  echo "New App Identifier - $AppIdentifier"
fi

if [ -n "$4" ];then
  defaults write "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$4"
  AppIdentifier="$4"
fi

defaults delete "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleResourceSpecification

security cms -D -i "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" > "$TEMP/mobileprovision.plist"

/usr/libexec/PlistBuddy -c "Print :Entitlements" "$TEMP/mobileprovision.plist" -x > "$EntitlementsPlist"

for binext in $LIST_BINARY_EXTENSIONS; do
  for signfile in $(find "$OUTPUT/Payload/$AppBundleName" -name "*.$binext" -type f); do
    codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist" "$signfile"
  done
   
done
codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist"  "$OUTPUT/Payload/$AppBundleName"

for framework in $(find "$OUTPUT/Payload/$AppBundleName/Frameworks" -name "*.framework"); do
  codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist" "$framework"
done
for dylib in $(find "$OUTPUT/Payload/$AppBundleName/Frameworks" -name "*.dylib"); do
  codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist" "$dylib"
done

codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist"  "$OUTPUT/Payload/$AppBundleName"

rm "$CURRENT_PATH/$AppIdentifier-signed.ipa"
cd "$OUTPUT"
zip -qry "$CURRENT_PATH/$AppIdentifier-signed.ipa" "."
echo $CURRENT_PATH
cd "$CURRENT_PATH"
echo "$TEMP"
#rm -rf "$TEMP"