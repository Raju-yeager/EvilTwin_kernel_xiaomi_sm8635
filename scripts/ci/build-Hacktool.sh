#!/usr/bin/env bash
set -euo pipefail

FLAVOR="${1:-ksun-susfs}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

KSUN_REPO="https://github.com/KernelSU-Next/KernelSU-Next"
KSUN_TAG="v3.3.0"
SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_PIN="4fc9c1898ea66f51847cdbc0d1473ea4ef525a70"

CLANG_DIR="${CLANG_DIR:?CLANG_DIR must point to Clang root}"
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

# 1. Swap kernel source to khargosxh18/android_kernel_xiaomi_sm8635 (Vibranium 6.1.174 base)
#    while preserving our EvilTwin scripts/, anykernel/, and modules_src/!
if ! grep -q "SUBLEVEL = 174" "$ROOT/Makefile" 2>/dev/null; then
  log "Switching kernel source tree to khargosxh18/android_kernel_xiaomi_sm8635 (Vibranium base)..."
  TMP_VIB="$(mktemp -d)"
  git clone --depth=1 https://github.com/khargosxh18/android_kernel_xiaomi_sm8635.git "$TMP_VIB"

  # Preserve EvilTwin custom directories
  cp -a "$ROOT/scripts/ci" "$TMP_VIB/scripts/"
  cp -a "$ROOT/scripts/susfs" "$TMP_VIB/scripts/"
  [[ -d "$ROOT/anykernel" ]] && cp -a "$ROOT/anykernel" "$TMP_VIB/"
  [[ -d "$ROOT/modules_src" ]] && cp -a "$ROOT/modules_src" "$TMP_VIB/"
  [[ -d "$ROOT/.github" ]] && cp -a "$ROOT/.github" "$TMP_VIB/"

  # Replace working tree with Vibranium source + EvilTwin additions
  find "$ROOT" -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} +
  cp -a "$TMP_VIB/." "$ROOT/"
  rm -rf "$TMP_VIB"
  log "Kernel source is now Vibranium ($(head -n 4 "$ROOT/Makefile" | tr '\n' ' '))"
fi

# Fix OpenSSL 3.0 undeclared 'key_pass' in certs/extract-cert.c on Ubuntu 24.04
if [[ -f "$ROOT/certs/extract-cert.c" ]]; then
  sed -i '/static.*key_pass/d' "$ROOT/certs/extract-cert.c"
  sed -i '1i static const char *key_pass;' "$ROOT/certs/extract-cert.c"
fi

# 2. Integrate KernelSU-Next v3.3.0 & SuSFS
KSUN_DIR="$ROOT/KernelSU-Next"
S4K_DIR="$ROOT/susfs4ksu"

if [[ ! -d "$KSUN_DIR" ]]; then
  log "Cloning KernelSU-Next ($KSUN_TAG)..."
  git clone --branch "$KSUN_TAG" "$KSUN_REPO" "$KSUN_DIR"
  rm -rf "$ROOT/drivers/kernelsu"
  ln -sfn "$KSUN_DIR/kernel" "$ROOT/drivers/kernelsu"
  grep -q "kernelsu" "$ROOT/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$ROOT/drivers/Makefile"
  grep -q "drivers/kernelsu/Kconfig" "$ROOT/drivers/Kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$ROOT/drivers/Kconfig"

  log "Fetching susfs4ksu ($SUSFS_PIN)..."
  rm -rf "$S4K_DIR"
  mkdir -p "$S4K_DIR"
  git -C "$S4K_DIR" init -q
  git -C "$S4K_DIR" remote add origin "$SUSFS_REPO"
  git -C "$S4K_DIR" fetch --depth=1 origin "$SUSFS_PIN"
  git -C "$S4K_DIR" checkout -q FETCH_HEAD

  log "Running scripts/susfs/integrate.sh..."
  chmod +x "$ROOT/scripts/susfs/integrate.sh"
  "$ROOT/scripts/susfs/integrate.sh" "$KSUN_DIR" "$S4K_DIR" "$ROOT"
fi

sed -i 's/^int ksu_handle_/__weak int ksu_handle_/g; s/^void ksu_handle_/__weak void ksu_handle_/g' "$KSUN_DIR/kernel/selinux/selinux.c" || true

rm -rf "$OUT"
mkdir -p "$OUT" "$DIST"

# 3. Generate Vibranium's exact defconfig (gki_defconfig + pineapple_GKI.config + peridot_GKI.config)
log "Generating Vibranium base config..."
make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 gki_defconfig

for frag in \
  "$ROOT/arch/arm64/configs/vendor/pineapple_GKI.config" \
  "$ROOT/arch/arm64/configs/vendor/peridot_GKI.config" \
  "$ROOT/arch/arm64/configs/peridot_GKI.config"; do
  if [[ -f "$frag" ]]; then
    log "Merging fragment: $frag"
    ARCH=arm64 "$ROOT/scripts/kconfig/merge_config.sh" -m -O "$OUT" "$OUT/.config" "$frag"
  fi
done

log "Applying 1:1 Vibranium working config + EvilTwin KSUN/SuSFS..."
./scripts/config --file "$OUT/.config" \
  --set-str LOCALVERSION "-Vibranium-EvilTwin-KSUN" \
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
  --set-val UCLAMP_BUCKETS_COUNT 20 \
  -d TASK_DELAY_ACCT \
  -d CFS_BANDWIDTH \
  -d RT_GROUP_SCHED \
  -d CGROUP_PIDS \
  -d CGROUP_DEVICE \
  -d CGROUP_PERF \
  -d CGROUP_MISC \
  -d USER_NS \
  -d RSEQ \
  -d SCHED_CLUSTER \
  -e SCHED_MC \
  -e SCHED_HRTICK \
  -e RT_SOFTIRQ_AWARE_SCHED \
  -e RCU_BOOST \
  -e RCU_LAZY \
  -e RCU_LAZY_DEFAULT_OFF \
  -e BOEFFLA_WL_BLOCKER \
  -e UNWIND_TABLES \
  -e UNWIND_PATCH_PAC_INTO_SCS \
  -e DYNAMIC_SCS \
  -d HZ_100 \
  -e HZ_250 \
  -d HZ_300 \
  -d HZ_1000 \
  --set-val HZ 250 \
  -d LTO_NONE \
  -d LTO_CLANG_THIN \
  -e LTO \
  -e LTO_CLANG \
  -e LTO_CLANG_FULL \
  -e CFI_CLANG \
  -d MODULE_SIG_ALL \
  -e MODULE_SIG_SHA256 \
  -d MODULE_SIG_SHA512 \
  --set-str MODULE_SIG_HASH "sha256" \
  -m MI_HARDWARE_ID \
  -m RFKILL \
  -m CFG80211 \
  -e NL80211_TESTMODE \
  -e CFG80211_REQUIRE_SIGNED_REGDB \
  -e CFG80211_USE_KERNEL_REGDB_KEYS \
  -e CFG80211_DEFAULT_PS \
  -d CFG80211_CRDA_SUPPORT \
  -d CFG80211_WEXT \
  -m MAC80211

make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

log "Building Kernel Image & Modules (jobs=$JOBS)"
make -j"$JOBS" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC="ccache clang" HOSTCC=clang HOSTCXX=clang++ \
  KBUILD_MODPOST_WARN=1 \
  Image modules 2>&1 | tee "$OUT/build.log"

IMG="$OUT/arch/arm64/boot/Image"
if [[ ! -f "$IMG" ]]; then
  echo "::error::Kernel Image was not produced at $IMG"
  exit 1
fi

log "Checking exported KABI CRCs for module_layout, runqueues, and cpu_number:"
grep -E "\b(module_layout|runqueues|cpu_number)\b" "$OUT/Module.symvers" || true

cp -f "$IMG" "$DIST/Image-$FLAVOR"
cp -f "$OUT/Module.symvers" "$DIST/Module.symvers-$FLAVOR"
cp -f "$OUT/.config" "$DIST/config-$FLAVOR"

# 4. Compile patched qca_cld3_qca6750.ko from modules_src against Vibranium source!
WLAN_DIR="$ROOT/modules_src/qcom/opensource/wlan"
QCACLD_DIR="$WLAN_DIR/qcacld-3.0"
if [[ -d "$QCACLD_DIR" ]]; then
  log "Building Patched Wi-Fi Module (qca_cld3_qca6750.ko)"
  ln -sfn ../qca-wifi-host-cmn "$QCACLD_DIR/cmn"

  sed -i '/CONFIG_WLAN_FEATURE_PKT_CAPTURE/d' "$QCACLD_DIR/configs/pineapple_gki_qca6750_defconfig" || true
  sed -i 's/CONFIG_DP_RX_DROP_RAW_FRM=y/CONFIG_DP_RX_DROP_RAW_FRM=n/g' "$QCACLD_DIR/configs/pineapple_gki_qca6750_defconfig" || true

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
    WLAN_CFG_OVERRIDE="CONFIG_QCA_CLD_WLAN=m CONFIG_DP_RX_DROP_RAW_FRM=n CONFIG_FEATURE_MONITOR_MODE_SUPPORT=y CONFIG_WIFI_MONITOR_SUPPORT=y" \
    KBUILD_MODPOST_WARN=1 \
    KCFLAGS="-Wno-error" \
    modules 2>&1 | tee "$OUT/wlan_build.log"

  llvm-strip --strip-debug "$QCACLD_DIR/qca_cld3_qca6750.ko"
  cp -f "$QCACLD_DIR/qca_cld3_qca6750.ko" "$DIST/qca_cld3_qca6750.ko"
fi

# 5. Package Unified AnyKernel3 Zip
if [[ "${SKIP_ZIP:-0}" != "1" && -d "$ROOT/anykernel" ]]; then
  STAGE="$(mktemp -d)"
  cp -r "$ROOT/anykernel/." "$STAGE/"
  cp -f "$IMG" "$STAGE/Image"

  if [[ -f "$QCACLD_DIR/qca_cld3_qca6750.ko" ]]; then
    cp -f "$QCACLD_DIR/qca_cld3_qca6750.ko" "$STAGE/qca_cld3_qca6750.ko"
  fi

  STAMP="$(date -u +%Y%m%d)"
  SHA="$(git rev-parse --short=7 HEAD 2>/dev/null || echo local)"
  ZIP_NAME="${ZIP_PREFIX}-${FLAVOR}-${ZIP_VERSION}-${STAMP}-${SHA}.zip"
  (cd "$STAGE" && zip -r9q "$DIST/$ZIP_NAME" .)
  rm -rf "$STAGE"
  log "Packaged unified flashable zip: $DIST/$ZIP_NAME"
fi
