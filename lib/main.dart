import 'dart:io' show Platform;

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'app.dart';

/// Wire up WinSparkle-based in-place auto-updates.
///
/// The feed URL points at the GitHub release asset that the Windows
/// packaging pipeline keeps up to date (appcast.xml attached to the
/// `latest` release of sahil-tgs/fredes). We fire a check on launch and
/// schedule a periodic re-check every hour.
///
/// Only runs on Windows release builds — the `auto_updater` plugin is a
/// Windows-only wrapper, so we gate the whole thing behind a platform
/// check to keep Linux/other runs clean.
Future<void> _initAutoUpdater() async {
  if (kIsWeb) return;
  if (!Platform.isWindows) return;
  const feedURL = 'https://github.com/sahil-tgs/fredes/releases/latest/download/appcast.xml';
  try {
    await autoUpdater.setFeedURL(feedURL);
    await autoUpdater.checkForUpdates();
    await autoUpdater.setScheduledCheckInterval(3600); // hourly
  } catch (_) {
    // Non-fatal — if the network's down or WinSparkle DLLs are missing we
    // still want the app to boot. A later manual "Check for Updates…" click
    // will surface any real error to the user.
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: don't block the first frame on a network call.
  _initAutoUpdater();
  runApp(const FredesApp());
}
