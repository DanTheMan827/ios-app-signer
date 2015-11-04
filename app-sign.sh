#!/bin/bash
# This script was tested on 10.11.1 with Xcode 7.1 installed, your mileage may vary.
echo "iOS App Signer rev. 34"
if [[ "$#" -lt 2 ]]; then
  echo "Usage: "$(basename "$0")" (file name/url) (Developer Identity) [(.mobileprovision file)] [(new app id)]"
  echo ""
  echo "You can ommit the mobileprovision file if you just want to re-sign the app."
  echo "It is also possible to specify a new app id, this is only possible if you have a wildcard .mobileprovision file."
  echo "The application id will be changed to the mobileprovision file if it is not a wildcard."
  echo "It is also possible to change the app id without specifying a mobileprovision file, just use two quotes \"\""
  echo ""
  echo "Supported filetypes are .deb, .ipa, and app bundles"
  exit 1
fi

LIST_BINARY_EXTENSIONS="dylib so 0 vis pvr framework"
TEMP="$(mktemp -d)"
OUTPUT="$TEMP/out"
mkdir "$OUTPUT"
CURRENT_PATH="$(pwd)"

Extension="${1##*.}"
FilePath="$1"

if [[ "$1" == http*://* ]] && [[ ("$Extension" == "deb" || "$Extension" == "ipa") ]]; then
  curl "$1" > "$TEMP/app.$Extension" || (echo "Error Downloading: $1"; exit 1)
  FilePath="$TEMP/app.$Extension"
fi

if [[ ! -e "$FilePath" ]]; then
    echo "File not found: $1"
    exit 1
fi

case "$Extension" in
  deb )
    echo "Extracting .deb file"
    mkdir "$TEMP/deb"
    cd "$TEMP/deb"
    ar -x "$FilePath" >/dev/null 2>&1 || (echo "Error extracting .deb"; exit 1)
    
    tar -xvf $TEMP/deb/data.tar* >/dev/null 2>&1  || (echo "Error untarring .deb data file"; exit 1)
    
    mv "$TEMP/deb/Applications/" "$OUTPUT/Payload/"
    ;;
  ipa )
    echo "Unzipping .ipa file"
    unzip -q "$FilePath" -d "$OUTPUT" > /dev/null || (echo "Error extracting $FilePath"; exit 1)
    ;;
  app )
    if [ ! -d "$FilePath" ]; then
      echo "$FilePath is not a directory"
      exit 1
    fi
    echo "Copying .app to temp folder"
    mkdir "$OUTPUT/Payload"
    cp -r "$FilePath" "$OUTPUT/Payload"
    ;;
  *) echo "Filetype not supported"; exit 1
esac

AppBundleName="$(ls "$OUTPUT/Payload/" | sort -n | head -1)"
EntitlementsPlist="$OUTPUT/entitlements.plist"
AppIdentifier="$(defaults read "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier)"

if [[ -n "$3" ]] && [[ -e "$3" ]]; then
  if [[ -e "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" ]]; then
    echo "Deleted .mobileprovision in app bundle"
    rm "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision"
  fi
  
  echo "Copy .mobileprovision to app bundle"
  cp "$3" "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision"
fi

if [[ -e "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" ]]; then
  MobileProvisionIdentifier="$(egrep -a -A 2 application-identifier "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //')"
  MobileProvisionIdentifier="${MobileProvisionIdentifier#*.}"
  
  if [[ "$MobileProvisionIdentifier" != "*" ]] && [[ "$MobileProvisionIdentifier" != "$AppIdentifier" ]] && [[ -z "$4" ]]; then
    defaults write "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$MobileProvisionIdentifier"
    AppIdentifier="$MobileProvisionIdentifier"
    echo "Changed app identifier to $AppIdentifier to match the provisioning profile"
  fi
else
  MobileProvisionIdentifier="*"
fi

if [[ -n "$4" ]]; then
  if [[ "$MobileProvisionIdentifier" != "*" ]] && [[ "$MobileProvisionIdentifier" != "$4" ]]; then
    echo "You wanted to change the app identifier to $4 but your provisioning profile would not allow this! ($MobileProvisionIdentifier)"
    exit 1
  fi
  defaults write "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$4"
  AppIdentifier="$4"
  echo "Changed app identifier to $AppIdentifier"
fi

defaults read "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleResourceSpecification >/dev/null 2>&1 &&
  defaults delete "$OUTPUT/Payload/$AppBundleName/Info.plist" CFBundleResourceSpecification

if [[ -e "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" ]]; then
  security cms -D -i "$OUTPUT/Payload/$AppBundleName/embedded.mobileprovision" > "$TEMP/mobileprovision.plist"
  /usr/libexec/PlistBuddy -c "Print :Entitlements" "$TEMP/mobileprovision.plist" -x > "$EntitlementsPlist"
fi

cd "$OUTPUT/Payload/"
if [ -e "$EntitlementsPlist" ]; then
  echo "Signing with entitlements"
  echo "-------------------------"
  cat "$EntitlementsPlist"
  echo "-------------------------"
else
  echo "Signing without entitlements"
fi
for binext in $LIST_BINARY_EXTENSIONS; do
  for signfile in $(find "./$AppBundleName" -name "*.$binext" -type f); do
    if [ -e "$EntitlementsPlist" ]; then
      codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist" "$signfile"
    else
      codesign -vvv -fs "$2" --no-strict "$signfile"
    fi
  done
done

if [ -e "$EntitlementsPlist" ]; then
  codesign -vvv -fs "$2" --no-strict "--entitlements=$EntitlementsPlist"  "./$AppBundleName"
else
  codesign -vvv -fs "$2" --no-strict   "./$AppBundleName"
fi

if [[ -e "$CURRENT_PATH/$AppIdentifier-signed.ipa" ]]; then
  echo "Deleted existing output file"
  rm "$CURRENT_PATH/$AppIdentifier-signed.ipa"
fi
cd "$OUTPUT"
echo "Packaging..."
zip -qry "$CURRENT_PATH/$AppIdentifier-signed.ipa" "."
cd "$CURRENT_PATH"
echo "Doing some housekeeping..."
rm -rf "$TEMP"
echo "Done, the package is located at $CURRENT_PATH/$AppIdentifier-signed.ipa"