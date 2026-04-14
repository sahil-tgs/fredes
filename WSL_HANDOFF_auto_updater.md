# WSL Claude — wire up in-app auto-updater for Fredes

Hey WSL Claude. Prime on the Windows side here. The user (sahil) wants Fredes to update itself in-place — no more re-extracting zips on every build. I'm handling the **installer** and **GitHub Release publishing** on Windows; you handle the **Flutter code integration** in `/home/lol/freegama/fredes`.

---

## ⚠️ Context: what I already committed (so you don't duplicate)

Commit: **`280a35d` — "tooling: Inno Setup installer + release pipeline script + WSL handoff"** (on `main`, already pushed). Diff it with `git show 280a35d`.

Files that commit added (DO NOT re-create these, they're ready):

| path | purpose |
|---|---|
| `scripts/release.sh` | One-command release pipeline. Run from this repo root: `bash scripts/release.sh 0.1.X`. It rsyncs source into `C:\fredes-build` (non-git Windows workdir), invokes Windows Flutter + Inno Setup, generates `appcast.xml` (WinSparkle feed), commits the pubspec bump, tags `vX.Y.Z`, pushes, and publishes a GitHub Release via `gh` (using the existing `sahil-tgs` auth in WSL). Don't edit unless it breaks. |
| `windows/installer/fredes.iss` | Inno Setup 6 script. Per-user install to `%LOCALAPPDATA%\Programs\Fredes\`, no UAC, Start Menu shortcut, in-place replaceable (so auto-update can overwrite). Version injected via `/DMyAppVersion=...`. |
| `.gitignore` | `dist/` added (release artifacts are local-only; they live on GitHub Releases). |
| `WSL_HANDOFF_auto_updater.md` | This file — self-referential, delete it after you're done. |

I built a test installer for v0.1.6 on Windows to verify the Inno script works — produced `Fredes-Setup-0.1.6-win-x64.exe` (11 MB). That artifact is NOT committed and NOT in a GitHub Release yet. v0.1.7 (the one YOU enable auto-update in) will be the first published release via the pipeline.

Environment I've already set up on the Windows side (no action needed from you):
- Flutter SDK at `C:\src\flutter`
- Visual Studio 2022 Community with C++ Desktop workload
- Inno Setup 6 at `C:\Users\sahil\AppData\Local\Programs\Inno Setup 6\ISCC.exe`
- Windows Developer Mode ON (needed for Flutter plugin symlinks)

Why I committed this tooling directly: user wants all release work in this WSL repo (single source of truth) and I'd been staging stuff in a throwaway Windows clone. Consolidating into one commit here was cleanest. Review `280a35d` — if you dislike any of it, amend and force-push before you start your work; I'll adapt.

---

## What YOU need to do

### 1. Add the `auto_updater` dependency

Edit `pubspec.yaml`, add under `dependencies:`:
```yaml
  auto_updater: ^1.0.0
```
Run `flutter pub get` to update `pubspec.lock`. If it doesn't resolve, fall back to latest compatible (try `0.2.0`). `auto_updater` is a WinSparkle wrapper (https://pub.dev/packages/auto_updater) — bundles native DLLs, no manual native code edits needed.

### 2. Wire it into app startup

In `lib/main.dart` (check `lib/app.dart` too), before `runApp`:

```dart
import 'dart:io' show Platform;
import 'package:auto_updater/auto_updater.dart';

Future<void> _initAutoUpdater() async {
  if (!Platform.isWindows) return;
  const feedURL =
      'https://github.com/sahil-tgs/fredes/releases/latest/download/appcast.xml';
  await autoUpdater.setFeedURL(feedURL);
  await autoUpdater.checkForUpdatesWithSilence(true); // silent startup check
  await autoUpdater.setScheduledCheckInterval(3600);  // recheck hourly
}
```

Fire-and-forget from `main()` — don't `await` before `runApp`.

### 3. Add a "Check for Updates…" menu item

The app has a native menu bar. Under Help (or App menu):
```dart
MenuItem(
  label: 'Check for Updates…',
  onPressed: () => autoUpdater.checkForUpdates(), // shows UI dialog
)
```

### 4. Commit + push + delete this handoff

Suggested commits:
1. `pubspec: add auto_updater dependency`
2. `app: integrate auto_updater with GitHub Releases appcast feed`
3. `chore: remove WSL handoff doc (work complete)` — `git rm WSL_HANDOFF_auto_updater.md`

Push to `main`, tell user "done". Prime runs:
```
bash scripts/release.sh 0.1.7
```
producing v0.1.7 as the first auto-update-aware release. v0.1.8 will be the first that a v0.1.7 install can pull automatically.

---

## Notes / gotchas

- Installer is **unsigned**. WinSparkle still auto-installs unsigned updates, but SmartScreen flashes a warning each time. Tolerable for now.
- `auto_updater` requires an installer-based install (not unzipped) for replace-and-relaunch to work. Inno Setup installer satisfies that.
- Don't hand-edit `windows/runner/` or native CMake — plugin tooling handles wiring.
- Dart SDK constraint `>=3.4.0 <4.0.0` is compatible with `auto_updater ^1.0.0`.
- Feed URL uses GitHub's `/releases/latest/download/<file>` redirect, so whichever release is marked `latest` auto-serves the appcast. No extra hosting.

If a resolve conflict, pin what works and note it in the commit message — Prime will adapt the pipeline.

— Prime
