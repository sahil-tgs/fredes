#!/usr/bin/env bash
# Fredes release pipeline — runs from WSL in /home/lol/freegama/fredes.
# Commits, tags, releases all happen in this WSL repo (source of truth).
# Build happens in a throwaway Windows workdir (required for MSVC).
#
# Usage: bash scripts/release.sh <new_version>     e.g.  bash scripts/release.sh 0.1.7
# Requires (in WSL): git, gh (authenticated as sahil-tgs), rsync, python3.
# Requires (on Windows): Flutter at C:\src\flutter, Inno Setup 6 in %LOCALAPPDATA%\Programs.

set -euo pipefail

NEW_VERSION="${1:-}"
if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <new_version>  (e.g. 0.1.7)"; exit 1
fi

REPO_ROOT="/home/lol/freegama/fredes"
WIN_WORKDIR_WIN='C:\fredes-build'
WIN_WORKDIR_WSL="/mnt/c/fredes-build"
FLUTTER_WIN='C:\src\flutter\bin\flutter.bat'
ISCC_WIN='C:\Users\sahil\AppData\Local\Programs\Inno Setup 6\ISCC.exe'
REPO_SLUG="sahil-tgs/fredes"

cd "$REPO_ROOT"

PATCH="${NEW_VERSION##*.}"
BUILD_NUM=$((PATCH + 1))

echo "=== [1/8] pull latest ==="
git pull --ff-only

echo "=== [2/8] bump pubspec to ${NEW_VERSION}+${BUILD_NUM} ==="
python3 - "$NEW_VERSION" "$BUILD_NUM" <<'PY'
import re, sys, pathlib
v, b = sys.argv[1], sys.argv[2]
p = pathlib.Path("pubspec.yaml")
s = p.read_text(encoding="utf-8")
s2 = re.sub(r'(?m)^version:.*$', f'version: {v}+{b}', s, count=1)
p.write_text(s2, encoding="utf-8")
print("pubspec version set to", f"{v}+{b}")
PY

echo "=== [3/8] sync source to Windows workdir ${WIN_WORKDIR_WIN} ==="
mkdir -p "$WIN_WORKDIR_WSL"
rsync -a --delete \
  --exclude='.git/' --exclude='build/' --exclude='.dart_tool/' \
  --exclude='windows/flutter/ephemeral/' --exclude='linux/flutter/ephemeral/' \
  --exclude='.flutter-plugins' --exclude='.flutter-plugins-dependencies' \
  --exclude='dist/' \
  "$REPO_ROOT"/ "$WIN_WORKDIR_WSL"/

echo "=== [4/8] flutter build in Windows workdir ==="
cmd.exe /c "cd /d ${WIN_WORKDIR_WIN} && ${FLUTTER_WIN} pub get" | tail -3
cmd.exe /c "cd /d ${WIN_WORKDIR_WIN} && ${FLUTTER_WIN} build windows --release" | tail -5

echo "=== [5/8] compile installer ==="
powershell.exe -NoProfile -Command "& '${ISCC_WIN}' /DMyAppVersion=${NEW_VERSION} '${WIN_WORKDIR_WIN}\\windows\\installer\\fredes.iss'" | tail -5

INSTALLER_WSL="${WIN_WORKDIR_WSL}/dist/Fredes-Setup-${NEW_VERSION}-win-x64.exe"
test -f "$INSTALLER_WSL" || { echo "installer missing: $INSTALLER_WSL"; exit 1; }

# bring installer back into WSL repo dist/ (gitignored)
mkdir -p "$REPO_ROOT/dist"
cp "$INSTALLER_WSL" "$REPO_ROOT/dist/"
INSTALLER="$REPO_ROOT/dist/Fredes-Setup-${NEW_VERSION}-win-x64.exe"
ls -lh "$INSTALLER"

echo "=== [6/8] generate appcast.xml ==="
INSTALLER_SIZE=$(stat -c%s "$INSTALLER")
PUBDATE=$(date -Ru)
cat > "$REPO_ROOT/dist/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Fredes</title>
    <link>https://github.com/${REPO_SLUG}</link>
    <description>Fredes release feed</description>
    <language>en</language>
    <item>
      <title>Version ${NEW_VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <enclosure
        url="https://github.com/${REPO_SLUG}/releases/download/v${NEW_VERSION}/Fredes-Setup-${NEW_VERSION}-win-x64.exe"
        sparkle:version="${NEW_VERSION}"
        sparkle:shortVersionString="${NEW_VERSION}"
        length="${INSTALLER_SIZE}"
        type="application/octet-stream" />
      <sparkle:minimumSystemVersion>10.0.17763</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
EOF

echo "=== [7/8] commit + tag + push ==="
git add pubspec.yaml
git diff --cached --quiet || git commit -m "release: v${NEW_VERSION}"
git tag -f "v${NEW_VERSION}"
git push origin main --tags --force-with-lease

echo "=== [8/8] gh release ==="
gh release delete "v${NEW_VERSION}" --yes --cleanup-tag 2>/dev/null || true
# re-tag after cleanup-tag may have removed it
git tag -f "v${NEW_VERSION}"
git push origin "v${NEW_VERSION}" --force
gh release create "v${NEW_VERSION}" \
  "$INSTALLER" "$REPO_ROOT/dist/appcast.xml" \
  --repo "${REPO_SLUG}" \
  --title "Fredes v${NEW_VERSION}" \
  --notes "Auto-update release for v${NEW_VERSION}." \
  --latest

echo "=== done. release: https://github.com/${REPO_SLUG}/releases/tag/v${NEW_VERSION} ==="
