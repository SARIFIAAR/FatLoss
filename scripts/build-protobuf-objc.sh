#!/bin/bash
# Build the Objective-C Protobuf runtime (GPBMessage, …) as a DEVICE-ONLY static
# xcframework for the VB9 (BLEMidAutumn) integration.
#
# Why this exists: BLEMidAutumn.framework (IWOWN/Zeroner "Mid-Autumn" SDK) is a
# static framework whose ONLY external link dependency is the Obj-C Protobuf
# runtime. HUMANS is a Swift Package Manager app with no CocoaPods, so we vendor
# that one runtime as a prebuilt static .xcframework and link it device-only
# (alongside BLEMidAutumn) via [sdk=iphoneos*] build settings. Keeps the
# simulator build (screenshot harness) clean — neither binary is seen on sim.
#
# Source: the Protobuf pod shipped inside the VB9 SDK demo (BSD-licensed).
# Output: Vendor/BLEMidAutumn/Protobuf.xcframework  (git-ignored)
#
# Run from the repo root:  bash scripts/build-protobuf-objc.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HOME/Downloads/VB9SDK/b9_ble_demo_ios/AutumnTest/Pods/Protobuf/objectivec"
OUT="$REPO/Vendor/BLEMidAutumn"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ ! -d "$SRC" ]; then
  echo "ERROR: Protobuf source not found at $SRC" >&2
  echo "       (expected the extracted VB9 SDK demo Pods)." >&2
  exit 1
fi

echo "==> Compiling Obj-C Protobuf runtime for arm64-iphoneos (static lib)"
SDK_PATH="$(xcrun --sdk iphoneos --show-sdk-path)"
OBJS="$WORK/obj"; mkdir -p "$OBJS"

# Compile every runtime .m (the *.pbobjc.m well-known-type files + core runtime).
# ARC on; GPB headers import siblings by name, so -I the source dir.
for m in "$SRC"/*.m; do
  base="$(basename "$m" .m)"
  # Google's Obj-C Protobuf runtime is manual-reference-counted (MRC), not ARC.
  xcrun --sdk iphoneos clang -c "$m" \
    -arch arm64 -isysroot "$SDK_PATH" -miphoneos-version-min=15.0 \
    -fno-objc-arc -fmodules -I"$SRC" \
    -o "$OBJS/$base.o"
done

echo "==> Archiving libProtobuf.a (device static lib)"
# Our Swift code never imports GPB*; only the BLEMidAutumn static framework references these symbols,
# resolved at final link. So we need the .a for symbols only — no headers shipped into the app.
xcrun --sdk iphoneos libtool -static -o "$OUT/libProtobuf.a" "$OBJS"/*.o

echo "==> Done: $OUT/libProtobuf.a"
lipo -info "$OUT/libProtobuf.a" 2>/dev/null || true
