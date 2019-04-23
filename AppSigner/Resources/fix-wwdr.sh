#!/bin/bash
security find-certificate -c "Apple Worldwide Developer Relations Certification Authority" -a -Z | awk '/SHA-1/{system("security delete-certificate -Z "$NF)}'
TEMP="$(mktemp -d -t com.DanTheMan827.WWDR-Fix)"
curl "https://developer.apple.com/certificationauthority/AppleWWDRCA.cer" > "$TEMP/AppleWWDRCA.cer"
security add-certificates "$TEMP/AppleWWDRCA.cer"
rm "$TEMP/AppleWWDRCA.cer"