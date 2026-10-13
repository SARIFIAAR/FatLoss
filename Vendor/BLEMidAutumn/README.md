# VB9 wristband SDK — drop-in location

The IWOWN / Zeroner **BLEMidAutumn.framework** (v6.6.6) is a commercial, closed-source binary and is
**intentionally NOT committed** to this public repo (see `.gitignore`). It is also **arm64 device-only
— no simulator slice** — so it is linked into the **device build only**.

## To activate the VB9 integration on a real device

1. Drop the vendor framework here: `Vendor/BLEMidAutumn/BLEMidAutumn.framework`
   (from the supplier SDK: `b9_ble_demo_ios/AutumnTest/blelib/BLEMidAutumn.framework`).
2. In Xcode, add it to the **FatLossCoach** target → General → *Frameworks, Libraries & Embedded Content*
   → **Embed & Sign**. Set the destination filter so it only links for **iOS device**, not the simulator.
3. Add the CocoaPods dependencies the framework needs (or vendor them): `Protobuf` (3.21.x),
   `iOSDFULibrary` (4.15.x), `ZIPFoundation`, `Masonry`, `IVBaseKit`.
4. Build **to a device**. `VB9Manager.isAvailable` flips to `true` (via `#if canImport(BLEMidAutumn)`),
   and the `bridge*` methods in `VB9Manager.swift` take over from the simulator stub. Finish wiring the
   delegate callbacks there against the physical band (see `docs/vb9-integration.md`).

Until then the app compiles and runs normally on the simulator; the band features are inert unless you
pass `-vb9Sim 1` (demo data for UI work).
