#!/bin/bash
LIST_BINARY_EXTENSIONS="dylib so 0 vis pvr"
TEMP="$(mktemp -d)"
CURRENT_PATH="$(pwd)"
cd "$TEMP"
if [[ "$#" -lt 3 ]]; then
  echo "Usage: "$(basename "$0")" (file name/url) (Developer Identity) (.mobileprovision file) [(new app id)]"
  exit
fi

Extension="${1##*.}"

echo "$Extension"
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
    mv Applications/ Payload/
    ;;
  ipa )
    unzip "app.$Extension"
    ;;
  app )
    mkdir Payload
    cp -r "$1" "Payload"
    ;;
  *) echo "Filetype not supported"; exit
esac

AppBundleName="$(ls ./Payload/ | sort -n | head -1)"
echo "AppBundleName - $AppBundleName"

EntitlementsPlist="$TEMP/entitlements.plist"

rm -rf "Payload/$AppBundleName/_CodeSignature/"

AppIdentifier="$(defaults read $TEMP/Payload/$AppBundleName/Info.plist CFBundleIdentifier)"
CFBundleName="$(defaults read $TEMP/Payload/$AppBundleName/Info.plist CFBundleName)"
CFBundleExecutable="$(defaults read $TEMP/Payload/$AppBundleName/Info.plist CFBundleExecutable)"

echo "CFBundleName - $CFBundleName"
echo "AppIdentifier - $AppIdentifier"
#if [ -n "$3" ]; then
	cp "$3" "Payload/$AppBundleName/embedded.mobileprovision"
    MobileProvisionIdentifier="$(egrep -a -A 2 application-identifier $TEMP/Payload/$AppBundleName/embedded.mobileprovision | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //')"
    TeamIdentifier="$(egrep -a -A 2 com.apple.developer.team-identifier $TEMP/Payload/$AppBundleName/embedded.mobileprovision | grep string | sed -e 's/<string>//' -e 's/<\/string>//' -e 's/ //' | xargs)"
    
    echo "MobileProvisionIdentifier - $MobileProvisionIdentifier"
    MobileProvisionIdentifier=${MobileProvisionIdentifier#*.}
    echo "MobileProvisionIdentifier - $MobileProvisionIdentifier"
    if [ "$MobileProvisionIdentifier" != "*" ]; then
        defaults write "$TEMP/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$MobileProvisionIdentifier"
        AppIdentifier="$MobileProvisionIdentifier"
        echo "New App Identifier - $AppIdentifier"
    fi
#fi

if [ -n "$4" ]
  then
    defaults write "$TEMP/Payload/$AppBundleName/Info.plist" CFBundleIdentifier "$4"
    AppIdentifier="$4"
fi

touch "$EntitlementsPlist"
defaults write "$EntitlementsPlist" "application-identifier" "$TeamIdentifier.$AppIdentifier"
defaults write "$EntitlementsPlist" "com.apple.developer.team-identifier" "$TeamIdentifier"
defaults write "$EntitlementsPlist" "get-task-allow" -bool TRUE
defaults write "$EntitlementsPlist" "keychain-access-groups" -array-add "$TeamIdentifier.*"

for binext in $LIST_BINARY_EXTENSIONS
do
  codesign -fvvv -s "$2" -i "$AppIdentifier" --entitlements "$EntitlementsPlist" `find "$TEMP/Payload/$AppBundleName/" -name "*.$binext" -type f`
done
codesign -fvvv -s "$2" -i "$AppIdentifier" --entitlements "$EntitlementsPlist" "$TEMP/Payload/$AppBundleName/$CFBundleExecutable" "$TEMP/Payload/$AppBundleName"



rm "$CURRENT_PATH/$AppIdentifier-signed.ipa"
zip -r "$CURRENT_PATH/$AppIdentifier-signed.ipa" Payload/
echo $CURRENT_PATH
cd "$CURRENT_PATH"
rm -rf "$TEMP"