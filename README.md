<div align="center">
  <img src="assets/gemini-svg.svg" width="100%" alt="EvilTwin Kernel Banner" />
  # **EVILTWIN KERNEL & WI-FI SUITE // SM8635**
  *Offensive Security & Low-Level Wireless Auditing Engine for Xiaomi POCO F6 / Redmi Turbo 3 (`peridot`)*
  [![Release](https://img.shields.io/github/v/release/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635?color=00ff66&label=RELEASE&style=for-the-badge&logo=git&logoColor=black)](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases)
  [![GKI Version](https://img.shields.io/badge/GKI-6.1-black?color=00ff66&style=for-the-badge&logo=linux&logoColor=00ff66)](https://kernel.org)
  [![KSUN](https://img.shields.io/github/v/release/KernelSU-Next/KernelSU-Next?color=00e5ff&label=KernelSU--Next&style=for-the-badge&logo=android&logoColor=black)](https://github.com/KernelSU-Next/KernelSU-Next)
  [![SUSFS](https://img.shields.io/badge/SUSFS-gki--android14--6.1-purple?style=for-the-badge&logo=shield)](https://gitlab.com/simonpunk/susfs4ksu)
  [![Toolchain](https://img.shields.io/badge/Neutron_Clang-23.0.0git-orange?style=for-the-badge&logo=llvm)](https://github.com/Neutron-Toolchains/clang-build-catalogue)
  [![Downloads](https://img.shields.io/github/downloads/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/total?color=00e5ff&label=DOWNLOADS&style=for-the-badge&logo=cloud-download)](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases)
  [![Support](https://img.shields.io/badge/Support-Buy_Me_A_Coffee-FFDD00?style=for-the-badge&logo=buy-me-a-coffee&logoColor=black)](https://buymeacoffee.com/raju_yeager)
  [![License](https://img.shields.io/badge/LICENSE-GPL--2.0-red?style=for-the-badge)](LICENSE)
</div>
---
> **⚠️ WARNING / DISCLAIMER**  
> **USE AT YOUR OWN RISK.** This custom kernel and wireless driver suite is provided strictly for educational purposes, authorized wireless security auditing, and hardware research. Modifying kernel-level driver states can cause bootloops, thermal variance, or system instability. The developer assumes zero liability for bricked devices, voided warranties, or misuse.
---
## ⚡ Overview & Capabilities
**EvilTwin** is an offensive-security GKI 6.1 kernel and out-of-tree WLAN driver suite engineered for Qualcomm SM8635 devices (`peridot`). While stock OEM kernels strip `mac80211` stacks, enforce module signature locks, and drop raw 802.11 frames in the datapath, EvilTwin delivers a patched `qcacld-3.0` (`qca_cld3_qca6750.ko`) Wi-Fi driver in **two flexible deployment variants**: a **Full Custom Kernel + Wi-Fi AnyKernel3 Bundle** and a **Standalone Universal Magisk / KernelSU Module**.
* **Native Monitor Mode (`wlan0`):** Unlocks internal QCA6750 driver transport endpoints (`con_mode=4`) and disables `CONFIG_DP_RX_DROP_RAW_FRM=n`, converting the onboard Wi-Fi chip into a passive 802.11 packet listener without external USB OTG adapters.
* **Raw 802.11 Frame Injection:** Enables `CONFIG_FEATURE_MONITOR_MODE_SUPPORT=y` and `CONFIG_WIFI_MONITOR_SUPPORT=y` in `qcacld-3.0` to allow radiotap-encapsulated raw frame transmission.
* **Vendor Symbol CRC Alignment:** Pre-linked against 43 SM8635 `vendor_dlkm` symbol CRCs (`icnss_*`, `cnss_utils_*`, `wcnss_prealloc_*`, `cld80211_*`) for seamless module loading across stock and custom ROMs.
* **KernelSU-Next + SuSFS (Auto-Synced):** Built-in root integration dynamically synced to the latest upstream KernelSU-Next release and SuSFS (`gki-android14-6.1`), featuring kernel-level mount hiding (`sus_mount`), path hiding (`sus_path`), kstat spoofing (`sus_kstat`), `uname` spoofing, and open redirect.
* **Vibranium Performance Base:** Tuned with 250Hz timer tick, Full Clang LTO + CFI, UClamp (20 buckets), RCU Boost & Lazy RCU, and Boeffla Wakelock Blocker.
---
## 🧩 Variant 2: Universal Magisk / KernelSU Wi-Fi Module (No Kernel Change Required)
Don't want to replace your current kernel? **`Universal-EvilTwin-WiFi-Magisk-v1.0.zip`** lets you bring native Monitor Mode and packet injection to **any existing kernel** (Stock HyperOS, AOSP, LineageOS, or third-party custom kernels) without flashing `boot.img`.
* **Zero Kernel Modification:** Leaves your existing `boot` partition and kernel completely untouched—flashable directly in Magisk, KernelSU, KernelSU-Next, or APatch.
* **Dynamic `vermagic` Binary Patching:** Includes an automated `post-fs-data.sh` engine that inspects `$(uname -r)` on every boot and binary-patches the `vermagic=` header inside `qca_cld3_qca6750.ko` via `dd`. Even if you dirty-flash a new ROM or switch kernels later, the module automatically adapts itself on the next reboot.
* **Non-Destructive Bind Mounting:** Uses `mount --bind` over your stock `/vendor_dlkm/lib/modules/qca_cld3_qca6750.ko` at runtime—never permanently overwriting vendor partition files.
* **One-Command `wlan-mode` CLI Utility:** Ships with `/system/bin/wlan-mode` to switch between Monitor Mode (`wlan-mode mon [channel]`) and normal Android Wi-Fi (`wlan-mode sta`) in one command.
---
## 📥 Downloads
### [⬇ Download Latest EvilTwin Kernel & Universal Module Releases](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases/latest)

| Artifact | Target Users | What It Installs |
| :--- | :--- | :--- |
| **`EvilTwin-ksun-susfs-v1.0-*.zip`** | Full Custom Kernel + Root + Stealth + Wi-Fi | Vibranium-based EvilTwin GKI 6.1 `Image` (with latest KernelSU-Next & SuSFS) + Patched `qca_cld3_qca6750.ko` |
| **`Universal-EvilTwin-WiFi-Magisk-v1.0.zip`** | Any Stock or Custom Kernel (Magisk / KSU / APatch) | Standalone self-patching `qca_cld3_qca6750.ko` + `post-fs-data.sh` vermagic patcher + `/system/bin/wlan-mode` CLI |

---
## 🛠 Stack Architecture

| Component | Version / Source | Role |
| :--- | :--- | :--- |
| **Base Kernel** | Vibranium GKI `android14-6.1` (`peridot` / SM8635) | Core kernel with `CFG80211=m`, `MAC80211=m`, 250Hz & Full LTO |
| **WLAN Driver** | [`qcacld-3.0`](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635) (`qca_cld3_qca6750.ko`) | Patched out-of-tree Wi-Fi driver with Monitor Mode & Raw RX/TX |
| **Root Manager** | [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) *(Auto-Synced Latest Release)* | Kernel-based root with dynamic weak-symbol sucompat hooks |
| **Stealth Engine** | [SuSFS](https://gitlab.com/simonpunk/susfs4ksu) (`gki-android14-6.1` Latest) | VFS path/mount hiding, kstat, uname & cmdline/bootconfig spoofing |
| **Toolchain** | Neutron Clang `23.0.0git` | Full LLVM/LLD + Full Clang LTO & CFI compilation |

---
## 🚀 Installation Guide
### Option A: Universal Magisk / KernelSU Module (Keep Your Current Kernel)
1. Download **`Universal-EvilTwin-WiFi-Magisk-v1.0.zip`** from [Releases](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases/latest).
2. Open **Magisk**, **KernelSU / KernelSU-Next**, or **APatch** Manager → **Modules** → **Install from storage**.
3. Select the ZIP and reboot your device.
4. On boot, `post-fs-data.sh` automatically binary-patches the Wi-Fi module's `vermagic` to match your active `uname -r`.
### Option B: Full EvilTwin Kernel + Wi-Fi Bundle (AnyKernel3)
> **Prerequisites:** Unlocked Bootloader on POCO F6 / Redmi Turbo 3 (`peridot`), **KernelSU-Next Manager** installed, and a backup of your stock `boot.img`.
1. Download **`EvilTwin-ksun-susfs-v1.0-*.zip`** from [Releases](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases/latest).
2. Flash the ZIP using **Horizon Kernel Flasher**, **Franco Kernel Manager**, or **Custom Recovery** (OrangeFox / TWRP).
3. Reboot System.
### Option C: Fastboot (Raw Kernel Image Only)
```bash
fastboot flash boot boot.img
fastboot reboot
```
---
## 🔧 Usage & Monitor Mode Commands
### 1. Using the Built-In `wlan-mode` CLI (Universal Module Users)
Open Termux, Kali NetHunter, or an ADB shell and run:
```bash
# Enable Monitor Mode (con_mode=4) and optionally lock to channel 6
su -c "wlan-mode mon 6"
# Restore Normal Android Wi-Fi (Station Mode, con_mode=0)
su -c "wlan-mode sta"
```
### 2. Manual Sysfs Toggle (AnyKernel3 / Custom Script Users)
```bash
# Enable Monitor Mode (con_mode = 4)
su -c "svc wifi disable && ip link set wlan0 down && echo 4 > /sys/module/qca_cld3_qca6750/parameters/con_mode && ip link set wlan0 up"
# Return to Normal Managed / Station Mode (con_mode = 0)
su -c "ip link set wlan0 down && echo 0 > /sys/module/qca_cld3_qca6750/parameters/con_mode && svc wifi enable"
```
### 3. Verify Installation & Driver Load State
```bash
# Check active kernel version
uname -r
# Verify patched Wi-Fi module is bind-mounted and loaded
su -c "lsmod | grep qca_cld3_qca6750"
su -c "mount | grep qca_cld3_qca6750"
# Check SuSFS initialization in kernel ring buffer (Full Kernel Variant)
su -c "dmesg | grep -i susfs"
```
---
## 🎯 Offensive Security & Auditing Ecosystem

| Auditing Suite / Vector | Supported Operations | Interface / Requirement |
| :--- | :--- | :--- |
| **Kali NetHunter / Termux Chroot** | Full 802.11 wireless auditing, frame capture & custom packet crafting | `wlan0` (`con_mode=4`) |
| **Aircrack-ng Suite** | `airodump-ng` passive beacon/handshake capture & `aireplay-ng` testing | Radiotap RX / TX hooks |
| **HCXTools (`hcxdumptool`)** | PMKID & EAPOL 4-way handshake harvesting | Raw 802.11 frame RX |
| **Bettercap & Wifite2** | Automated wireless reconnaissance & rogue AP / Evil Twin simulations | `CFG80211` / `MAC80211` stack |
| **Wireshark / `tcpdump`** | Live 802.11 management, control & data frame dissection | `wlan0` Promiscuous / Monitor |

---
## ☕ Support My Work
If you find my projects or builds helpful, consider buying me a coffee to support future updates and development!
<p align="left">
  <a href="https://buymeacoffee.com/raju_yeager" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" height="50" width="180">
  </a>
</p>
---
<div align="center">
  🛡️ <b>EVILTWIN SECURITY RESEARCH // END OF FILE</b> 🛡️
  <br /><br />
  <table>
    <tr>
      <td align="center"><b>🔐 Root & Stealth</b><br /><sub>KernelSU-Next (Latest) + SuSFS</sub></td>
      <td align="center"><b>📡 Wireless Stack</b><br /><sub>QCA6750 Monitor Mode + Raw TX</sub></td>
      <td align="center"><b>🧩 Universal Module</b><br /><sub>Auto-Vermagic Patching · Any Kernel</sub></td>
      <td align="center"><b>⚙️ Build Pipeline</b><br /><sub>Automated CI · Neutron Clang 23</sub></td>
    </tr>
  </table>
  <p>
    <b>Built for the Offensive Security & Hardware Research Community.</b><br />
    <sub><i>Authorized penetration testing and educational research only. Contributions, bug reports, and pull requests are welcome.</i></sub>
  </p>
</div>
