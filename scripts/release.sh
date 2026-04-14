#!/usr/bin/env bash
# Fredes release pipeline (MSIX edition) — runs from WSL in /home/lol/freegama/fredes.
# Commits, tags, releases all happen in this WSL repo (source of truth).
# Build + MSIX packaging happens on the Windows side (required for MSVC + makeappx).
#
# Usage: bash scripts/release.sh <new_version>     e.g.  bash scripts/release.sh 0.1.12
# Requires (in WSL): git, gh (authenticated as sahil-tgs), rsync, python3.
# Requires (on Windows): Flutter at C:\src\flutter, Fredes signing cert at
#   C:\fredes-signing\Fredes.pfx, cert installed to LocalMachine\TrustedPeople
#   (one-time admin step — see C:\fredes-signing\install-cert-AS-ADMIN.ps1).

set -euo pipefail

NEW_VERSION="${1:-}"
if [[ -z "$NEW_VERSION" ]]; then
  echo "Usage: $0 <new_version>  (e.g. 0.1.12)"; exit 1
fi

REPO_ROOT="/home/lol/freegama/fredes"
WIN_WORKDIR_WIN='C:\fredes-build'
WIN_WORKDIR_WSL="/mnt/c/fredes-build"
FLUTTER_WIN='C:\src\flutter\bin\flutter.bat'
DART_WIN='C:\src\flutter\bin\dart.bat'
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

echo "=== [4/8] flutter build ==="
cmd.exe /c "cd /d ${WIN_WORKDIR_WIN} && ${FLUTTER_WIN} pub get" | tail -3
cmd.exe /c "cd /d ${WIN_WORKDIR_WIN} && ${FLUTTER_WIN} build windows --release" | tail -5

echo "=== [5/8] msix package + appinstaller ==="
# msix:create reads msix_config from pubspec.yaml, signs with C:\fredes-signing\Fredes.pfx,
# and emits fredes.msix to build/windows/x64/runner/Release/.
cmd.exe /c "cd /d ${WIN_WORKDIR_WIN} && ${DART_WIN} run msix:create --build-windows false" | tail -5

MSIX_WSL="${WIN_WORKDIR_WSL}/build/windows/x64/runner/Release/fredes.msix"
test -f "$MSIX_WSL" || { echo "msix missing: $MSIX_WSL"; exit 1; }

mkdir -p "$REPO_ROOT/dist"
MSIX_OUT="$REPO_ROOT/dist/fredes_${NEW_VERSION}.0_x64.msix"
cp "$MSIX_WSL" "$MSIX_OUT"

# Hand-generate Fredes.appinstaller with GitHub-hosted URIs.
# Windows polls MainPackage Uri at HoursBetweenUpdateChecks cadence; when Version
# here exceeds the installed version, it auto-downloads + installs the .msix.
APPINSTALLER_URL="https://github.com/${REPO_SLUG}/releases/latest/download/Fredes.appinstaller"
MSIX_URL="https://github.com/${REPO_SLUG}/releases/download/v${NEW_VERSION}/fredes_${NEW_VERSION}.0_x64.msix"
cat > "$REPO_ROOT/dist/Fredes.appinstaller" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
    Uri="${APPINSTALLER_URL}" Version="${NEW_VERSION}.0">
  <MainPackage Name="com.sahiltgs.fredes" Version="${NEW_VERSION}.0"
    Publisher="CN=sahil-tgs, O=Fredes, C=IN"
    Uri="${MSIX_URL}"
    ProcessorArchitecture="x64" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="1" UpdateBlocksActivation="false" ShowPrompt="false" />
    <AutomaticBackgroundTask />
  </UpdateSettings>
</AppInstaller>
EOF
ls -lh "$REPO_ROOT/dist/"

echo "=== [6/8] commit + tag + push ==="
git add pubspec.yaml
git diff --cached --quiet || git commit -m "release: v${NEW_VERSION}"
git tag -f "v${NEW_VERSION}"
git push origin main --tags --force-with-lease

echo "=== [7/8] gh release ==="
gh release delete "v${NEW_VERSION}" --yes --cleanup-tag 2>/dev/null || true
git tag -f "v${NEW_VERSION}"
git push origin "v${NEW_VERSION}" --force
gh release create "v${NEW_VERSION}" \
  "$MSIX_OUT" \
  "$REPO_ROOT/dist/Fredes.appinstaller" \
  --repo "${REPO_SLUG}" \
  --title "Fredes v${NEW_VERSION}" \
  --notes "MSIX release v${NEW_VERSION}. Windows auto-updates via Fredes.appinstaller." \
  --latest

echo "=== [8/8] done ==="
echo "Release: https://github.com/${REPO_SLUG}/releases/tag/v${NEW_VERSION}"
echo "AppInstaller URL (Windows polls this): ${APPINSTALLER_URL}"
