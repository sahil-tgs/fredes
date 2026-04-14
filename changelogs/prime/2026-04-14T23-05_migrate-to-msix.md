# 2026-04-14T23:05 — Migrate from Inno Setup + auto_updater to MSIX + .appinstaller

## Why

The `auto_updater` Flutter plugin + WinSparkle combination is broken and abandoned:

- Plugin's `setFeedURL` calls `win_sparkle_init()` on every call (should be called once at startup), producing race conditions and the "Update Error! An error occurred in retrieving update information" dialog on launch.
- Plugin never calls `win_sparkle_set_app_details()` or `win_sparkle_set_app_build_version()` — WinSparkle's implicit version detection is unreliable.
- Even after stripping `+N` from Runner.rc so WinSparkle reads a clean version string, it still reports "up to date" when feed clearly serves a newer version (tested with `sparkle:version="1.0.0"` — no prompt).
- 6+ open leanflutter/auto_updater issues (#19, #42, #50, #54, #61, #65, #80) about this exact failure mode. Maintainer inactive since early 2024.

Also: user hated the Inno Setup wizard UX.

**MSIX solves both problems at once:**
- Clean single-click native Windows install UX
- **Windows itself handles auto-update** via the `.appinstaller` manifest — no plugin, no Dart code, no WinSparkle
- Same package can later be submitted to Microsoft Store unchanged
- Built-in sandboxing, clean uninstall, no Program Files pollution

## What changes

### Removed
- `auto_updater` dependency from `pubspec.yaml`
- `package:auto_updater/auto_updater.dart` imports
- `_initAutoUpdater()` in `lib/main.dart`
- `_checkForUpdates()` handler and "Check for Updates…" menu item in `lib/app.dart`
- `windows/installer/fredes.iss` (Inno Setup script)
- Inno-specific logic in `scripts/release.sh`

### Added
- `msix` dev_dependency (https://pub.dev/packages/msix)
- `msix_config:` block in `pubspec.yaml` — publisher, display name, icons, capabilities, **publish URL for auto-update**
- `windows/packaging/Fredes.appinstaller` template — AppInstaller XML Windows polls for updates
- Self-signed code-signing cert at `C:\fredes-signing\Fredes.pfx` on Windows side (not committed; see changelog §Cert)
- `scripts/release.sh` rewritten to:
  1. Bump pubspec
  2. Run `flutter build windows --release`
  3. Run `dart run msix:create` → outputs `build/windows/x64/runner/Release/fredes.msix`
  4. Generate versioned `.appinstaller` XML
  5. Tag, push, create GitHub Release with `fredes.msix` + `Fredes.appinstaller` attached
- `changelogs/prime/2026-04-14T23-05_migrate-to-msix.md` (this file)

### Kept
- `windows/runner/Runner.rc` fix (clean `MAJOR.MINOR.PATCH` in StringFileInfo) — still useful since MSIX reads versions from the manifest, not StringFileInfo, but doesn't hurt.
- Pubspec `version: X.Y.Z+N` convention.

## Cert (user-installed, not committed)

Windows MSIX requires code signing. We generate a **self-signed cert** on the Windows side (outside the repo):
- Location: `C:\fredes-signing\Fredes.pfx` (password-protected; password stored in a .env file that `release.sh` reads, NOT committed).
- Subject: `CN=sahil-tgs, O=Fredes, C=IN` (adjust as needed).
- User imports the public `.cer` into `LocalMachine\TrustedPeople` once — after that all MSIX installs and auto-updates work silently. Documented in the new README section.

For Microsoft Store distribution later, the Store publishes with its own cert — our self-signed cert becomes irrelevant.

## Auto-update flow (native Windows)

1. User installs `Fredes_0.1.12_x64.msix` once (or via Store later).
2. MSIX manifest's `<PublisherDisplayName>` + `<AppInstaller Uri>` registers the update source.
3. Windows polls the `.appinstaller` URL on its own schedule (typically on launch, once per hour).
4. When the manifest shows a newer version, Windows downloads + installs silently in background. User sees a Windows toast "Fredes has been updated".
5. No "check for updates" button needed; no user action required.

## Risks

- **First-time cert trust friction**: user must run a one-time PowerShell command to import the self-signed cert. Installation fails silently otherwise (`App package signature verification failed`). README will document clearly.
- **MSIX sandboxing**: Fredes writes `.freegma` files to user-chosen paths via file picker — MSIX's broker handles this fine. No known issue.
- **`.appinstaller` served over HTTP**: GitHub Releases URLs are HTTPS, required by MSIX auto-update. Good.
- **MSIX minimum OS**: Windows 10 1809 (build 17763). Already our floor. Unchanged.
- **App still loads existing `.freegma` files**: MSIX install preserves `%LOCALAPPDATA%` — no data loss migrating from Inno install to MSIX install (though both co-exist until user uninstalls the Inno one manually).

## Migration path for existing Inno install

The Inno Setup install (`C:\Users\sahil\AppData\Local\Programs\Fredes\`) and MSIX install are distinct — different AppIds, different locations. User should:
1. Uninstall Fredes via Windows Settings → Apps (removes Inno install).
2. Install `Fredes_0.1.12_x64.msix` (the new MSIX build).
3. Going forward, Windows handles all updates automatically.

Future installs for other users: distribute just the `.msix` + cert `.cer` + one-line PowerShell to import cert.

## Status

Uncommitted at time of writing. I'll execute the edits + build the first MSIX + release v0.1.12 in the same session that produces this changelog. Will update this file with final commit hash when committed.

If you review the working tree before my next release:

```
git status
git diff pubspec.yaml lib/main.dart lib/app.dart scripts/release.sh
```

Expect removals of the auto_updater wiring, additions of the msix_config block, and a rewritten release.sh. If anything looks off, amend before I tag v0.1.12.

— Prime
