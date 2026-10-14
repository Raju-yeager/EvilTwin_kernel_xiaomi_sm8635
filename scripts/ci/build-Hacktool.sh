#!/usr/bin/env bash
set -euo pipefail

FLAVOR="${1:-ksun-susfs}"
if [[ "$FLAVOR" != "ksun-susfs" ]]; then
  echo "::error::Unsupported flavor '$FLAVOR' (only ksun-susfs is supported)"
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

# 1. Load pinned versions for KernelSU-Next and SuSFS
if [[ -f "$ROOT/scripts/ci/pins.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/scripts/ci/pins.env"
  set +a
fi

KSUN_REPO="${KSUN_REPO:-https://github.com/KernelSU-Next/KernelSU-Next}"
KSUN_TAG="${KSUN_TAG:-v3.3.0}"
SUSFS_REPO="${SUSFS_REPO:-https://gitlab.com/simonpunk/susfs4ksu.git}"
SUSFS_PIN="${SUSFS_PIN:-4fc9c1898ea66f51847cdbc0d1473ea4ef525a70}"

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

# 2. Clone KernelSU-Next & susfs4ksu and run scripts/susfs/integrate.sh
KSUN_DIR="$ROOT/KernelSU-Next"
S4K_DIR="$ROOT/susfs4ksu"

if [[ ! -d "$KSUN_DIR" ]]; then
  log "Cloning KernelSU-Next ($KSUN_TAG)..."
  git clone --branch "$KSUN_TAG" "$KSUN_REPO" "$KSUN_DIR"
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

rm -rf "$OUT"
mkdir -p "$OUT" "$DIST"

# 2b. Pull clean GKI defconfig from Vibranium (khargosxh18/android_kernel_xiaomi_sm8635)
log "Fetching clean gki_defconfig from Vibranium repo..."
curl -fsSL "https://raw.githubusercontent.com/khargosxh18/android_kernel_xiaomi_sm8635/HEAD/arch/arm64/configs/gki_defconfig" \
  -o "$ROOT/arch/arm64/configs/gki_defconfig"

# 2c. Deduplicate any double EXPORT_SYMBOL*(sysctl_sched_*) left in kernel/sched/fair.c by BORE patch
log "Deduplicating EXPORT_SYMBOL in kernel/sched/fair.c..."
python3 -c '
p = "kernel/sched/fair.c"
s = open(p).read().splitlines(True)
seen, out = set(), []
for line in s:
    if "EXPORT_SYMBOL" in line and "sysctl_sched_" in line:
        if line.strip() in seen:
            continue
        seen.add(line.strip())
    out.append(line)
open(p, "w").writelines(out)
'

log "Applying gki_defconfig"
make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 gki_defconfig

log "Configuring EvilTwin (KernelSU-Next + SuSFS + Strict GKI KABI Lock)"
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
  -d UNWIND_PATCH_PAC_INTO_SCS \
  -d DYNAMIC_SCS \
  -d UNWIND_TABLES \
  -d SCHED_BORE \
  -d RT_SOFTIRQ_AWARE_SCHED \
  -d RCU_BOOST \
  -d RCU_LAZY \
  -d BOEFFLA_WL_BLOCKER \
  -d KPROFILES \
  -d MQ_IOSCHED_ADIOS \
  -d ADIOS_IOSCHED \
  -d HZ_100 \
  -e HZ_250 \
  -d HZ_300 \
  -d HZ_1000 \
  --set-val HZ 250 \
  --set-val UCLAMP_BUCKETS_COUNT 5 \
  -e CFS_BANDWIDTH \
  -e RT_GROUP_SCHED \
  -e TASK_DELAY_ACCT \
  -e RSEQ \
  -e SCHED_CLUSTER \
  -e PID_NS \
  -e USER_NS \
  -e CGROUP_PIDS \
  -e CGROUP_DEVICE \
  -e CGROUP_PERF \
  -e CGROUP_MISC

make O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 olddefconfig

# Force-disable UNWIND_TABLES if any Kconfig 'select' re-enabled it during olddefconfig
if grep -q "^CONFIG_UNWIND_TABLES=y" "$OUT/.config" || grep -q "^CONFIG_SCHED_BORE=y" "$OUT/.config"; then
  log "WARNING: Kconfig re-enabled ABI-breaking symbols; forcing off..."
  sed -i 's/^CONFIG_UNWIND_PATCH_PAC_INTO_SCS=y/# CONFIG_UNWIND_PATCH_PAC_INTO_SCS is not set/' "$OUT/.config"
  sed -i 's/^CONFIG_DYNAMIC_SCS=y/# CONFIG_DYNAMIC_SCS is not set/' "$OUT/.config"
  sed -i 's/^CONFIG_UNWIND_TABLES=y/# CONFIG_UNWIND_TABLES is not set/' "$OUT/.config"
  sed -i 's/^CONFIG_SCHED_BORE=y/# CONFIG_SCHED_BORE is not set/' "$OUT/.config"
fi

log "Verifying KABI-critical config state:"
grep -E "CONFIG_(UNWIND_TABLES|SCHED_BORE|HZ=|UCLAMP_BUCKETS_COUNT|CFS_BANDWIDTH|TASK_DELAY_ACCT|RSEQ)" "$OUT/.config" || true

log "Building Kernel Image & Modules (jobs=$JOBS)"
make -j"$JOBS" O="$OUT" ARCH=arm64 LLVM=1 LLVM_IAS=1 \
  CC="ccache clang" HOSTCC=clang HOSTCXX=clang++ \
  Image modules 2>&1 | tee "$OUT/build.log"

IMG="$OUT/arch/arm64/boot/Image"
if [[ ! -f "$IMG" ]]; then
  echo "::error::Kernel Image was not produced at $IMG"
  exit 1
fi

log "Checking exported KABI CRCs for module_layout and runqueues:"
grep -E "\b(module_layout|runqueues)\b" "$OUT/Module.symvers" || true

cp -f "$IMG" "$DIST/Image-$FLAVOR"
cp -f "$OUT/Module.symvers" "$DIST/Module.symvers-$FLAVOR"
cp -f "$OUT/.config" "$DIST/config-$FLAVOR"

# 3. Compile patched qca_cld3_qca6750.ko from modules_src
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
fi

# 4. Package Unified AnyKernel3 Zip ONLY (no loose .ko in dist/)
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
