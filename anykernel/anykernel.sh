### AnyKernel3 Ramdisk Mod Script
## osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=EvilTwin Kernel // SM8635 (KSUN + SuSFS)
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
device.name1=peridot
device.name2=POCO F6
device.name3=Redmi Turbo 3
supported.versions=14-17
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
# boot shell variables
block=/dev/block/by-name/boot;
is_slot_device=1;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;
no_block_display=false;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# Detect running kernel version
kver=$(uname -r 2>/dev/null | cut -d- -f1)
[ -z "$kver" ] && kver="6.1.176"

ui_print " "
ui_print "=================================================="
ui_print "   ______     _ _ ______          _               "
ui_print "  |  ____|   (_) |  ____|        (_)              "
ui_print "  | |__ __   ___| | | __      ___ _ __            "
ui_print "  |  __|\ \ / / | | |\ \ /\ / / | '_ \            "
ui_print "  | |____\ V /| | | | \ V  V /| | | | |           "
ui_print "  |______|\_/ |_|_|_|  \_/\_/ |_|_| |_|  // SM8635"
ui_print "=================================================="
ui_print "   TARGET  : POCO F6 / Redmi Turbo 3 (peridot)    "
ui_print "   ENGINE  : GKI $kver | KernelSU-Next v3.3.0     "
ui_print "   STEALTH : SuSFS v2.3.0 (VFS / Mount / Kstat)   "
ui_print "   PAYLOAD : QCA6750 802.11 Monitor + Raw TX      "
ui_print "=================================================="
ui_print " "
ui_print "[*] Unpacking boot partition..."

split_boot;

ui_print "[*] Injecting EvilTwin Kernel Image onto boot..."

flash_boot;

# Stage EvilTwin Wi-Fi module & on-demand loader (No boot-blocking post-fs-data hook)
if [ -f "$home/qca_cld3_qca6750.ko" ]; then
  ui_print "[*] Staging QCA6750 Patched WLAN Driver..."
  rm -f /data/adb/post-fs-data.d/eviltwin_wifi.sh
  mkdir -p /data/adb/eviltwin
  cp -f "$home/qca_cld3_qca6750.ko" /data/adb/eviltwin/qca_cld3_qca6750.ko
  chmod 0644 /data/adb/eviltwin/qca_cld3_qca6750.ko
  chcon u:object_r:vendor_file:s0 /data/adb/eviltwin/qca_cld3_qca6750.ko 2>/dev/null || true

  cat > /data/adb/eviltwin/eviltwin.sh << 'EOF'
#!/system/bin/sh
MOD="/data/adb/eviltwin/qca_cld3_qca6750.ko"
chcon u:object_r:vendor_file:s0 "$MOD" 2>/dev/null || true

case "$1" in
  load)
    echo "[*] Swapping to EvilTwin patched qca_cld3_qca6750.ko..."
    svc wifi disable
    sleep 1
    rmmod qca_cld3_qca6750 2>/dev/null || true
    for TARGET in /vendor_dlkm/lib/modules/qca_cld3_qca6750.ko /vendor/lib/modules/qca_cld3_qca6750.ko; do
      if [ -f "$TARGET" ]; then
        umount "$TARGET" 2>/dev/null || true
        mount -o bind "$MOD" "$TARGET"
      fi
    done
    insmod "$MOD" && echo "[+] Patched module loaded!" || echo "[-] insmod failed (check dmesg)"
    svc wifi enable
    ;;
  monitor)
    echo "[*] Enabling Monitor Mode (con_mode=4) on wlan0..."
    ip link set wlan0 down
    echo 4 > /sys/module/qca_cld3_qca6750/parameters/con_mode
    ip link set wlan0 up
    iw dev wlan0 info
    ;;
  station)
    echo "[*] Returning wlan0 to Managed Station Mode (con_mode=0)..."
    ip link set wlan0 down
    echo 0 > /sys/module/qca_cld3_qca6750/parameters/con_mode
    ip link set wlan0 up
    svc wifi enable
    ;;
  unload)
    echo "[*] Restoring stock Wi-Fi module..."
    svc wifi disable
    rmmod qca_cld3_qca6750 2>/dev/null || true
    for TARGET in /vendor_dlkm/lib/modules/qca_cld3_qca6750.ko /vendor/lib/modules/qca_cld3_qca6750.ko; do
      umount "$TARGET" 2>/dev/null || true
    done
    svc wifi enable
    ;;
  *)
    echo "Usage: su -c 'sh /data/adb/eviltwin/eviltwin.sh {load|monitor|station|unload}'"
    ;;
esac
EOF
  chmod 0755 /data/adb/eviltwin/eviltwin.sh
  ui_print "[+] Control script ready: /data/adb/eviltwin/eviltwin.sh"
fi

ui_print " "
ui_print "=================================================="
ui_print "   [✓] EVILTWIN DEPLOYMENT COMPLETE               "
ui_print "   >>  Reboot System & run 'eviltwin.sh load' <<  "
ui_print "=================================================="
ui_print " "
## end install
