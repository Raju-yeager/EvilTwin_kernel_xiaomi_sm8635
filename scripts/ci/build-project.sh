#!/usr/bin/env bash
set -euo pipefail

FLAVOR="${1:-ksun-susfs}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

KSUN_REPO="https://github.com/KernelSU-Next/KernelSU-Next"
# Dynamically fetch the latest KernelSU-Next release tag (e.g., v3.4.2), fallback to v3.3.0
KSUN_TAG="${KSUN_TAG:-$(curl -sL "https://api.github.com/repos/KernelSU-Next/KernelSU-Next/releases/latest" | grep -oE '"tag_name":\s*"[^"]+"' | head -n1 | cut -d'"' -f4 || true)}"
[[ -z "$KSUN_TAG" ]] && KSUN_TAG="v3.3.0"

SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
SUSFS_BRANCH="${SUSFS_BRANCH:-gki-android14-6.1}"
SUSFS_FALLBACK_PIN="4fc9c1898ea66f51847cdbc0d1473ea4ef525a70"
VIBRANIUM_REPO="https://github.com/khargosxh18/android_kernel_xiaomi_sm8635.git"

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

# Suppress warnings & prevent warnings from breaking build with -Wno-error
WARN_FLAGS="-Wno-error -Wno-gnu-zero-variadic-macro-arguments -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable -Wno-misleading-indentation -Wno-format ${KCFLAGS:-}"

log() {
  printf '\033[1;34m[%s]\033[0m %s\n' "$(date -u +%H:%M:%S)" "$*"
}

log "flavor=$FLAVOR  ksun=$KSUN_TAG  clang:$(clang --version | head -1)"

# 1. Sync kernel source to latest khargosxh18/android_kernel_xiaomi_sm8635 (Vibranium base)
log "Syncing kernel source tree to latest khargosxh18/android_kernel_xiaomi_sm8635..."
TMP_VIB="$(mktemp -d)"
git clone --depth=1 "$VIBRANIUM_REPO" "$TMP_VIB"

cp -a "$ROOT/scripts/ci" "$TMP_VIB/scripts/"
cp -a "$ROOT/scripts/susfs" "$TMP_VIB/scripts/"
[[ -d "$ROOT/anykernel" ]] && cp -a "$ROOT/anykernel" "$TMP_VIB/"
[[ -d "$ROOT/modules_src" ]] && cp -a "$ROOT/modules_src" "$TMP_VIB/"
[[ -d "$ROOT/.github" ]] && cp -a "$ROOT/.github" "$TMP_VIB/"

find "$ROOT" -mindepth 1 -maxdepth 1 ! -name ".git" -exec rm -rf {} +
cp -a "$TMP_VIB/." "$ROOT/"
rm -rf "$TMP_VIB"
log "Kernel source synced: $(head -n 4 "$ROOT/Makefile" | tr '\n' ' ')"

# Fix OpenSSL 3.0 undeclared 'key_pass' and unused global warning on Ubuntu 24.04
if [[ -f "$ROOT/certs/extract-cert.c" ]]; then
  sed -i '/static.*key_pass/d' "$ROOT/certs/extract-cert.c"
  sed -i '1i __attribute__((unused)) static const char *key_pass;' "$ROOT/certs/extract-cert.c"
fi

# 2. Integrate Latest KernelSU-Next & SuSFS (with automatic fallback to tested pin on conflict)
KSUN_DIR="$ROOT/KernelSU-Next"
S4K_DIR="$ROOT/susfs4ksu"

if [[ ! -d "$KSUN_DIR" ]]; then
  log "Cloning KernelSU-Next ($KSUN_TAG)..."
  git clone --depth=1 --branch "$KSUN_TAG" "$KSUN_REPO" "$KSUN_DIR" || {
    log "Tag $KSUN_TAG clone failed; falling back to v3.3.0..."
    git clone --depth=1 --branch "v3.3.0" "$KSUN_REPO" "$KSUN_DIR"
  }
  rm -rf "$ROOT/drivers/kernelsu"
  ln -sfn "$KSUN_DIR/kernel" "$ROOT/drivers/kernelsu"
  grep -q "kernelsu" "$ROOT/drivers/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$ROOT/drivers/Makefile"
  grep -q "drivers/kernelsu/Kconfig" "$ROOT/drivers/Kconfig" || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' "$ROOT/drivers/Kconfig"

  log "Fetching latest susfs4ksu ($SUSFS_BRANCH)..."
  rm -rf "$S4K_DIR"
  git clone --depth=1 --branch "$SUSFS_BRANCH" "$SUSFS_REPO" "$S4K_DIR" || {
    mkdir -p "$S4K_DIR"
    git -C "$S4K_DIR" init -q
    git -C "$S4K_DIR" remote add origin "$SUSFS_REPO"
    git -C "$S4K_DIR" fetch --depth=1 origin "$SUSFS_FALLBACK_PIN"
    git -C "$S4K_DIR" checkout -q FETCH_HEAD
  }

  chmod +x "$ROOT/scripts/susfs/integrate.sh"
  log "Running scripts/susfs/integrate.sh..."
  if ! "$ROOT/scripts/susfs/integrate.sh" "$KSUN_DIR" "$S4K_DIR" "$ROOT"; then
    log "Latest SuSFS had a conflict; falling back to tested SuSFS pin ($SUSFS_FALLBACK_PIN)..."
    git -C "$KSUN_DIR" checkout -- . || true
    rm -rf "$S4K_DIR"
    mkdir -p "$S4K_DIR"
    git -C "$S4K_DIR" init -q
    git -C "$S4K_DIR" remote add origin "$SUSFS_REPO"
    git -C "$S4K_DIR" fetch --depth=1 origin "$SUSFS_FALLBACK_PIN"
    git -C "$S4K_DIR" checkout -q FETCH_HEAD
    "$ROOT/scripts/susfs/integrate.sh" "$KSUN_DIR" "$S4K_DIR" "$ROOT"
  fi
fi

sed -i 's/^int ksu_handle_/__weak int ksu_handle_/g; s/^void ksu_handle_/__weak void ksu_handle_/g' "$KSUN_DIR/kernel/selinux/selinux.c" || true

# Fix KernelSU-Next v3.4+ missing sucompat symbols in fs/exec.c
if grep -q "ksu_handle_post_execveat_sucompat" "$ROOT/fs/exec.c"; then
  log "Injecting correct weak sucompat stubs into fs/exec.c..."
  cat << 'EOF' >> "$ROOT/fs/exec.c"

/* Fallback stubs for KernelSU-Next v3.4+ missing sucompat */
void __weak ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) {}
void __weak ksu_handle_post_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) {}
EOF
fi

rm -rf "$OUT"
mkdir -p "$OUT" "$DIST"

# 3. Generate Vibranium's exact defconfig
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
  CC="ccache clang" HOSTCC="ccache clang" HOSTCXX="ccache clang++" \
  KBUILD_MODPOST_WARN=1 \
  KCFLAGS="$WARN_FLAGS" \
  Image modules 2>&1 | tee "$OUT/build.log"

IMG="$OUT/arch/arm64/boot/Image"
if [[ ! -f "$IMG" ]]; then
  echo "::error::Kernel Image was not produced at $IMG"
  exit 1
fi

cp -f "$IMG" "$DIST/Image-$FLAVOR"
cp -f "$OUT/Module.symvers" "$DIST/Module.symvers-$FLAVOR"
cp -f "$OUT/.config" "$DIST/config-$FLAVOR"

# 4. Compile patched qca_cld3_qca6750.ko from modules_src
WLAN_DIR="$ROOT/modules_src/qcom/opensource/wlan"
QCACLD_DIR="$WLAN_DIR/qcacld-3.0"
if [[ -d "$QCACLD_DIR" ]]; then
  log "Building Patched Wi-Fi Module (qca_cld3_qca6750.ko)"
  ln -sfn ../qca-wifi-host-cmn "$QCACLD_DIR/cmn"

  # Append 43 vendor_dlkm symbol CRCs
  python3 - "$OUT/Module.symvers" << 'PYEOF'
import sys

symvers_path = sys.argv[1]
lines = open(symvers_path, "r", encoding="utf-8", errors="ignore").read().splitlines()
sample = lines[0] if lines else "0x00000000\tdummy\tvmlinux\tEXPORT_SYMBOL\t"
num_tabs = sample.count("\t")

vendor_syms = [
    ("0xf35b1593", "__icnss_register_driver"),
    ("0x62f5d9f4", "cld80211_get_genl_family"),
    ("0x7f3db83b", "cnss_utils_get_wlan_derived_mac_address"),
    ("0xdd04312a", "cnss_utils_get_wlan_mac_address"),
    ("0x7cab32df", "cnss_utils_get_wlan_unsafe_channel"),
    ("0x0e39f21c", "cnss_utils_increment_driver_load_cnt"),
    ("0x83d6fb88", "cnss_utils_set_wlan_unsafe_channel"),
    ("0xef048766", "cnss_utils_wlan_get_dfs_nol"),
    ("0xb83d7182", "cnss_utils_wlan_set_dfs_nol"),
    ("0x1a4d338d", "deregister_cld_cmd_cb"),
    ("0xd42566f2", "icnss_allow_l1"),
    ("0x8831b37b", "icnss_athdiag_read"),
    ("0xaabf5c45", "icnss_athdiag_write"),
    ("0x61e3742e", "icnss_exit_power_save"),
    ("0xe32d9f2a", "icnss_force_wake_release"),
    ("0x0f936194", "icnss_force_wake_request"),
    ("0xc7db251a", "icnss_get_curr_therm_cdev_state"),
    ("0x71358fe3", "icnss_get_mhi_state"),
    ("0xd9cebef2", "icnss_get_msi_address"),
    ("0x22af7d88", "icnss_get_msi_irq"),
    ("0xf7f0c22c", "icnss_get_soc_info"),
    ("0xa8b17f5a", "icnss_get_user_msi_assignment"),
    ("0x71e6e153", "icnss_idle_restart"),
    ("0x413458df", "icnss_idle_shutdown"),
    ("0x354028de", "icnss_is_device_awake"),
    ("0x9b5bd3f7", "icnss_is_fw_down"),
    ("0xbadde3d4", "icnss_is_pci_ep_awake"),
    ("0x49e4b3b1", "icnss_power_off"),
    ("0x8f973526", "icnss_power_on"),
    ("0xa35f4a41", "icnss_prevent_l1"),
    ("0x6a21d2a9", "icnss_qmi_send"),
    ("0xb8aa15ba", "icnss_set_fw_log_mode"),
    ("0x46d9e785", "icnss_smmu_get_domain"),
    ("0x3c92e266", "icnss_smmu_map"),
    ("0xb71bf2a4", "icnss_thermal_cdev_register"),
    ("0x188e10cc", "icnss_thermal_cdev_unregister"),
    ("0x835eac09", "icnss_trigger_recovery"),
    ("0x07cf14dc", "icnss_unregister_driver"),
    ("0x254b144e", "icnss_wlan_disable"),
    ("0x10b1edcc", "icnss_wlan_enable"),
    ("0x14d2e4b6", "register_cld_cmd_cb"),
    ("0xdff15e8a", "wcnss_prealloc_get"),
    ("0x0521fc53", "wcnss_prealloc_put"),
]

existing = {l.split("\t")[1] for l in lines if "\t" in l}
with open(symvers_path, "a", encoding="utf-8") as f:
    for crc, name in vendor_syms:
        if name not in existing:
            extra_tabs = "\t" * max(0, num_tabs - 3)
            f.write(f"{crc}\t{name}\tvmlinux\tEXPORT_SYMBOL{extra_tabs}\n")
print(f"[+] Appended {len(vendor_syms)} vendor symbols with {num_tabs} tabs per line")
PYEOF

  sed -i '/CONFIG_WLAN_FEATURE_PKT_CAPTURE/d' "$QCACLD_DIR/configs/pineapple_gki_qca6750_defconfig" || true
  sed -i 's/CONFIG_DP_RX_DROP_RAW_FRM=y/CONFIG_DP_RX_DROP_RAW_FRM=n/g' "$QCACLD_DIR/configs/pineapple_gki_qca6750_defconfig" || true

  make -j"$JOBS" -C "$ROOT" O="$OUT" \
    M="$QCACLD_DIR" \
    CC="ccache clang" HOSTCC="ccache clang" HOSTCXX="ccache clang++" \
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
    KCFLAGS="$WARN_FLAGS" \
    modules 2>&1 | tee "$OUT/wlan_build.log"

  llvm-strip --strip-debug "$QCACLD_DIR/qca_cld3_qca6750.ko"
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

# 6. Build Universal Magisk/KernelSU Module
if [[ -f "$QCACLD_DIR/qca_cld3_qca6750.ko" ]]; then
  log "Packaging Universal Magisk/KernelSU Module..."
  MAGISK_DIR="$(mktemp -d)"
  mkdir -p "$MAGISK_DIR/META-INF/com/google/android"
  mkdir -p "$MAGISK_DIR/system/bin"

  curl -sL -o "$MAGISK_DIR/META-INF/com/google/android/update-binary" "https://raw.githubusercontent.com/topjohnwu/Magisk/master/scripts/module_installer.sh"
  chmod +x "$MAGISK_DIR/META-INF/com/google/android/update-binary"
  echo "#MAGISK" > "$MAGISK_DIR/META-INF/com/google/android/updater-script"

  cat << 'EOF' > "$MAGISK_DIR/module.prop"
id=eviltwin-wifi
name=Universal EvilTwin Wi-Fi (Monitor Mode)
version=v1.0
versionCode=1
author=Raju-yeager
description=Native monitor mode (con_mode=4) and raw packet injection for POCO F6 (peridot). Automatically adapts to ANY custom kernel on every boot.
EOF

  cat << 'EOF' > "$MAGISK_DIR/customize.sh"
ui_print "- Installing Universal EvilTwin Wi-Fi"
ui_print "- The module will automatically patch itself to match"
ui_print "- your specific kernel version on the next boot."
EOF

  cp "$QCACLD_DIR/qca_cld3_qca6750.ko" "$MAGISK_DIR/qca_cld3_qca6750_original.ko"

  cat << 'EOF' > "$MAGISK_DIR/post-fs-data.sh"
#!/system/bin/sh
MODDIR=${0%/*}
KO_FILE="$MODDIR/qca_cld3_qca6750.ko"
ORIG_FILE="$MODDIR/qca_cld3_qca6750_original.ko"
KVER="$(uname -r)"

if [ ! -f "$KO_FILE" ] || ! grep -q "vermagic=$KVER " "$KO_FILE"; then
    cp "$ORIG_FILE" "$KO_FILE"
    OFFSET=$(grep -aob "vermagic=" "$KO_FILE" | head -n 1 | cut -d: -f1)
    if [ -n "$OFFSET" ]; then
        printf "vermagic=%s SMP preempt mod_unload modversions aarch64\0" "$KVER" > "$MODDIR/new_vermagic"
        dd if="$MODDIR/new_vermagic" of="$KO_FILE" bs=1 seek="$OFFSET" conv=notrunc status=none
        rm -f "$MODDIR/new_vermagic"
    fi
fi
EOF
  chmod +x "$MAGISK_DIR/post-fs-data.sh"

  cat << 'EOF' > "$MAGISK_DIR/system/bin/wlan-mode"
#!/system/bin/sh
MODDIR="/data/adb/modules/eviltwin-wifi"
STOCK_KO=$(find /vendor_dlkm /vendor /system -type f -name qca_cld3_qca6750.ko | head -n 1)
MOD_KO="$MODDIR/qca_cld3_qca6750.ko"

if [ "$1" = "mon" ]; then
    echo "[+] Enabling Monitor Mode..."
    ip link set wlan0 down
    rmmod qca_cld3_qca6750 2>/dev/null
    mount --bind "$MOD_KO" "$STOCK_KO"
    insmod "$STOCK_KO"
    echo 4 > /sys/module/qca_cld3_qca6750/parameters/con_mode
    svc wifi disable
    ip link set wlan0 up
    [ -n "$2" ] && iw dev wlan0 set channel "$2"
    echo "[+] wlan0 is now in Monitor Mode (con_mode=4)"
elif [ "$1" = "sta" ]; then
    echo "[+] Restoring Normal Android Wi-Fi..."
    ip link set wlan0 down
    umount "$STOCK_KO" 2>/dev/null
    rmmod qca_cld3_qca6750 2>/dev/null
    insmod "$STOCK_KO"
    echo 0 > /sys/module/qca_cld3_qca6750/parameters/con_mode
    svc wifi enable
    echo "[+] Normal Android Wi-Fi restored."
else
    echo "Usage: su -c wlan-mode [mon <channel> | sta]"
fi
EOF
  chmod +x "$MAGISK_DIR/system/bin/wlan-mode"

  (cd "$MAGISK_DIR" && zip -r9q "$DIST/Universal-EvilTwin-WiFi-Magisk-${ZIP_VERSION}.zip" .)
  rm -rf "$MAGISK_DIR"
  log "Packaged Universal Magisk Module: $DIST/Universal-EvilTwin-WiFi-Magisk-${ZIP_VERSION}.zip"
fi
