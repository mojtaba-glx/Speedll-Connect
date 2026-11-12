#!/usr/bin/env bash
# ==============================================================================
# build_libbox_minimal.sh
#
# Builds a minimal, stripped-down libbox.aar for Android (arm64-v8a and armeabi-v7a)
# from upstream sing-box v1.14.4 source using gomobile.
#
# Excludes unnecessary protocols (tailscale, cloudflared, openvpn, openconnect,
# usbip, acme, dhcp, ccm, ocm) to minimize binary footprint.
# Retains essential VPN protocols: VLESS/Reality, VMess, Trojan, Shadowsocks,
# Hysteria2, TUIC, AnyTLS, and WireGuard.
#
# Prerequisites:
#   - Go 1.23.x (with GOPATH set and $GOPATH/bin in PATH)
#   - Android NDK (r26d / r27+; set ANDROID_NDK_HOME)
#   - gomobile: go install golang.org/x/mobile/cmd/gomobile@latest
#               gomobile init
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_AAR="${ROOT_DIR}/app/android/app/libs/libbox.aar"
SRC_DIR="${ROOT_DIR}/build/sing-box-src"
SING_BOX_VERSION="v1.14.4"

echo "=== Speedll Minimal libbox.aar Builder ==="
echo "Target sing-box version: ${SING_BOX_VERSION}"

# Check prerequisites
if ! command -v go >/dev/null 2>&1; then
    echo "ERROR: 'go' is not installed or not in PATH." >&2
    exit 1
fi

if ! command -v gomobile >/dev/null 2>&1; then
    echo "ERROR: 'gomobile' is not installed." >&2
    echo "Run: go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init" >&2
    exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" && -z "${ANDROID_NDK_ROOT:-}" ]]; then
    # Fallback to standard SDK ndk path if available
    NDK_CANDIDATE="$(find "${HOME}/.android-sdk/ndk" "${ANDROID_HOME:-/opt/android-sdk}/ndk" -maxdepth 1 -mindepth 1 2>/dev/null | sort -V | tail -n 1 || true)"
    if [[ -n "${NDK_CANDIDATE}" && -d "${NDK_CANDIDATE}" ]]; then
        export ANDROID_NDK_HOME="${NDK_CANDIDATE}"
        echo "Auto-detected ANDROID_NDK_HOME=${ANDROID_NDK_HOME}"
    else
        echo "ERROR: ANDROID_NDK_HOME or ANDROID_NDK_ROOT must be set." >&2
        exit 1
    fi
fi

# Clone / checkout sing-box
mkdir -p "${ROOT_DIR}/build"
if [[ ! -d "${SRC_DIR}" ]]; then
    echo "Cloning sing-box ${SING_BOX_VERSION}..."
    git clone --depth 1 --branch "${SING_BOX_VERSION}" https://github.com/sagernet/sing-box.git "${SRC_DIR}"
else
    echo "Using existing checkout in ${SRC_DIR}"
fi

cd "${SRC_DIR}"

BUILD_TAGS="with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api"
TARGET_ABIS="android/arm64,android/arm"

echo "Running gomobile bind..."
echo "  Targets: ${TARGET_ABIS}"
echo "  Tags:    ${BUILD_TAGS}"

gomobile bind \
    -v \
    -target="${TARGET_ABIS}" \
    -tags="${BUILD_TAGS}" \
    -javapkg=io.nekohasekai \
    -ldflags="-s -w" \
    -o "${OUTPUT_AAR}" \
    ./experimental/libbox

echo "SUCCESS: Generated minimal libbox.aar at ${OUTPUT_AAR}"
ls -lh "${OUTPUT_AAR}"
