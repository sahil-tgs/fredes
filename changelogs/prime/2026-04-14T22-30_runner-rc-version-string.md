# 2026-04-14T22:30 — Strip `+N` from exe StringFileInfo version

## Context

WSL Claude wired `auto_updater` (WinSparkle 0.8.1 underneath) to the GitHub Releases appcast feed. Works for the network fetch, but every `Help → Check for Updates…` said "You're up to date!" even when the feed served a drastically higher version (tested `9999.0.0` and `0.1.999999` — still reported up-to-date).

## Root cause

Two-part:

1. **`auto_updater_windows` 1.0.0 never calls `win_sparkle_set_app_details()` or `win_sparkle_set_app_build_version()`.** So WinSparkle falls back to reading the app's `VS_VERSION_INFO` block — specifically the `StringFileInfo.FileVersion` / `ProductVersion` strings.
2. **Flutter's default `windows/runner/Runner.rc` stamps the full pubspec `version:` string** (including the `+N` build-number suffix) into those fields. Verified on the installed exe: PowerShell `(Get-Item fredes.exe).VersionInfo.FileVersion` = `"0.1.9+10"`.
3. WinSparkle 0.8.1's comparator does not like the `+` — it bails / returns "not newer" regardless of what the feed says.

Upstream fix in the plugin would be ideal but it's not coming (see leanflutter/auto_updater issues #77, #79, #80, #82, #83 — project appears stalled). Fixing on our side by never writing `+N` into StringFileInfo is simpler.

## Change

**File:** `windows/runner/Runner.rc` (lines 69–73 replaced with a 10-line block).

Before:
```c
#if defined(FLUTTER_VERSION)
#define VERSION_AS_STRING FLUTTER_VERSION
#else
#define VERSION_AS_STRING "1.0.0"
#endif
```

After: build `VERSION_AS_STRING` from `MAJOR.MINOR.PATCH` only (stringified via two-level macro trick, standard C preprocessor idiom). `FLUTTER_VERSION_BUILD` is still used for the numeric `FILEVERSION` quad (`0,1,9,10`) — that's a separate field; only the human-readable strings change.

Result: `FileVersion` / `ProductVersion` will read `"0.1.9"` instead of `"0.1.9+10"`. WinSparkle can now compare cleanly.

**File:** `scripts/release.sh`

Changed appcast generation: `sparkle:version="${NEW_VERSION}+${BUILD_NUM}"` → `sparkle:version="${NEW_VERSION}"`. Both sides are now pure `X.Y.Z`. `sparkle:shortVersionString` was already `${NEW_VERSION}` — unchanged.

## Risks

- None I can see for pubspec `version:` semantics elsewhere. The pubspec still uses `X.Y.Z+N`. `FLUTTER_VERSION_BUILD` still feeds the numeric quad. Only the displayed strings change.
- If anything downstream (analytics, crash reports) parses `FileVersion` expecting `+N`, it'll be surprised. None in this repo that I can see.
- `pubspec.lock` unchanged.

## Status

**Uncommitted.** Both edits sit in the working tree — review the diff before my next release call.

```
git diff windows/runner/Runner.rc scripts/release.sh
```

If you're good with it, I'll run `bash scripts/release.sh 0.1.10` which will bump pubspec, build with the new Runner.rc (so exe gets clean `0.1.9`-style version string), compile installer, push tag, publish release. Installed v0.1.9+10 should then correctly detect v0.1.10 — and since the new v0.1.10 exe will ALSO have clean version strings, all future auto-update checks will work.

— Prime
