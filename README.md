# Device tree for Redmi K50 Gaming Edition / POCO F4 GT (codename ingres)

Scaffolded from a sibling sm8450/taro OrangeFox device tree (Xiaomi 12 "cupid") and adapted
for ingres. This is a from-scratch port: it has NOT been validated against a real device yet.

## Device specifications

| Device                  | Redmi K50 Gaming Edition / POCO F4 GT                          |
| ----------------------- | :-------------------------------------------------------------- |
| SoC                     | Qualcomm SM8450 Snapdragon 8 Gen 1 (4 nm)                        |
| CPU                     | Octa-core (1x3.00 GHz Cortex-X2 & 3x2.50 GHz Cortex-A710 & 4x1.80 GHz Cortex-A510) |
| GPU                     | Adreno 730                                                       |
| Shipped Android Version | 12 (MIUI 13)                                                     |
| Partition layout        | A/B, separate vendor_boot, dedicated recovery partition          |
| Kernel                  | Not built from source; uses a prebuilt Image extracted from the device's own boot/vendor_boot |
| SELinux                 | Permissive (no custom sepolicy rules)                            |

## Status / known gaps

Validated on a real unlocked ingres unit (bootloader unlocked, `fastboot getvar product` = `ingres`).
Boots to the OrangeFox UI, adbd works, `recovery_a`/`recovery_b` partition sizes matched real
hardware (0x6400000) with no changes needed.

Confirmed working:
- [x] Boots and displays UI (sdcard visible)
- [x] adbd
- [x] Haptic motor firmware (`aw8697_haptic.bin`, real ingres file bundled in
      `recovery/root/vendor/firmware/` — the ramdisk copy is required because OrangeFox does not
      mount the real `/vendor` partition early enough for the kernel's `request_firmware()` call;
      confirmed via dmesg: `awinic_haptic ...: loaded aw8697_haptic.bin`)
- [x] Notification LED firmware (`aw22xxx_fw.bin`, same mechanism/fix)
- [x] **Touch**. Root cause (found by diffing a rooted normal-boot `dmesg` against recovery's):
      ingres's real touch panel is STMicro FTS over SPI (`fts_touch_spi.ko` + its `xiaomi_touch.ko`
      dependency), loaded via `modprobe` from `/vendor/lib/modules/` at normal boot — NOT
      goodix/novatek/synaptics (those bus drivers register in both normal and recovery boot but
      never bind; they're just other-SKU drivers bundled by Xiaomi in the same kernel image).
      `fts_touch_spi.ko`/`xiaomi_touch.ko` are not part of the base vendor_boot module set recovery
      boots with, so they never load automatically. Fix: pulled the real `.ko` files (matching this
      exact kernel, `5.10.209-android12-9-00019-...`) from the device's own `/vendor/lib/modules/`
      into `recovery/root/vendor/lib/modules/1.1/`, and set `TW_LOAD_VENDOR_MODULES` in
      `BoardConfig.mk` — this is required to even compile in OrangeFox's own userspace vendor-module
      loader (`kernel_module_loader.cpp`, gated behind `#ifdef TW_LOAD_VENDOR_MODULES`), which is
      the thing that actually picks modules up from that `1.1/` directory and sets
      `twrp.modules.loaded=true`. Confirmed via `/tmp/recovery.log`: `Modules Loaded: 2`, and a real
      `"fts"` input device now shows up with full `ABS_MT_*` touch axes.
- [x] **Battery**. Root cause: the PMIC battery/charger driver (`qti_battery_charger_main_m81.ko`)
      is hosted on the ADSP coprocessor via PMIC glink, so it only registers a `power_supply` once
      the ADSP remoteproc is actually booted. In normal boot this is triggered by a vendor-only
      service (`/vendor/bin/init.qti.write.sh /sys/kernel/boot_adsp/boot 1`, backed by a sysfs node
      that a vendor init script/driver creates — not present in recovery's ramdisk). cupid's original
      `init.recovery.qcom.rc` waited on that same non-existent path and silently timed out after 5s
      (visible in dmesg: `wait for '/sys/kernel/boot_adsp/boot' timed out`). Fix: replaced it with
      the standard Linux remoteproc control interface, `write /sys/class/remoteproc/remoteproc0/state
      start`, right after the existing `/firmware` (modem partition) mount — `adsp.mdt` and its
      segments get found through the same ueventd firmware-fallback search (`/firmware/image/...`)
      used for the haptic/LED fix above. Confirmed: `remote processor ... is now up` →
      `battery_chg_probe done` → `/sys/class/power_supply/battery/capacity` reads a real value (63).

Still open / unverified:
- [ ] `BoardConfig.mk` kernel load offsets (`BOARD_KERNEL_TAGS_OFFSET`, `BOARD_RAMDISK_OFFSET`)
      are still inherited from cupid and unverified (partition *sizes* were confirmed correct).
- [ ] `prebuilt/kernel` is an empty placeholder by design — this device boots recovery with the
      kernel supplied by the real `boot` partition (`BOARD_EXCLUDE_KERNEL_FROM_RECOVERY_IMAGE`),
      confirmed working on real hardware.
- [ ] No custom sepolicy is included on purpose (recovery runs permissive) — confirmed: an AVC
      denial on `/vendor/firmware/aw22xxx_fw.bin` was logged but did not block access
      (`permissive=1`).

## Compile

Sync OrangeFox sources and the fox_12.1 minimal manifest:

```
mkdir ~/orangefox && cd ~/orangefox
git clone https://gitlab.com/OrangeFox/sync.git
cd sync
./orangefox_sync.sh --branch 12.1 --path ~/orangefox/fox_12.1
```

Place this device tree at `device/xiaomi/ingres` inside that manifest directory, then:

```
cd ~/orangefox/fox_12.1
source build/envsetup.sh
export ALLOW_MISSING_DEPENDENCIES=true
export LC_ALL="C"

lunch twrp_ingres-eng
mka adbd recoveryimage
```

## To flash (once the prebuilt kernel and partition sizes above are corrected)

```
fastboot flash recovery out/target/product/ingres/OrangeFox-*.img
```
