#!/bin/bash
# build-flavor.sh — EvilTwin Kernel Builder (KernelSU-Next + SuSFS)
set -euo pipefail

FLAVOR="${1:-ksun-susfs}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1091
source scripts/ci/pins.env

OUT="${OUT:-out}"
DIST="${DIST:-dist}"
JOBS="${JOBS:-$(nproc --all)}"
CLANG_DIR="${CLANG_DIR:-$HOME/clang}"
ZIP_PREFIX="${ZIP_PREFIX:-EvilTwin}"
ZIP_VERSION="${ZIP_VERSION:-v1.0}"
ALLOW_DIRTY="${ALLOW_DIRTY:-1}"

export ARCH=arm64 SUBARCH=arm64 LLVM=1 LLVM_IAS=1
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-Raju-yeager}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-EvilTwin}"
export PATH="$CLANG_DIR/bin:$PATH"

log()  { echo "[$(date -u +\%H:\%M:\%S)]$*"; }
die()  { echo "::error::$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- flavor configuration (locked to KernelSU-Next + SuSFS) -----------------
ROOT_ENGINE=ksun
SUSFS=shim
INTEGRATE=integrate.sh
DROIDSPACES=0
KPM=0
APATCH=0
ZIPNAME="KSUN${KSUN_TAG#v}-SUSFS${SUSFS_EXPECT_VERSION#v}"
LABEL="KernelSU-Next ${KSUN_TAG} + SUSFS${SUSFS_EXPECT_VERSION}"

# ---- preconditions ----------------------------------------------------------
have clang || die "clang not in PATH (CLANG_DIR=$CLANG_DIR)"
log "flavor=$FLAVOR  clang:$(clang --version | head -1)"
if [ "${ALLOW_OTHER_CLANG:-0}" != 1 ]; then
  clang --version | head -1 | grep -qF "$NEUTRON_CLANG_ID" || die "clang is not the pinned release toolchain ($NEUTRON_CLANG_ID, build$NEUTRON_BUILD)"
fi
grep -qE '^SUBLEVEL = (175|176)' Makefile || die "base is not 6.1.175/176"

# ---- 1. root driver (KernelSU-Next) -----------------------------------------
fetch_driver() {
  rm -rf KernelSU
  git clone --quiet --branch "$KSUN_TAG" "$KSUN_REPO" KernelSU
  local cnt; cnt=$(git -C KernelSU rev-list --count HEAD)
  [ "$cnt" -gt 100 ] || die "KernelSU-Next clone looks shallow (rev-list count $cnt)"
  log "driver @ $(git -C KernelSU rev-parse --short HEAD) ($ROOT_ENGINE)"
}

fetch_susfs() {
  rm -rf susfs4ksu
  git clone --quiet -b "$SUSFS_BRANCH" "$SUSFS_REPO" susfs4ksu
  git -C susfs4ksu checkout --quiet "$SUSFS_PIN"
  local v; v="$(sed -n 's/.*SUSFS_VERSION[^"]*"\([^"]*\)".*/\1/p' susfs4ksu/kernel_patches/include/linux/susfs.h)"
  [ "$v" = "$SUSFS_EXPECT_VERSION" ] || die "expected SUSFS $SUSFS_EXPECT_VERSION, got '$v' at$SUSFS_PIN"
  log "susfs4ksu $v @ ${SUSFS_PIN:0:10}"
}

check_rejects() {
  local rej; rej="$(find . -path ./"$OUT" -prune -o -name '*.rej' -print 2>/dev/null || true)"
  [ -z "$rej" ] \vert{}\vert{} { echo "$rej" | while read -r r; do echo "== $r =="; cat "$r"; done; die "patch rejects present"; }
}

fetch_driver
ln -sfn ../KernelSU/kernel drivers/kernelsu
grep -q 'drivers/kernelsu/Kconfig' drivers/Kconfig || sed -i '/^endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
grep -q 'obj-$(CONFIG_KSU)' drivers/Makefile \vert{}\vert{} printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> drivers/Makefile

fetch_susfs

# ---- 2. SUSFS integration ---------------------------------------------------
log "integrating SUSFS via scripts/susfs/$INTEGRATE"
bash "scripts/susfs/$INTEGRATE" "$PWD/KernelSU" "$PWD/susfs4ksu" "$PWD"
check_rejects

if [ -f KernelSU/kernel/hook/lsm_hook.c ]; then
  bash scripts/fix-lsm-hook-lto.sh KernelSU/kernel/hook/lsm_hook.c
fi

# ---- 3. configure -----------------------------------------------------------
C=./scripts/config
make -s -j"$JOBS" O="$OUT" gki_defconfig
CFG="$OUT/.config"

$C --file "$CFG" -e KSU
for o in KSU_SUSFS KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT KSU_SUSFS_SPOOF_UNAME \
         KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
         KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MAP; do
  $C --file "$CFG" -e "$o"
done

make -s -j"$JOBS" O="$OUT" olddefconfig

log "config verification"
grep -q '^CONFIG_KSU=y' "$CFG" || die "KSU not enabled"
grep -q '^CONFIG_KSU_SUSFS=y' "$CFG" || die "SUSFS not enabled in .config"

# ---- 4. build ---------------------------------------------------------------
export KBUILD_COMPILER_STRING="$(clang --version | head -n1)"
CCW=clang; if [ "${USE_CCACHE:-1}" = 1 ] && have ccache; then CCW="ccache clang"; fi
log "build: make -j$JOBS O=$OUT CC='$CCW'"
make -j"$JOBS" O="$OUT" CC="$CCW" 2>&1 \vert{} tee "$OUT/build.log" | grep -E --line-buffered 'error:|Error [0-9]|LD      vmlinux$|OBJCOPY arch/arm64/boot/Image' || true
[ "${PIPESTATUS[0]}" = 0 ] || die "kernel build failed (see $OUT/build.log)"
IMG="$OUT/arch/arm64/boot/Image"; [ -f "$IMG" ] || die "no Image"
KREL="$(cat "$OUT/include/config/kernel.release")"

# ---- 5. KMI check (non-fatal warning mode for custom wireless configs) ------
KMI_BASE="scripts/ci/kmi-baseline/$FLAVOR.symvers"
KMI_ACCEPTED="${KMI_ACCEPTED:-scripts/ci/kmi-baseline/accepted-drift.txt}"
if [ -f "$KMI_BASE" ]; then
  if scripts/ci/symvers-diff.sh "$KMI_BASE" "$OUT/Module.symvers" "$KMI_ACCEPTED" > "$OUT/kmi-diff.txt" 2> "$OUT/kmi-summary.txt"; then
    log "KMI gate: $(cat "$OUT/kmi-summary.txt") vs $KMI_BASE"
  else
    log "WARNING: KMI CRC drift detected (expected due to custom NetHunter configs):"
    head -20 "$OUT/kmi-diff.txt" || true
  fi
fi

# ---- 6.
