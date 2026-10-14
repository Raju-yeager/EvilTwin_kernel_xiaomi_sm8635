#!/usr/bin/env bash
set -euo pipefail

FLAVOR="${1:-ksun-susfs}"
if [[ "$FLAVOR" != "ksun-susfs" ]]; then
  echo "::error::Unsupported flavor '$FLAVOR' (only ksun-susfs is supported)"
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

CLANG_DIR="${CLANG_DIR:?CLANG_DIR must point to Neutron Clang root}"
export PATH="$CLANG_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export LLVM=1
export LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-Raju-yeager}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-EvilTwin}"

OUT="${OUT_DIR:-$ROOT/out}"
DIST="${DIST_DIR:-$ROOT/dist}"
JOBS="${JOBS:-$(nproc --all)}"
ZIP_PREFIX="${ZIP_PREFIX:-EvilTwin}"
ZIP_VERSION="${ZIP_VERSION:-v1.0}"

log() {
  printf '\033[1;34m[%s]\033[0m %s\n' "$(date -u +%H:%M:%S)" "$*"
}

log "flavor=$FLAVOR  clang:$(clang --version | head -1)"

if [[ ! -d "$ROOT/KernelSU-Next" ]]; then
  echo "::error::KernelSU-Next/ directory missing at repo root"
  exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT" "$DIST"

log "Applying gki_defconfig"
make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 gki_defconfig

log "Configuring EvilTwin (KernelSU-Next + SuSFS + Unsigned Module Loading)"
./scripts/config --file "$OUT/.config" \
  --set-str LOCALVERSION "-EvilTwin-KSUN-SuSFS" \
  -d LOCALVERSION_AUTO \
  -e KPROBES \
  -e HAVE_KPROBES \
  -e KPROBE_EVENTS \
  -e KSU \
  -e KSU_SUSFS \
  -e KSU_SUSFS_SUS_PATH \
  -e KSU_SUSFS_SUS_MOUNT \
  -e KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT \
  -e KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT \
  -e KSU_SUSFS_SUS_KSTAT \
  -e KSU_SUSFS_TRY_UMOUNT \
  -e KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT \
  -e KSU_SUSFS_SPOOF_UNAME \
  -e KSU_SUSFS_ENABLE_LOG \
  -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
  -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
  -e KSU_SUSFS_OPEN_REDIRECT \
  -d KSU_SUSFS_SUS_SU \
  -e CFG80211 \
  -e MAC80211 \
  -e RFKILL \
  -d MODULE_SIG \
  -d MODULE_SIG_FORCE \
  -d MODULE_SIG_ALL \
  -d MODVERSIONS

make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

log "Building Kernel Image & Modules (jobs=$JOBS)"
make -j"$JOBS" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC="ccache clang" HOSTCC=clang HOSTCXX=clang++ \
  Image modules 2>&1 | tee "$OUT/build.log"

IMG="$OUT/arch/arm64/boot/Image"
if [[ ! -f "$IMG" ]]; then
  echo "::error::Kernel Image was not produced at $IMG"
  exit 1
fi

cp -f "$IMG" "$DIST/Image-$FLAVOR"
cp -f "$OUT/Module.symvers" "$DIST/Module.symvers-$FLAVOR"
cp -f "$OUT/.config" "$DIST/config-$FLAVOR"

# If modules_src was checked out by CI, compile qca_cld3_qca6750.ko now
WLAN_DIR="$ROOT/modules_src/qcom/opensource/wlan"
QCACLD_DIR="$WLAN_DIR/qcacld-3.0"
if [[ -d "$QCACLD_DIR" ]]; then
  log "Building Patched Wi-Fi Module (qca_cld3_qca6750.ko)"
  ln -sfn ../qca-wifi-host-cmn "$QCACLD_DIR/cmn"

  make -j"$JOBS" -C "$ROOT" O="$OUT" \
    M="$QCACLD_DIR" \
    CC="ccache clang" \
    WLAN_ROOT="$QCACLD_DIR" \
    WLAN_COMMON_ROOT=cmn \
    WLAN_COMMON_INC="$QCACLD_DIR/cmn" \
    WLAN_FW_API="$WLAN_DIR/fw-api/" \
    CONFIG_ARCH_PINEAPPLE=y \
    CONFIG_ARCH_QCOM=y \
    CONFIG_CNSS_OUT_OF_TREE=y \
    CONFIG_IPA_OUT_OF_TREE=y \
    CONFIG_QCA_WIFI_ISOC=0 \
    CONFIG_QCA_WIFI_2_0=1 \
    WLAN_PROFILE=qca6750 \
    DYNAMIC_SINGLE_CHIP=qca6750 \
    DEVNAME=qca6750 \
    MODNAME=qca_cld3_qca6750 \
    CONFIG_QCA_CLD_WLAN=m \
    WLAN_CFG_OVERRIDE="CONFIG_QCA_CLD_WLAN=m CONFIG_DP_RX_DROP_RAW_FRM=n CONFIG_WLAN_FEATURE_PKT_CAPTURE=y CONFIG_FEATURE_MONITOR_MODE_SUPPORT=y CONFIG_WIFI_MONITOR_SUPPORT=y" \
    KBUILD_MODPOST_WARN=1 \
    KCFLAGS="-Wno-error" \
    modules 2>&1 | tee "$OUT/wlan_build.log"

  llvm-strip --strip-debug "$QCACLD_DIR/qca_cld3_qca6750.ko"
  cp -f "$QCACLD_DIR/qca_cld3_qca6750.ko" "$DIST/qca_cld3_qca6750.ko"
fi

if [[ "${SKIP_ZIP:-0}" != "1" && -d "$ROOT/anykernel" ]]; then
  STAGE="$(mktemp -d)"
  cp -r "$ROOT/anykernel/." "$STAGE/"
  cp -f "$IMG" "$STAGE/Image"

  # Embed patched Wi-Fi module inside AnyKernel3 zip so a single flash installs both
  if [[ -f "$DIST/qca_cld3_qca6750.ko" ]]; then
    cp -f "$DIST/qca_cld3_qca6750.ko" "$STAGE/qca_cld3_qca6750.ko"
    cat >> "$STAGE/anykernel.sh" << 'EOF'

# Install EvilTwin patched Wi-Fi module automatically via KernelSU boot hook
if [ -f "$home/qca_cld3_qca6750.ko" ]; then
  ui_print "- Installing EvilTwin Patched Wi-Fi Module (Monitor + Injection)..."
  mkdir -p /data/adb/eviltwin /data/adb/post-fs-data.d
  cp -f "$home/qca_cld3_qca6750.ko" /data/adb/eviltwin/qca_cld3_qca6750.ko
  chmod 0644 /data/adb/eviltwin/qca_cld3_qca6750.ko
  cat > /data/adb/post-fs-data.d/eviltwin_wifi.sh << 'BOOTEOF'
#!/system/bin/sh
MOD="/data/adb/eviltwin/qca_cld3_qca6750.ko"
for TARGET in /vendor_dlkm/lib/modules/qca_cld3_qca6750.ko /vendor/lib/modules/qca_cld3_qca6750.ko /system/vendor/lib/modules/qca_cld3_qca6750.ko; do
  if [ -f "$TARGET" ] && [ -f "$MOD" ]; then
    mount -o bind "$MOD" "$TARGET"
  fi
done
BOOTEOF
  chmod 0755 /data/adb/post-fs-data.d/eviltwin_wifi.sh
fi
EOF
  fi

  STAMP="$(date -u +%Y%m%d)"
  SHA="$(git rev-parse --short=7 HEAD 2>/dev/null || echo local)"
  ZIP_NAME="${ZIP_PREFIX}-${FLAVOR}-${ZIP_VERSION}-${STAMP}-${SHA}.zip"
  (cd "$STAGE" && zip -r9q "$DIST/$ZIP_NAME" .)
  rm -rf "$STAGE"
  log "Packaged unified flashable zip: $DIST/$ZIP_NAME"
fi
