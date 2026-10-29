# MacVentoy (fork)

This repository is a **fork** of the original Ventoy project, adapted for macOS. It contains a SwiftUI front‑end and a Bash script that attempts to partition a USB drive and copy the Ventoy EFI files.

**Important:** This fork does **not** work out‑of‑the‑box. The EFI mounting steps are still problematic on recent macOS versions, and the installer fails with a mount error. Use at your own risk; it is provided for educational purposes only.

## What is included

- SwiftUI UI (`Sources/ContentView.swift`, `Sources/VentoyMacInstallerApp.swift`)
- Bash script (`Sources/Resources/createVentoy.sh`) that partitions the USB and copies EFI files.
- EFI boot files (`Sources/Resources/EFI/BOOT/*`).

## Building

```bash
swift build -c release
```

The built app can be found in `.build/release/MacVentoy`.

## Disclaimer

This code is provided as‑is and is not officially supported. Do not use it for production or critical data. The original Ventoy project can be found at https://github.com/ventoy/Ventoy.
