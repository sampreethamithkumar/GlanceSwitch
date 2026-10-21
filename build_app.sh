#!/usr/bin/env bash
#
# Builds GlanceSwitch.app from the Swift package and ad-hoc code-signs it so
# macOS can attach Camera / Accessibility permissions to a stable identity.
#
set -euo pipefail
cd "$(dirname "$0")"

APP="GlanceSwitch.app"
BIN_NAME="GlanceSwitch"

echo "==> Compiling (release)…"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BIN_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

echo "==> Assembling ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp "${BIN_PATH}" "${APP}/Contents/MacOS/${BIN_NAME}"
cp "Info.plist" "${APP}/Contents/Info.plist"

echo "==> Code signing (ad-hoc)…"
codesign --force --deep --sign - "${APP}"

echo ""
echo "Done. Launch with:"
echo "    open ${APP}"
echo ""
echo "First run will ask for Camera, then Accessibility permission."
