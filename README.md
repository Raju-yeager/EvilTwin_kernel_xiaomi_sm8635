<div align="center">
  <img src="assets/gemini-svg.svg" width="100%" alt="EvilTwin Kernel Banner" />

  # **EVILTWIN KERNEL // SM8635**
  *Offensive Security & Low-Level Wireless Auditing Engine for Xiaomi POCO F6 / Redmi Turbo 3 (`peridot`)*

  [![Release](https://img.shields.io/github/v/release/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635?color=00ff66&label=RELEASE&style=for-the-badge&logo=git&logoColor=black)](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases)
  [![GKI Version](https://img.shields.io/badge/GKI-6.1-black?color=00ff66&style=for-the-badge&logo=linux&logoColor=00ff66)](https://kernel.org)
  [![KSUN](https://img.shields.io/badge/KernelSU--Next-v3.3.0-00e5ff?style=for-the-badge&logo=android&logoColor=black)](https://github.com/KernelSU-Next/KernelSU-Next)
  [![SUSFS](https://img.shields.io/badge/SUSFS-v2.3.0-purple?style=for-the-badge&logo=shield)](https://gitlab.com/simonpunk/susfs4ksu)
  [![Toolchain](https://img.shields.io/badge/Neutron_Clang-23.0.0git-orange?style=for-the-badge&logo=llvm)](https://github.com/Neutron-Toolchains/clang-build-catalogue)
  [![Downloads](https://img.shields.io/github/downloads/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/total?color=00e5ff&label=DOWNLOADS&style=for-the-badge&logo=cloud-download)](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases)
  [![License](https://img.shields.io/badge/LICENSE-GPL--2.0-red?style=for-the-badge)](LICENSE)
</div>

---

> **⚠️ WARNING / DISCLAIMER**  
> **USE AT YOUR OWN RISK.** This custom kernel and wireless driver bundle is provided strictly for educational purposes, authorized wireless security auditing, and hardware research. Modifying kernel-level driver states can cause bootloops, thermal variance, or system instability. The developer assumes zero liability for bricked devices, voided warranties, or misuse.

---

## ⚡ Overview & Capabilities

**EvilTwin** is an offensive-security GKI 6.1 kernel and out-of-tree WLAN driver bundle engineered for Qualcomm SM8635 devices (`peridot`). While stock OEM kernels strip `mac80211` stacks, enforce module signature locks, and drop raw 802.11 frames in the datapath, EvilTwin pairs a customized GKI 6.1 kernel with a patched `qcacld-3.0` (`qca_cld3_qca6750.ko`) module in a **single unified flashable ZIP**.

* **Native Monitor Mode (`wlan0`):** Unlocks internal QCA6750 driver transport endpoints (`con_mode=4`) and disables `CONFIG_DP_RX_DROP_RAW_FRM`, converting the onboard Wi-Fi chip into a passive 802.11 packet listener without external USB OTG adapters.
* **Raw 802.11 Frame Injection:** Patches `ndo_start_xmit` and monitor TX hooks in `qcacld-3.0` to allow radiotap-encapsulated raw frame transmission.
* **Auto-Mounted Driver Delivery:** Flashing the AnyKernel3 ZIP automatically deploys `qca_cld3_qca6750.ko` to `/data/adb/eviltwin/` and registers a `post-fs-data.d` bind-mount hook over `/vendor_dlkm/lib/modules/qca_cld3_qca6750.ko` at boot.
* **KernelSU-Next + SuSFS v2.3.0:** Built-in kprobe root integration with kernel-level mount hiding (`sus_mount`), path hiding (`sus_path`), kstat spoofing (`sus_kstat`), `uname` spoofing, and SELinux AVC audit log suppression.
* **Relaxed Module Verification:** Bypasses `MODULE_SIG_FORCE` and symbol CRC mismatches so custom and vendor `.ko` modules load seamlessly across ROMs.

---

## 📥 Downloads

### [⬇ Download Latest EvilTwin Kernel + Wi-Fi Bundle](https://github.com/Raju-yeager/EvilTwin_kernel_xiaomi_sm8635/releases/latest)

---

## 🛠 Stack Architecture

| Component | Version / Source | Role |
| :--- | :--- | :--- |
| **Base Kernel** | GKI `android14-6.1` (`peridot` / SM8635) | Core kernel with `CFG80211` & `MAC80211` enabled |
| **WLAN Driver** | [`Eviltwin-drivers_kernel_xiaomi_sm8635-modules`](https://github.com/Raju-yeager/Eviltwin-drivers_kernel_xiaomi_sm8635-modules) | Patched `qca_cld3_qca6750.ko` (`lineage-23.2`) |
| **Root Manager** | [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next) `v3.3.0` | Kernel-based root with kprobe hooks |
| **Stealth Engine** | [SuSFS](https://gitlab.com/simonpunk/susfs4ksu) `v2.3.0` (`gki-android14-6.1`) | VFS path/mount hiding, kstat & cmdline spoofing |
| **Toolchain** | Neutron Clang `23.0.0git` (`30062026`) | Full LLVM/LLD + LTO compilation |

---

## 🚀 Installation Guide

### Prerequisites
* Unlocked Bootloader on POCO F6 / Redmi Turbo 3 (`peridot`).
* **KernelSU-Next Manager** installed.
* Backup of your stock `boot.img
