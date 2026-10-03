# PRD: Optimasi Performa, Perbaikan Bug & Re-Branding OrangeFox Recovery (POCO F4 GT / ingres)

## 1. Ringkasan Eksekutif (Executive Summary)
Dokumen ini merupakan **Product Requirements Document (PRD)** untuk perbaikan dan penyempurnaan pohon perangkat (*device tree*) **OrangeFox Recovery** untuk perangkat **POCO F4 GT / Redmi K50 Gaming** (codename: `ingres`, SoC: Snapdragon 8 Gen 1 / SM8450).

Tujuan utama dari iterasi ini adalah:
1. Mengatasi masalah **lag / patah-patah parah** saat recovery berjalan.
2. Mematikan fitur **getar (vibration / haptics)** secara tuntas.
3. Mengatur tingkat **kecerahan default ke 35%**.
4. Membersihkan seluruh identitas/nama lama (`bladee`, `cupid`) agar repositori menjadi milik `Bymeopen` secara bersih (*clean state*).
5. Memastikan stabilitas tanpa merusak fungsionalitas yang sudah bekerja (seperti dekripsi `/data` dan driver touch panel).

---

## 2. Analisis Akar Masalah (Root Cause Analysis - RCA)

### A. Penyebab Lag / Patah-Patah Parah pada POCO F4 GT
Berdasarkan audit mendalam terhadap seluruh berkas konfigurasi di repositori, ditemukan **5 faktor utama** penyebab lag ekstrem:

1. **Kernel Debugging Overhead & Virtual Framebuffer pada `BOARD_KERNEL_CMDLINE`:**
   * Pada [BoardConfig.mk](file:///workspace/orange-fox-ingres/BoardConfig.mk#L145-L147), terdapat parameter:
     `video=vfb:640x400,bpp=32,memsize=3072000`
     `console=tty0 earlyprintk=fb printk.devkmsg=on ignore_loglevel`
   * **Dampak:** Parameter ini mendaftarkan framebuffer virtual 640x400 pada layar fisik 1080x2400 dan memaksa setiap baris log kernel (`printk`) dituliskan secara sinkron langsung ke layar (*framebuffer console*). MinUI / Surface rendering OrangeFox harus berebut framebuffer dengan output konsol teks tty0, yang mengakibatkan framerate anjlok drastis (hingga 1–5 FPS) dan stuttering parah.

2. **Kesalahan Sintaks Quoting pada `TARGET_RECOVERY_PIXEL_FORMAT`:**
   * Di [BoardConfig.mk](file:///workspace/orange-fox-ingres/BoardConfig.mk#L184):
     `TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"` (menggunakan tanda kutip dua).
   * **Dampak:** Pada sistem build Android AOSP / TWRP (`minui/Android.mk`), pengecekan dilakukan dengan:
     `ifeq ($(TARGET_RECOVERY_PIXEL_FORMAT),RGBX_8888)`
     Karena nilai variabel memiliki tanda kutip literal, kondisi ini bernilai *false*, sehingga minui tidak mengaktifkan pipeline grafis native RGBX hardware dan jatuh ke konversi format piksel software (*software color conversion* CPU-heavy) setiap kali frame dirender.

3. **CPU Terjebak di Frekuensi Terendah (Tanpa Scaling Governor):**
   * Chipset Snapdragon 8 Gen 1 (SM8450) memiliki 8 core (4 Little Cortex-A510, 3 Big Cortex-A710, 1 Prime Cortex-X2).
   * Di [recovery/root/init.recovery.qcom.rc](file:///workspace/orange-fox-ingres/recovery/root/init.recovery.qcom.rc), tidak ada inisialisasi CPU governor. Secara default, kernel recovery berjalan pada mode hemat daya terendah (300 MHz pada core Little) dan core Big/Prime dimatikan (*offline*).
   * **Dampak:** Render UI software pada layar FHD+ 120Hz membutuhkan siklus CPU yang memadai. Jika berjalan di 300 MHz pada 1 core, navigasi layar akan terasa sangat lambat dan delayed.

4. **Crash Loop & Blocking I/O pada Layanan Vibrator AIDL:**
   * Di [BoardConfig.mk](file:///workspace/orange-fox-ingres/BoardConfig.mk#L234-L236), aktif:
     `TW_SUPPORT_INPUT_AIDL_HAPTICS := true`
     `TW_SUPPORT_INPUT_AIDL_HAPTICS_FQNAME := "IVibrator/vibratorfeature"`
   * Di [recovery/root/vendor/etc/init/vendor.xiaomi.hardware.vibratorfeature.service.rc](file:///workspace/orange-fox-ingres/recovery/root/vendor/etc/init/vendor.xiaomi.hardware.vibratorfeature.service.rc), layanan `vibratorfeature-hal-service` dijalankan saat boot.
   * **Dampak:** Driver haptik Xiaomi memerlukan konfigurasi i2c/audio routing yang di recovery belum tentu siap. Jika layanan ini crash-loop, init akan terus-menerus me-restart proses tersebut (memakan CPU 100%). Selain itu, setiap event sentuhan layar memanggil Binder AIDL ke vibrator service yang hang, sehingga setiap sentuhan mengalami *input lag*.

5. **Resolusi dan Skala Layar yang Belum Didefinisikan Secara Presisi:**
   * Di `vendorsetup.sh`, variabel `OF_SCREEN_H=2400` belum didefinisikan (masih default 1920).
   * Di `BoardConfig.mk`, `TARGET_SCREEN_WIDTH` dan `TARGET_SCREEN_HEIGHT` belum dideklarasikan secara eksplisit.
   * **Dampak:** OrangeFox melakukan kalkulasi scaling dinamis yang membebani GPU/CPU software rendering.

---

### B. Analisis Kecerahan (Brightness)
* Nilai maksimum saat ini: `TW_MAX_BRIGHTNESS := 2047`.
* Nilai default saat ini: `TW_DEFAULT_BRIGHTNESS := 1024` (50%).
* Nilai 35% yang diinginkan: `round(2047 * 0.35) = 716`.
* Di `init.recovery.qcom.rc`, nilai hardcoded saat ini adalah `200` (terlalu redup di awal sebelum GUI mengambil alih). Perlu diselaraskan menjadi `716`.

---

### C. Analisis Identitas Lama (De-branding / Pembersihan Nama)
Ditemukan jejak author lama dan nama perangkat rujukan:
1. `vendorsetup.sh`: `export OF_MAINTAINER="bladee"`
2. Git Commits: author `bladee <131528761+MrMatiaas@users.noreply.github.com>` & `poveresmatias@gmail.com`
3. `BoardConfig.mk` & `README.md`: Referensi ke `cupid` (Xiaomi 12) dan scaffold lama.
4. `init.recovery.qcom.rc`: Komentar referensi ke `cupid`.
5. `init.recovery.usb.rc`: Baris residu Asus (`ro.vendor.asus.product.mkt_name`).

---

## 3. Rencana Solusi & Perubahan Teknis (Technical Solution Plan)

### Modul 1: Mengatasi Lag & Optimasi Performa UI
1. **Bersihkan `BOARD_KERNEL_CMDLINE`:**
   * Hapus `video=vfb:640x400,bpp=32,memsize=3072000`.
   * Hapus `console=tty0`, `earlyprintk=fb`, `printk.devkmsg=on`, `ignore_loglevel`.
   * Pertahankan konfigurasi serial & selinux standar:
     `console=ttyMSM0,115200n8 earlycon msm_geni_serial.con_enabled=1 androidboot.selinux=permissive`
2. **Koreksi `TARGET_RECOVERY_PIXEL_FORMAT`:**
   * Ganti `TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"` menjadi `TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888`.
3. **Konfigurasi CPU Performance Governor saat Recovery Boot:**
   * Tambahkan perintah init di `init.recovery.qcom.rc`:
     * Bawa core CPU 0–7 ke status `online 1`.
     * Atur scaling governor ke `schedutil` (atau `performance` untuk responsivitas instan).
4. **Deklarasikan Resolusi Layar Penuh POCO F4 GT:**
   * Di `BoardConfig.mk`:
     `TARGET_SCREEN_WIDTH := 1080`
     `TARGET_SCREEN_HEIGHT := 2400`
   * Di `vendorsetup.sh`:
     `export OF_SCREEN_H=2400`
     `export OF_STATUS_INDENT_LEFT=48`
     `export OF_STATUS_INDENT_RIGHT=48`
5. **Hapus Ghost Service Trigger:**
   * Hapus `start touch_report` dan `start touchsensor` dari `init.recovery.qcom.rc` karena binary tersebut tidak ada di ramdisk.

---

### Modul 2: Menonaktifkan Getar (Disable Vibration / Haptics)
1. **Nonaktifkan Haptics di Build Flag:**
   * Di `BoardConfig.mk`, hapus:
     `TW_SUPPORT_INPUT_AIDL_HAPTICS := true`
     `TW_SUPPORT_INPUT_AIDL_HAPTICS_FQNAME := "IVibrator/vibratorfeature"`
   * Tambahkan:
     `TW_NO_HAPTICS := true`
2. **Matikan Service Vibrator Feature:**
   * Di `recovery/root/vendor/etc/init/vendor.xiaomi.hardware.vibratorfeature.service.rc`, nonaktifkan `start vibratorfeature-hal-service` dan tandai servicenya sebagai `disabled`.
   * Ini memastikan tidak ada background process getar yang berjalan atau crash-loop.

---

### Modul 3: Kalibrasi Kecerahan ke 35%
1. Di `BoardConfig.mk`:
   * `TW_BRIGHTNESS_PATH := /sys/class/backlight/panel0-backlight/brightness`
   * `TW_MAX_BRIGHTNESS := 2047`
   * `TW_DEFAULT_BRIGHTNESS := 716`  *(35% dari 2047)*
2. Di `init.recovery.qcom.rc`:
   * `write /sys/class/backlight/panel0-backlight/brightness 716`

---

### Modul 4: Pembersihan Identitas Lama & Kepemilikan Repositori
1. **Pembaruan Konfigurasi Maintainer:**
   * Di `vendorsetup.sh`: Ganti `OF_MAINTAINER="bladee"` menjadi `OF_MAINTAINER="Bymeopen"`.
2. **Pembersihan Komentar Kode:**
   * Hapus seluruh sebutan `cupid` dan `bladee` pada `BoardConfig.mk`, `init.recovery.qcom.rc`, `init.recovery.usb.rc`, dan `README.md`.
3. **Pilihan Penanganan Riwayat Git (Git History):**
   * **Opsi A (Paling Bersih - Disarankan):** Squash / reset riwayat git lokal menjadi 1 initial commit bersih atas nama `Bymeopen <byme.openwrt@gmail.com>`. Seluruh histori commit `bladee` akan hilang sepenuhnya.
   * **Opsi B:** Pertahankan commit history yang ada, dan buat commit baru berisi perubahan optimasi ini atas nama `Bymeopen`.

---

## 4. Matriks Berkas yang Terdampak (Affected Files)

| File | Tindakan & Perubahan Utama |
| :--- | :--- |
| [`BoardConfig.mk`](file:///workspace/orange-fox-ingres/BoardConfig.mk) | Hapus vfb/earlyprintk dari cmdline; perbaiki quotes `RGBX_8888`; tambah resolusi 1080x2400; set `TW_DEFAULT_BRIGHTNESS := 716`; ganti haptics dengan `TW_NO_HAPTICS := true`; bersihkan komentar `cupid`. |
| [`vendorsetup.sh`](file:///workspace/orange-fox-ingres/vendorsetup.sh) | Set `OF_MAINTAINER="Bymeopen"`; tambah `OF_SCREEN_H=2400` dan indent padding. |
| [`recovery/root/init.recovery.qcom.rc`](file:///workspace/orange-fox-ingres/recovery/root/init.recovery.qcom.rc) | Set kecerahan 716; tambah scaling governor CPU `schedutil` & online cores; hapus ghost service `touch_report`/`touchsensor`. |
| [`recovery/root/vendor/etc/init/vendor.xiaomi.hardware.vibratorfeature.service.rc`](file:///workspace/orange-fox-ingres/recovery/root/vendor/etc/init/vendor.xiaomi.hardware.vibratorfeature.service.rc) | Nonaktifkan service start vibrator agar tidak membebani sistem. |
| [`recovery/root/init.recovery.usb.rc`](file:///workspace/orange-fox-ingres/recovery/root/init.recovery.usb.rc) | Bersihkan residu properti Asus. |
| [`README.md`](file:///workspace/orange-fox-ingres/README.md) | Perbarui dokumentasi resmi POCO F4 GT tanpa referensi ke perangkat/author lain. |
