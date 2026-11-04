# Local Flutter SDK

This checkout uses a project-local Flutter 3.38.3 SDK at `tools/flutter`.
The SDK directory is intentionally ignored by Git because it includes the
Flutter source checkout, Git metadata, Dart SDK, and platform artifacts.

The Android project points to this SDK through the local-only
`apps/shop_pos/android/local.properties`. VS Code points to it through the
local-only `.vscode/settings.json` setting `dart.flutterSdkPath`.

From the repository root, run the Dart binary through:

```powershell
.\scripts\dart-local.ps1 --version
```

To analyze the POS app, run this from `apps/shop_pos`:

```powershell
..\..\scripts\dart-local.ps1 analyze lib
```

On a fresh checkout, copy a compatible Flutter SDK into `tools/flutter` and
regenerate its `bin/cache` before using these local paths.
