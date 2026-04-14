# WSL Claude — wire up in-app auto-updater for Fredes

Hey WSL Claude. Prime on the Windows side here. The user (sahil) wants Fredes to update itself in-place — no more re-extracting zips on every build. I'm handling the **installer** and **GitHub Release publishing** on Windows; you handle the **Flutter code integration** in `/home/lol/freegama/fredes`.

## What to do

### 1. Add the `auto_updater` dependency

Edit `pubspec.yaml`, add under `dependencies:`:
```yaml
  auto_updater: ^1.0.0
```
Then run `flutter pub get` so the lockfile updates. Commit with: `pubspec: add auto_updater`.

Docs: https://pub.dev/packages/auto_updater — WinSparkle wrapper, works out of the box on Windows release builds. No native code edits required.

### 2. Wire it into app startup

In `lib/main.dart` (or `lib/app.dart`, wherever `runApp` is called), before `runApp`:

```dart
import 'package:auto_updater/auto_updater.dart';

Future<void> _initAutoUpdater() async {
  const feedURL = 'https://github.com/sahil-tgs/fredes/releases/latest/download/appcast.xml';
  await autoUpdater.setFeedURL(feedURL);
  await autoUpdater.checkForUpdates();
  await autoUpdater.setScheduledCheckInterval(3600); // hourly
}
```

Call `_initAutoUpdater()` from `main()` (fire-and-forget; don't await before `runApp`). Guard with `if (!kIsWeb && Platform.isWindows)` to keep Linux build clean.

### 3. Add a "Check for Updates" menu item

In the app's native menu bar (wherever the File/Edit/View menus are built), under Help or App menu, add:
```dart
MenuItem(
  label: 'Check for Updates…',
  onPressed: () => autoUpdater.checkForUpdates(inBackground: false),
)
```
The `inBackground: false` flag shows a UI dialog even if no update is available (for explicit checks).

### 4. Commit + push

Two commits is fine:
1. `pubspec: add auto_updater`
2. `app: integrate auto_updater with GitHub Releases feed`

Push to `main`. I'll `git pull` on the Windows side and build the next release.

## What I'm doing on Windows

- Writing an Inno Setup `.iss` script to produce `Fredes-Setup-x.y.z.exe` (installs to `%LOCALAPPDATA%\Programs\Fredes`, Start Menu shortcut, per-user install so no UAC prompt).
- Setting up `gh release create` workflow: on each rebuild I tag `vX.Y.Z`, upload `Fredes-Setup-X.Y.Z.exe`, and regenerate `appcast.xml` attached to the `latest` release. The feed URL above points at the GitHub Release asset, so no separate hosting needed.
- `appcast.xml` is the WinSparkle feed format — I'll generate it from the release metadata.

## Notes / gotchas

- The installer is **unsigned** (no code-signing cert). WinSparkle on Windows can still auto-download+install unsigned updates, but SmartScreen will flash a warning each time. User knows; tolerable for now.
- `auto_updater` requires the app to be installed via a proper installer (not run from a zip) for the "replace and relaunch" step to work. The Inno Setup installer satisfies that.
- Don't hand-edit `windows/runner/` or native code — `auto_updater` pulls its Windows plugin automatically via the plugin tool symlinks.
- Dart SDK in this repo is `>=3.4.0 <4.0.0`, and `auto_updater ^1.0.0` requires Dart `>=3.0.0` — compatible.

## If you're blocked

- Version conflict on `auto_updater`: pin the latest compatible, e.g. `auto_updater: 0.2.0` (older, also works with WinSparkle). Prefer `^1.0.0` if it resolves.
- If the package fails to find WinSparkle DLLs at runtime: the plugin bundles them, so this only happens if symlink generation broke — verify Windows Developer Mode is still on (it is).
- If you need to test the check without publishing a release, mock the feed URL to a local file server. Not required before first publish.

Ping me (via user) when pushed. I'll build v0.1.7 as the first update-aware release, then v0.1.8+ will be the first that the v0.1.7 install can auto-pull.
