#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

info() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -m)" == "x86_64" ]] || die "This script must be run on the Intel Mac. Detected $(uname -m)."

command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild not found. Install Xcode 26.2+ and its command-line tools."
command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install Homebrew for this Intel Mac first."

info "Checking macOS and Xcode"
sw_vers
xcodebuild -version

info "Installing/refreshing native bridge dependencies"
brew install rnp botan json-c

info "Checking that Homebrew supplied Intel static libraries"
for f in \
  "$(brew --prefix)/opt/rnp/lib/librnp.a" \
  "$(brew --prefix)/opt/rnp/lib/libsexpp.a" \
  "$(brew --prefix)/opt/botan/lib/libbotan-3.a" \
  "$(brew --prefix)/opt/json-c/lib/libjson-c.a"
do
  [[ -f "$f" ]] || die "Missing static library: $f"
  echo "  $(lipo -archs "$f")  $f"
  [[ "$(lipo -archs "$f")" == *x86_64* ]] || die "Library is not x86_64: $f"
done

info "Rebuilding the Intel RNP bridge"
HOMEBREW_PREFIX="$(brew --prefix)" Vendor/RNPBridge/scripts/build-rnp-bridge.sh

info "Checking the Intel bridge"
EXPECTED_ARCHS="x86_64" scripts/check-bridge-architectures.sh

info "Building MacPGP"
scripts/build.sh clean
EXPECTED_ARCHS="x86_64" scripts/build.sh build -c Release

APP="DerivedData/Build/Products/Release/MacPGP.app"
[[ -d "$APP" ]] || die "Release app was not produced at $APP"

info "Checking the main executable"
lipo -archs "$APP/Contents/MacOS/MacPGP"

info "Checking embedded extensions"
find "$APP/Contents/PlugIns" -name '*.appex' -maxdepth 1 -print -exec sh -c '
  app="$1"
  name="$(basename "$app" .appex)"
  binary="$app/Contents/MacOS/$name"
  if [[ -f "$binary" ]]; then
    printf "  %s: %s\n" "$name" "$(lipo -archs "$binary")"
  fi
' _ {} \;

info "Intel build complete"
echo "App: $APP"
