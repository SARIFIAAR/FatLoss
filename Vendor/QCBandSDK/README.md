# QRing SDK (QCBandSDK) — drop-in location

The Vivistar **QCBandSDK.framework** (QRing platform — VY26/VY28C rings) is a vendor binary and is
**intentionally NOT committed** to this public repo (see `.gitignore`). It is **arm64 device-only**
(no simulator slice) and linked into the **device build only** via `[sdk=iphoneos*]` settings.

## To activate the QRing integration on a real device
1. Drop the framework here: `Vendor/QCBandSDK/QCBandSDK.framework`
   (from the SDK zip: `QCBandSDKDemo/QCBandSDK.framework`).
2. It's already wired in the project (FRAMEWORK_SEARCH_PATHS + `-ObjC -framework QCBandSDK`, device-only).
   **No extra dependencies** — the framework is self-contained (unlike the VB9's Protobuf need).
3. Build to a device. `QRingManager.isAvailable` flips true (`#if canImport(QCBandSDK)`) and `QRingBridge`
   takes over. Simulator builds exclude it and keep compiling.

Knowledge base + API map: `docs/qring-integration.md`.
