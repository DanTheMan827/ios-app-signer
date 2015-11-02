Usage
======
app-sign.sh (file name/url) (Developer Identity) [(.mobileprovision file)] [(new app id)]

You can ommit the mobileprovision file if you just want to re-sign the app.
It is also possible to specify a new app id, this is only possible if you have a wildcard .mobileprovision file.
The application id will be changed to the mobileprovision file if it is not a wildcard.
It is also possible to change the app id without specifying a mobileprovision file, just use two quotes ""

Supported filetypes are .deb, .ipa, and app bundles