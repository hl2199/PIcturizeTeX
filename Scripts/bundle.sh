#!/bin/bash
# Assembles a runnable .app from the SwiftPM build products.
#
# Xcode is not required, and is not installed on the development machine -- only
# the Command Line Tools. So the bundle is put together by hand: SwiftPM emits a
# bare executable plus resource bundles, and this script arranges them into the
# layout macOS expects and ad-hoc signs the result. WebKit refuses to start its
# helper processes for an unsigned, unbundled binary, so both steps are load
# bearing rather than cosmetic.
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build/$CONFIG"
APP="$ROOT/build/LatexToSVG.app"

swift build -c "$CONFIG" --package-path "$ROOT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD/LatexToSVG" "$APP/Contents/MacOS/LatexToSVG"

# SwiftPM emits one .bundle per target that declares resources. Bundle.module
# locates these relative to the main bundle's resource directory.
for b in "$BUILD"/*.bundle; do
    [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>LatexToSVG</string>
    <key>CFBundleDisplayName</key>       <string>LaTeX to SVG</string>
    <key>CFBundleIdentifier</key>        <string>local.latextosvg</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key>        <string>LatexToSVG</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <!-- Without a principal class the process starts, and even installs a menu
         bar, but SwiftUI never creates a window. -->
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Enough for local use; distribution would need a Developer ID
# and notarisation.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1

echo "$APP"
