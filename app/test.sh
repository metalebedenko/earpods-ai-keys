#!/bin/sh
set -eu
app_source=$(CDPATH= cd -P "$(/usr/bin/dirname "$0")" && /bin/pwd)
compiler=$(/usr/bin/xcrun --find swiftc)
toolchain=$(CDPATH= cd -P "$(/usr/bin/dirname "$compiler")/.." && /bin/pwd)
# Some CLT SwiftPM builds do not auto-load the bundled Swift Testing macro.
# Use only the toolchain's own plugin; no dependencies or global changes.
for candidate in "$toolchain/lib/swift/host/plugins/testing/libTestingMacros.dylib" "$toolchain/lib/swift/host/plugins/libTestingMacros.dylib"; do
    if [ -f "$candidate" ]; then
        exec /usr/bin/xcrun swift test --package-path "$app_source" --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$candidate"
    fi
done
exec /usr/bin/xcrun swift test --package-path "$app_source" --disable-xctest
