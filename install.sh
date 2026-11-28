#!/usr/bin/env sh
# Sovereign Zero-Python Installer for `vedit` (verifiable-editorial-skills)
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gke0op/verifiable-editorial-skills/main/install.sh | sh
#   VEDIT_VERSION=v0.7.0 VEDIT_INSTALL_DIR="$HOME/.local/bin" sh install.sh
set -eu

REPO="${VEDIT_REPO:-gke0op/verifiable-editorial-skills}"
INSTALL_DIR="${VEDIT_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${VEDIT_VERSION:-latest}"

for cmd in curl tar install awk tr grep; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[vedit-install] Missing required tool: $cmd" >&2
    exit 1
  fi
done

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
  *)
    echo "[vedit-install] Unsupported OS: $OS_RAW" >&2
    exit 1
    ;;
esac

case "$ARCH_RAW" in
  arm64|aarch64) ARCH="aarch64" ;;
  x86_64|amd64)  ARCH="x86_64" ;;
  *)
    echo "[vedit-install] Unsupported CPU architecture: $ARCH_RAW" >&2
    exit 1
    ;;
esac

if [ "$OS" = "macos" ] && [ "$ARCH" = "aarch64" ]; then
  TARGET="macos-arm64"
elif [ "$OS" = "linux" ] && [ "$ARCH" = "x86_64" ]; then
  TARGET="linux-x86_64"
elif [ "$OS" = "linux" ] && [ "$ARCH" = "aarch64" ]; then
  TARGET="linux-aarch64"
else
  echo "[vedit-install] No prebuilt binary for ${OS}-${ARCH}; build from source with Zig 0.17.0: (cd zig && zig build --release=safe)" >&2
  exit 1
fi

if [ "$VERSION" = "latest" ]; then
  # Resolve via GitHub redirect to avoid unauthenticated api.github.com 60 req/hr rate limits.
  LATEST_URL="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
  case "$LATEST_URL" in
    *"/releases/tag/"*)
      TAG="${LATEST_URL##*/releases/tag/}"
      ;;
    *)
      echo "[vedit-install] Failed to resolve latest release tag from GitHub (${LATEST_URL})." >&2
      exit 1
      ;;
  esac
else
  TAG="$VERSION"
fi

if ! printf '%s\n' "$TAG" | grep -Eq '^v[0-9A-Za-z._-]+$'; then
  echo "[vedit-install] Invalid release tag: ${TAG}" >&2
  exit 1
fi

ASSET="vedit-${TAG}-${TARGET}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${TAG}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vedit-install.XXXXXX")"
STAGE_BIN=""
cleanup() {
  rm -rf "$TMP_DIR"
  if [ -n "$STAGE_BIN" ] && [ -e "$STAGE_BIN" ]; then
    rm -f "$STAGE_BIN"
  fi
}
trap cleanup EXIT INT TERM

echo "[vedit-install] Downloading ${ASSET} (${TAG})..."
curl -fsSL "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/${ASSET}"
curl -fsSL "${BASE_URL}/SHA256SUMS.txt" -o "${TMP_DIR}/SHA256SUMS.txt"

EXPECTED_SHA="$(awk -v f="$ASSET" '$2 == f || $2 == ("*" f) { print $1 }' "${TMP_DIR}/SHA256SUMS.txt" | head -n 1 | tr 'A-F' 'a-f')"
if ! printf '%s\n' "$EXPECTED_SHA" | grep -Eq '^[0-9a-f]{64}$'; then
  echo "[vedit-install] Refusing install: valid SHA-256 for ${ASSET} missing from SHA256SUMS.txt" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  ACTUAL_SHA="$(sha256sum "${TMP_DIR}/${ASSET}" | awk '{ print $1 }' | tr 'A-F' 'a-f')"
elif command -v shasum >/dev/null 2>&1; then
  ACTUAL_SHA="$(shasum -a 256 "${TMP_DIR}/${ASSET}" | awk '{ print $1 }' | tr 'A-F' 'a-f')"
else
  echo "[vedit-install] Neither sha256sum nor shasum found; refusing unverified binary." >&2
  exit 1
fi

if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "[vedit-install] SHA-256 mismatch for ${ASSET}!" >&2
  echo "  expected: $EXPECTED_SHA" >&2
  echo "  actual:   $ACTUAL_SHA" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
tar -xzf "${TMP_DIR}/${ASSET}" -C "$TMP_DIR" vedit
STAGE_BIN="${INSTALL_DIR}/.vedit.tmp.$$"
install -m 0755 "${TMP_DIR}/vedit" "$STAGE_BIN"
mv -f "$STAGE_BIN" "${INSTALL_DIR}/vedit"
STAGE_BIN=""

echo "[vedit-install] Verified SHA-256 (${ACTUAL_SHA}) & installed -> ${INSTALL_DIR}/vedit"
"${INSTALL_DIR}/vedit" version

echo ""
echo "[vedit-install] Runtime companion check:"
for dep in mutool typst verapdf; do
  if command -v "$dep" >/dev/null 2>&1; then
    echo "  [OK] $dep -> $(command -v "$dep")"
  else
    echo "  [--] $dep not found on PATH"
  fi
done

case ":$PATH:" in
  *":${INSTALL_DIR}:"*)
    RESOLVED="$(command -v vedit 2>/dev/null || true)"
    if [ -n "$RESOLVED" ] && [ "$RESOLVED" != "${INSTALL_DIR}/vedit" ]; then
      echo ""
      echo "[WARN] 'vedit' on PATH currently resolves to ${RESOLVED}, shadowing ${INSTALL_DIR}/vedit."
      echo "       Put ${INSTALL_DIR} earlier in PATH or remove the stale binary."
    fi
    ;;
  *)
    echo ""
    echo "Add to PATH: export PATH=\"${INSTALL_DIR}:\$PATH\""
    ;;
esac
