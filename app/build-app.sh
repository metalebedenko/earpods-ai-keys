#!/bin/sh
set -eu
app_source=$(CDPATH= cd -P "$(/usr/bin/dirname "$0")" && /bin/pwd)
configuration=${1:-release}
case "$configuration" in debug|release) ;; *) printf '%s\n' 'Usage: build-app.sh [debug|release]' >&2; exit 2 ;; esac
/usr/bin/xcrun swift build --package-path "$app_source" --configuration "$configuration"
products=$(/usr/bin/xcrun swift build --package-path "$app_source" --configuration "$configuration" --show-bin-path)
stamp=$(/bin/date -u '+%Y%m%dT%H%M%SZ')
output="$app_source/dist/$stamp-$$"
bundle="$output/EarPods AI Keys.app"
/bin/mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Helpers" "$bundle/Contents/Resources"
/bin/cp "$app_source/Info.plist" "$bundle/Contents/Info.plist"
/bin/cp "$products/EarPodsAIKeys" "$bundle/Contents/MacOS/EarPodsAIKeys"
/bin/cp "$products/EarPodsUninstallHelper" "$bundle/Contents/Helpers/EarPodsUninstallHelper"
/bin/cp "$app_source/../LICENSE" "$bundle/Contents/Resources/LICENSE"
/bin/cp "$app_source/Resources/AppIcon.icns" "$bundle/Contents/Resources/AppIcon.icns"
/bin/cp "$app_source/Resources/MenuIconTemplate.png" "$bundle/Contents/Resources/MenuIconTemplate.png"
/bin/cp "$app_source/Resources/MenuIconTemplate@2x.png" "$bundle/Contents/Resources/MenuIconTemplate@2x.png"
/bin/chmod 755 "$bundle/Contents/MacOS/EarPodsAIKeys" "$bundle/Contents/Helpers/EarPodsUninstallHelper"
# SwiftPM release products can contain build-machine paths in debug symbols.
# Strip those records before signing a distributable bundle.
if [ "$configuration" = release ]; then
    /usr/bin/strip -S "$bundle/Contents/MacOS/EarPodsAIKeys"
    /usr/bin/strip -S "$bundle/Contents/Helpers/EarPodsUninstallHelper"
fi
/usr/bin/plutil -lint "$bundle/Contents/Info.plist"
/usr/bin/codesign --force --sign - --identifier local.earpods-ai-keys.app.uninstall "$bundle/Contents/Helpers/EarPodsUninstallHelper"
/usr/bin/codesign --force --sign - --identifier local.earpods-ai-keys.app "$bundle"
/usr/bin/codesign --verify --strict --deep "$bundle"
printf '\n%s\n' "$bundle"
