# Tutorial Konfigurasi Switch MikroTik CHR via WinBox
## UKK TKJ 2026 — SPK Paket 1

Tutorial ini menggunakan **WinBox versi terbaru** (v3.x / v4.x) untuk mengkonfigurasi **VM Switch MikroTik (CHR)**, menggunakan metode **Bridge VLAN Filtering** (metode standar/terbaru RouterOS v7 untuk switching VLAN).

### Persiapkan VM CHR yang dapat didownload di https://mikrotik.com/download dan dijalankan dengan pengaturan spesifikasi RAM sebesar 128MB dan penambahan Network Interface menjadi 5:
- ether1: LAN Segment "Router-Switch"
- ether2: LAN Segment "Switch-Guru"
- ether3: LAN Segment "Switch-Siswa"
- ether4: LAN Segment "Switch-Server"
- ether5: Host Only
---

## 📋 Topologi Switch

| Interface | Fungsi | VLAN |
|---|---|---|
| Ether1 | Uplink ke Router | Trunk (tagged VLAN 10, 20, 30) |
| Ether2 | Ke Switch-Guru | Access — VLAN 10 |
| Ether3 | Ke Switch-Siswa | Access — VLAN 20 |
| Ether4 | Ke Server | Access — VLAN 30 |
| Ether5 | Management | Host Only — akses Winbox langsung dari PC Admin |

---

## 🔧 Persiapan

1. Buka WinBox → tab **Neighbors** → **Refresh**.
2. Klik MAC Address VM **Switch MikroTik CHR** → **Connect**.
3. Disarankan reset ke default dulu:
   - **System → Reset Configuration** → centang **No Default Configuration** → **Reset Configuration**.
   - Sambungkan ulang via MAC Address setelah reboot.
4. Buka menu **System  → Identity**.
5. Isi **Identity**: *switch-NamaAnda*
6. Klik **Apply → OK**.

---

## 1️⃣ Membuat Bridge

RouterOS CHR modern menggunakan satu **bridge** dengan **VLAN filtering** untuk mengatur trunk & access port — ini menggantikan cara lama (VLAN interface per port).

1. Buka menu **Bridge**.
2. Tab **Bridge** → klik **`+`** (Add):
   - **Name**: `bridge-switch`
   - Tab **VLAN**: centang **VLAN Filtering** — **JANGAN dicentang dulu**, aktifkan ini di langkah paling akhir (setelah semua port & VLAN diatur), supaya switch tidak "terkunci" saat konfigurasi berjalan.
3. Klik **Apply → OK**.

**Terminal equivalent:**
```
/interface bridge add name=bridge-switch
```

---

## 2️⃣ Menambahkan Semua Port ke Bridge

1. Buka tab **Ports** pada menu **Bridge**.
2. Klik **`+`** (Add) untuk setiap interface, masukkan ke `bridge-switch`:
   - `ether1` → Bridge: `bridge-switch`
   - `ether2` → Bridge: `bridge-switch`
   - `ether3` → Bridge: `bridge-switch`
   - `ether4` → Bridge: `bridge-switch`
   - `ether5` → Bridge: `bridge-switch` *(opsional — lihat catatan di bagian 6)*

**Terminal equivalent:**
```
/interface bridge port add bridge=bridge-switch interface=ether1
/interface bridge port add bridge=bridge-switch interface=ether2
/interface bridge port add bridge=bridge-switch interface=ether3
/interface bridge port add bridge=bridge-switch interface=ether4
```

---

## 3️⃣ Konfigurasi Trunk Port (Ether1 — ke Router)

Ether1 harus meneruskan **semua VLAN (tagged)** ke router.

1. Buka tab **VLAN** pada menu **Bridge**.
2. Klik **`+`** (Add):
   - **Bridge**: `bridge-switch`
   - **VLAN IDs**: `10`
   - **Tagged**: `ether1, bridge-switch`
   - **Untagged**: *(kosongkan)*
3. Ulangi untuk VLAN 20 dan 30, dengan **Tagged: ether1, bridge-switch** juga.

Jadi total ada 3 entri VLAN (10, 20, 30), dan `ether1` masuk sebagai **tagged** di ketiganya (karena ether1 adalah trunk).

**Terminal equivalent:**
```
/interface bridge vlan add bridge=bridge-switch vlan-ids=10 tagged=bridge-switch,ether1
/interface bridge vlan add bridge=bridge-switch vlan-ids=20 tagged=bridge-switch,ether1
/interface bridge vlan add bridge=bridge-switch vlan-ids=30 tagged=bridge-switch,ether1
```

---

## 4️⃣ Konfigurasi Access Port (Ether2, Ether3, Ether4)

Sekarang tambahkan tiap access port sebagai **untagged** di VLAN masing-masing. Edit ulang 3 entri VLAN yang sudah dibuat:

| VLAN ID | Tagged | Untagged |
|---|---|---|
| 10 | ether1, bridge-switch | **ether2** |
| 20 | ether1, bridge-switch | **ether3** |
| 30 | ether1, bridge-switch | **ether4** |

Caranya di WinBox: buka tab **VLAN**, double-klik entri VLAN 10 → isi kolom **Untagged**: `ether2` → Apply. Ulangi untuk VLAN 20 (`ether3`) dan VLAN 30 (`ether4`).

**Terminal equivalent (edit ulang entri sebelumnya):**
```
/interface bridge vlan set [find vlan-ids=10] untagged=ether2
/interface bridge vlan set [find vlan-ids=20] untagged=ether3
/interface bridge vlan set [find vlan-ids=30] untagged=ether4
```

---

## 5️⃣ Set PVID pada Access Port

Supaya trafik **masuk tanpa tag** dari perangkat (PC Guru/Siswa/Server) otomatis dianggap sebagai VLAN yang benar, set **PVID** di tiap access port.

1. Buka tab **Ports** pada menu **Bridge**.
2. Double-klik `ether2` → isi **PVID**: `10` → Apply.
3. Double-klik `ether3` → isi **PVID**: `20` → Apply.
4. Double-klik `ether4` → isi **PVID**: `30` → Apply.
5. `ether1` biarkan **PVID: 1** (default), karena ether1 murni trunk.

**Terminal equivalent:**
```
/interface bridge port set [find interface=ether2] pvid=10
/interface bridge port set [find interface=ether3] pvid=20
/interface bridge port set [find interface=ether4] pvid=30
```

---

## 6️⃣ Ether5 — Management Port (Host Only untuk WinBox)

Ether5 digunakan **khusus untuk akses langsung Winbox** dari PC Admin (Host-Only), terpisah dari jalur VLAN produksi — supaya switch tetap bisa diakses meskipun ada kesalahan konfigurasi VLAN.

**Opsi A (Direkomendasikan) — Ether5 di luar bridge VLAN:**
- **Jangan** masukkan `ether5` ke `bridge-switch`.
- Beri IP management langsung di `ether5`, contoh:

```
/ip address add address=192.168.100.1/24 interface=ether5
```

Lalu PC Admin (host-only) diset IP satu subnet, misalnya `192.168.100.2/24`, agar bisa Winbox langsung ke `192.168.100.1`.

**Opsi B — Ether5 ikut bridge tapi khusus VLAN management:**
Jika ingin tetap satu bridge, buat VLAN manajemen terpisah (misal VLAN 99) khusus untuk ether5, dan beri IP di interface VLAN tersebut. (Opsional, tidak wajib sesuai topologi dasar.)

> 💡 Gunakan **Opsi A** untuk kesederhanaan dan sesuai prinsip topologi (jalur Host-Only terpisah dari jalur data VLAN).

---

## 7️⃣ Aktifkan VLAN Filtering

Setelah **semua port dan VLAN selesai dikonfigurasi**, baru aktifkan VLAN filtering supaya bridge benar-benar memisahkan trafik antar-VLAN.

1. Buka menu **Bridge → tab Bridge**.
2. Double-klik `bridge-switch`.
3. Tab **VLAN**: centang **VLAN Filtering**.
4. Klik **Apply → OK**.

**Terminal equivalent:**
```
/interface bridge set bridge-switch vlan-filtering=yes
```

⚠️ **PENTING:** Setelah langkah ini diaktifkan, pastikan koneksi Winbox kamu tidak melalui port trunk/access biasa (gunakan Ether5/Host-Only) — karena jika salah konfigurasi, port trunk/access bisa langsung ter-filter dan memutus akses Winbox via jalur tersebut.

---

## ✅ 8️⃣ Verifikasi

```
/interface bridge print                  → pastikan bridge-switch aktif, vlan-filtering: yes
/interface bridge port print             → cek PVID tiap port sudah benar
/interface bridge vlan print             → cek tagged/untagged tiap VLAN ID
/interface bridge host print             → cek MAC address yang terdeteksi per VLAN
```

Uji dari sisi client:
- PC/Server yang terhubung ke **Ether2** otomatis masuk **VLAN 10** dan dapat DHCP dari Router (192.168.10.x) ✅
- PC yang terhubung ke **Ether3** otomatis masuk **VLAN 20** dan dapat DHCP (192.168.20.x) ✅
- Server yang terhubung ke **Ether4** berada di **VLAN 30** (192.168.30.10 static) ✅
- Trafik VLAN 10, 20, 30 saling terisolasi di level Layer 2 kecuali diizinkan firewall router ✅
- Winbox tetap bisa diakses via Ether5 (Host-Only) walau ada perubahan pada VLAN ✅

---

## 📌 Ringkasan Pemetaan Akhir

| Port | Bridge | PVID | Tagged | Untagged | Fungsi |
|---|---|---|---|---|---|
| Ether1 | bridge-switch | 1 | VLAN 10, 20, 30 | - | Trunk ke Router |
| Ether2 | bridge-switch | 10 | - | VLAN 10 | Ke Switch-Guru |
| Ether3 | bridge-switch | 20 | - | VLAN 20 | Ke Switch-Siswa |
| Ether4 | bridge-switch | 30 | - | VLAN 30 | Ke Server |
| Ether5 | *(luar bridge)* | - | - | - | Management Winbox (Host-Only) |

---

**Selanjutnya:** lanjut ke [`3-SETUP-SERVER.md`](./3-SETUP-SERVER.md) untuk konfigurasi VM Ubuntu.
