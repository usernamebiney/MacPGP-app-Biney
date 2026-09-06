#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
BRIDGE_ROOT="$ROOT/Vendor/RNPBridge"
BUILD_ROOT="$BRIDGE_ROOT/build/x86_64"
HEADERS_ROOT="$BRIDGE_ROOT/headers"
XCFRAMEWORK_PATH="$BRIDGE_ROOT/RNPBridge.xcframework"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-${BREW_PREFIX:-}}"
MAX_MINOS="${RNPBRIDGE_MAX_MINOS:-26.2}"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "::error::This Intel build must run on an x86_64 Mac." >&2
  exit 1
fi

if [[ -z "$HOMEBREW_PREFIX" ]]; then
  HOMEBREW_PREFIX="$(brew --prefix)"
fi

require_file() {
  [[ -f "$1" ]] || {
    echo "::error::Required file not found: $1" >&2
    exit 1
  }
}

check_arch() {
  local actual
  actual="$(lipo -archs "$1" 2>/dev/null || true)"
  [[ "$actual" == *"$2"* ]] || {
    echo "::error::$1 does not contain $2 (reported: ${actual:-none})" >&2
    exit 1
  }
}

RNP_LIB="$HOMEBREW_PREFIX/opt/rnp/lib/librnp.a"
SEXPP_LIB="$HOMEBREW_PREFIX/opt/rnp/lib/libsexpp.a"
BOTAN_LIB="$HOMEBREW_PREFIX/opt/botan/lib/libbotan-3.a"
JSONC_LIB="$HOMEBREW_PREFIX/opt/json-c/lib/libjson-c.a"
RNP_HEADERS="$HOMEBREW_PREFIX/opt/rnp/include/rnp"

for f in "$RNP_LIB" "$SEXPP_LIB" "$BOTAN_LIB" "$JSONC_LIB"; do
  require_file "$f"
  check_arch "$f" x86_64
done

[[ -d "$RNP_HEADERS" ]] || {
  echo "::error::RNP headers not found: $RNP_HEADERS" >&2
  exit 1
}

mkdir -p "$BUILD_ROOT"
rm -rf "$HEADERS_ROOT/rnp"
mkdir -p "$HEADERS_ROOT/rnp"
cp "$RNP_HEADERS/"*.h "$HEADERS_ROOT/rnp/"

rm -f "$BUILD_ROOT/libRNPBridge.a"

echo "==> Combining Intel RNP libraries"

libtool -static \
  -o "$BUILD_ROOT/libRNPBridge.a" \
  "$RNP_LIB" \
  "$SEXPP_LIB" \
  "$BOTAN_LIB" \
  "$JSONC_LIB"

check_arch "$BUILD_ROOT/libRNPBridge.a" x86_64

echo "==> Creating Intel-only RNPBridge.xcframework"

TEMP_XCFRAMEWORK="$BRIDGE_ROOT/RNPBridge.xcframework.tmp.xcframework"
rm -rf "$TEMP_XCFRAMEWORK"

xcodebuild -create-xcframework \
  -library "$BUILD_ROOT/libRNPBridge.a" \
  -headers "$HEADERS_ROOT" \
  -output "$TEMP_XCFRAMEWORK"

EXPECTED_ARCHS="x86_64" "$ROOT/scripts/check-bridge-architectures.sh" \
  "$TEMP_XCFRAMEWORK" \
  EXPECTED_ARCHS="x86_64"

"$BRIDGE_ROOT/scripts/check-rnp-bridge-minos.sh" \
  "$MAX_MINOS" \
  "$TEMP_XCFRAMEWORK/macos-x86_64/libRNPBridge.a"

rm -rf "$XCFRAMEWORK_PATH"
mv "$TEMP_XCFRAMEWORK" "$XCFRAMEWORK_PATH"

echo
echo "Intel-only RNPBridge.xcframework created successfully."
echo

EXPECTED_ARCHS="x86_64" "$ROOT/scripts/check-bridge-architectures.sh" \
  "$XCFRAMEWORK_PATH" \
  EXPECTED_ARCHS="x86_64"
