#!/bin/bash
# This script was tested on 10.11.1 with Xcode 7.1 installed, your mileage may vary.

if [[ "$#" -lt 2 ]]; then
  echo "Usage: "$(basename "$0")" (file name/url) (Developer Identity) [(.mobileprovision file)] [(new app id)]"
  echo "You can ommit the mobileprovision file if you just want to re-sign the app."
  echo "It is also possible to specify a new app id, this is only possible if you have a wildcard .mobileprovision file."
  echo "The application id will be changed to the mobileprovision file if it is not a wildcard."
  echo "It is also possible to change the app id without specifying a mobileprovision file, just use two quotes \"\""
  exit
fi

LIST_BINARY_EXTENSIONS="dylib so 0 vis pvr framework"
TEMP="$(mktemp -d)"
OUTPUT="$TEMP/out"
mkdir "$OUTPUT"
CURRENT_PATH="$(pwd)"

Extension="${1##*.}"

if [[ "$1" == http*://* && ("$Extension" == "deb" || "$Extension" == "ipa")]]; then
  curl "$1" > "$TEMP/app.$Extension"
else
  if [[ "$Extension" != "app" ]]; then
    cp "$1" "$TEMP/app.$Extension"
  fi
fi

case "$Extension" in
  deb )
    cd "$TEMP"
    ar -x "$TEMP/app.$Extension"
    tar --lzma -xvf data.tar.lzma
    mv Applications/ "$OUTPUT/Payload/"
    ;;
  ipa )
    unzip -q "$TEMP/app.$Extension" -d "$OUTPUT"
    ;;
  app )
    mkdir "$OUTPUT/Payload"
    cp -r "$1" "$OUTPUT/Payload"
    ;;
  *) echo "Filetype not supported"; exit
esac

AppBundleName="$(ls "$OUTPUT/Payload/" | sort -n | head -1)"
EntitlementsPlist="$OUTPUT/entitlements.plist"
AppIdentifier="$(defaults read "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier)"

if [ -n "$3" && -e "$3" ]; then
  rm "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision"
  cp "$3" "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision"
fi

if [ -z "$3" && -e "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision"]; then
  MobileProvisionIdentifier="$(egrep -a -A 2 application-identifier "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //')"
  MobileProvisionIdentifier="${MobileProvisionIdentifier#*.}"
  
  if [ "$MobileProvisionIdentifier" != "*" && "$MobileProvisionIdentifier" != "$AppIdentifier" && -z "$4" ]; then
    defaults write "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$MobileProvisionIdentifier"
    AppIdentifier="$MobileProvisionIdentifier"
    echo "Changed app identifier to $AppIdentifier to match the provisioning profile"
  fi
else
  MobileProvisionIdentifier="*"
fi

if [ -n "$4" ]; then
  if [[ "$MobileProvisionIdentifier" != "*" && "$MobileProvisionIdentifier" != "$4" ]]; then
    echo "You wanted to change the app identifier to $4 but your provisioning profile would not allow this! ($MobileProvisionIdentifier)"
    exit
  fi
  defaults write "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$4"
  AppIdentifier="$4"
  echo "Changed app identifier to $AppIdentifier"
fi

defaults delete "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleResourceSpecification
security cms -D -i "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" > "$TEMP/mobileprovision.plist"
/usr/libexec/PlistBuddy -c "Print :Entitlements" "$TEMP/mobileprovision.plist" -x > "$EntitlementsPlist"

for binext in $LIST_BINARY_EXTENSIONS; do
  for signfile in $(find "$OUTPUT/Payload/$AppBundleName" -name "*.$binext" -type f); do
    if[ -e "$EntitlementsPlist"]; then
      codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist" "$signfile"
    else
      codesign -vvv -fs "$2" --no-strict "$signfile"
    fi
  done
done

if[ -e "$EntitlementsPlist"]; then
  codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist"  "$OUTPUT/Payload/$AppBundleName"
else
  codesign -vvv -fs "$2" --no-strict   "$OUTPUT/Payload/$AppBundleName"
fi

rm "$CURRENT_PATH/$AppIdentifier-signed.ipa"
cd "$OUTPUT"
zip -qry "$CURRENT_PATH/$AppIdentifier-signed.ipa" "."
cd "$CURRENT_PATH"
rm -rf "$TEMP"