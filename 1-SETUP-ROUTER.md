# Tutorial Konfigurasi Router MikroTik CHR via WinBox
## UKK TKJ 2026 — SPK Paket 1

Tutorial ini menggunakan **WinBox versi terbaru** (v3.x / v4.x) untuk mengkonfigurasi **VM Router MikroTik (CHR)** sesuai topologi SPK Paket 1.

### Persiapkan VM CHR yang dapat di[download](https://download.mikrotik.com/routeros/7.23.2/chr-7.23.2.ova) di situs resmi MikroTik dan dijalankan dengan pengaturan spesifikasi RAM sebesar 128MB dan penambahan Network Interface menjadi 3 (ether1: NAT; ether2: LAN Segment "Router-Switch"; ether3: Host Only)
---

## 📋 Topologi Router

| Interface | Fungsi | Keterangan |
|---|---|---|
| Ether1 | WAN / Internet | DHCP Client (Use Peer DNS: **off**) |
| Ether2 | Trunk ke Switch | Membawa VLAN 10, 20, 30 |
| Ether3 | Management | Host Only — akses Winbox langsung dari PC Admin |

| VLAN | IP Gateway | Fungsi |
|---|---|---|
| VLAN 10 | 192.168.10.1/24 | Jaringan Guru |
| VLAN 20 | 192.168.20.1/24 | Jaringan Siswa |
| VLAN 30 | 192.168.30.1/24 | Jaringan Server |

---

## 🔧 Persiapan

1. [Download](https://download.mikrotik.com/routeros/winbox/3.43/winbox.exe) **WinBox terbaru** dari situs resmi MikroTik: `https://mikrotik.com/download`
2. Buka WinBox, pada tab **Neighbors** klik **Refresh** untuk mendeteksi VM Router CHR.
3. Klik pada MAC Address router yang muncul → klik **Connect** (login default: `admin`, password kosong).
4. Setelah masuk, disarankan langsung reset konfigurasi default agar bersih:
   - Menu **System → Reset Configuration** → centang **No Default Configuration** → klik **Reset Configuration**.
   - Winbox akan terputus, sambungkan ulang via MAC Address.
5. Buka menu **System  → Identity**.
6. Isi **Identity**: *router-NamaAnda*
7. Klik **Apply → OK**.

---

## 1️⃣ Konfigurasi Ether1 (DHCP Client / Internet)

1. Buka menu **IP → DHCP Client**.
2. Klik tombol **`+`** (Add).
3. Pada tab **General**:
   - **Interface**: `ether1`
   - **Use Peer DNS**: **hilangkan centang (off)** — sesuai requirement (DNS akan diarahkan manual ke server).
4. Klik **Apply → OK**.
5. Cek status DHCP Client, pastikan **Status: bound** dan mendapat IP dari internet/bridge.

**Terminal equivalent** (bisa dicek via New Terminal):
```
/ip dhcp-client add interface=ether1 use-peer-dns=no disabled=no
```

---

## 2️⃣ Konfigurasi DNS Server

1. Buka menu **IP → DNS**.
2. Pada kolom **Servers**, tambahkan:
   - `192.168.30.10` (DNS server internal)
   - `8.8.8.8` (DNS publik cadangan)
3. **JANGAN** centang "Allow Remote Requests" kecuali memang dibutuhkan sebagai DNS relay.
4. Klik **Apply → OK**.

**Terminal equivalent:**
```
/ip dns set servers=192.168.30.10,8.8.8.8
```

---

## 3️⃣ Aktifkan SNMP (untuk Monitoring)

Router akan dipantau oleh server monitoring (Netdata) via SNMP.

1. Buka menu **IP → SNMP**.
2. Centang **Enabled**.
3. Pada tab **Communities**, edit/tambah community:
   - **Name**: `public` (atau sesuaikan dengan yang dipakai di server monitoring)
   - **Addresses**: `192.168.30.10/32` (agar SNMP hanya bisa diakses dari server monitoring)
4. Klik **Apply → OK**.

**Terminal equivalent:**
```
/snmp set enabled=yes
/snmp community set [find default=yes] name=public addresses=192.168.30.10/32
```

⚠️ **Catatan:** community string ini **harus sama persis** dengan yang dikonfigurasi di script server (`SNMP_COMMUNITY` pada `setup-server.sh`).

---

## 4️⃣ Membuat VLAN 10, 20, 30 di atas Ether2 (Trunk)

1. Buka menu **Interfaces → VLAN**.
2. Klik **`+`** (Add) untuk masing-masing VLAN:

**VLAN 10:**
- **Name**: `vlan10`
- **VLAN ID**: `10`
- **Interface**: `ether2`

**VLAN 20:**
- **Name**: `vlan20`
- **VLAN ID**: `20`
- **Interface**: `ether2`

**VLAN 30:**
- **Name**: `vlan30`
- **VLAN ID**: `30`
- **Interface**: `ether2`

3. Klik **Apply → OK** untuk masing-masing.

**Terminal equivalent:**
```
/interface vlan add name=vlan10 vlan-id=10 interface=ether2
/interface vlan add name=vlan20 vlan-id=20 interface=ether2
/interface vlan add name=vlan30 vlan-id=30 interface=ether2
```

---

## 5️⃣ Pengalamatan IP Tiap VLAN

1. Buka menu **IP → Addresses**.
2. Klik **`+`** (Add) untuk masing-masing:

| Address | Network | Interface |
|---|---|---|
| 192.168.10.1/24 | 192.168.10.0 | vlan10 |
| 192.168.20.1/24 | 192.168.20.0 | vlan20 |
| 192.168.30.1/24 | 192.168.30.0 | vlan30 |

**Terminal equivalent:**
```
/ip address add address=192.168.10.1/24 interface=vlan10
/ip address add address=192.168.20.1/24 interface=vlan20
/ip address add address=192.168.30.1/24 interface=vlan30
```

---

## 6️⃣ DHCP Server untuk VLAN 10 dan VLAN 20

Gunakan **DHCP Setup Wizard** agar lebih cepat.

### DHCP Server VLAN 10 (Guru)
1. Buka menu **IP → DHCP Server → DHCP Setup**.
2. **DHCP Server Interface**: `vlan10` → Next
3. **DHCP Address Space**: `192.168.10.0/24` → Next
4. **Gateway for DHCP Network**: `192.168.10.1` → Next
5. **Addresses to Give Out**: `192.168.10.10-192.168.10.254` → Next
6. **DNS Servers**: `192.168.30.10, 8.8.8.8` → Next
7. **Lease Time**: default (`00:10:00` atau sesuaikan) → Next → **selesai**.

### DHCP Server VLAN 20 (Siswa)
Ulangi langkah yang sama dengan:
- Interface: `vlan20`
- Address Space: `192.168.20.0/24`
- Gateway: `192.168.20.1`
- Pool: `192.168.20.10-192.168.20.254`

**Terminal equivalent (ringkas, tanpa wizard):**
```
/ip pool add name=pool-vlan10 ranges=192.168.10.10-192.168.10.254
/ip dhcp-server add name=dhcp-vlan10 interface=vlan10 address-pool=pool-vlan10 disabled=no
/ip dhcp-server network add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.30.10,8.8.8.8

/ip pool add name=pool-vlan20 ranges=192.168.20.10-192.168.20.254
/ip dhcp-server add name=dhcp-vlan20 interface=vlan20 address-pool=pool-vlan20 disabled=no
/ip dhcp-server network add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=192.168.30.10,8.8.8.8
```

> Catatan: VLAN 30 (Server) **tidak perlu DHCP Server** karena server menggunakan IP static (192.168.30.10).

---

## 7️⃣ NAT Masquerade (Akses Internet)

1. Buka menu **IP → Firewall → tab NAT**.
2. Klik **`+`** (Add).
3. Tab **General**:
   - **Chain**: `srcnat`
   - **Out. Interface**: `ether1`
4. Tab **Action**:
   - **Action**: `masquerade`
5. Klik **Apply → OK**.

**Terminal equivalent:**
```
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade
```

---

## 8️⃣ Firewall Rules

Buka menu **IP → Firewall → tab Filter Rules**. Tambahkan rule secara **berurutan** (urutan penting!):

### a. Blok VLAN 20 akses ke VLAN 10
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `drop`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=drop comment="Blok VLAN20 ke VLAN10"
```

### b. Izinkan VLAN 30 akses ke VLAN 10
- **Chain**: `forward`
- **Src. Address**: `192.168.30.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `accept`

```
/ip firewall filter add chain=forward src-address=192.168.30.0/24 dst-address=192.168.10.0/24 action=accept comment="Izinkan VLAN30 ke VLAN10" place-before=0
```

> ⚠️ Pastikan rule **"Izinkan VLAN 30"** berada **di atas (place-before)** rule blok, atau tambahkan rule accept ini duluan sebelum rule drop VLAN20, supaya urutan eksekusi firewall benar (top-down).

### c. Amankan Brute-Force Login (SSH/Winbox)
Buat 3 rule berurutan untuk mendeteksi & blok percobaan login berulang:

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_blacklist action=drop comment="Drop brute force SSH/Winbox"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage3 action=add-src-to-address-list address-list=ssh_blacklist address-list-timeout=1d comment="Stage 3 to blacklist"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage2 action=add-src-to-address-list address-list=ssh_stage3 address-list-timeout=1m comment="Stage 2 to stage3"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage1 action=add-src-to-address-list address-list=ssh_stage2 address-list-timeout=1m comment="Stage 1 to stage2"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m comment="New connection attempt"
```

**Cara kerja:** setiap percobaan koneksi baru ke port SSH (22) atau Winbox (8291) akan dicatat bertahap (stage1 → stage2 → stage3). Jika IP yang sama mencoba lagi dalam rentang waktu singkat, IP tersebut otomatis masuk **blacklist** dan diblokir selama 1 hari.

### d. Logging Aktivitas Penting

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 action=log log-prefix="LOGIN-ATTEMPT: " comment="Log percobaan akses SSH/Winbox"

/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=log log-prefix="BLOCKED-VLAN20: " comment="Log percobaan VLAN20 ke VLAN10"
```

> Letakkan rule **log** ini **sebelum** rule drop/accept terkait, karena firewall MikroTik memproses top-down dan rule `log` tidak menghentikan proses (tetap lanjut ke rule berikutnya).

Untuk melihat log: menu **Log** di WinBox, atau via terminal:
```
/log print
```

### e. Amankan Akses Router — SSH/Winbox Hanya dari VLAN 10 & 30

Tambahkan rule berikut **di bagian bawah** (sebelum rule "drop all" jika ada), untuk membatasi siapa saja yang boleh mengakses router:

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.10.0/24 action=accept comment="Izinkan akses VLAN10 ke router"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.30.0/24 action=accept comment="Izinkan akses VLAN30 ke router"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 action=drop comment="Blok akses SSH/Winbox selain VLAN10 & VLAN30"
```

⚠️ **Uji dulu sebelum logout!** Pastikan kamu masih terkoneksi dari VLAN 10 atau VLAN 30 (atau Ether3 Host-Only) sebelum menerapkan rule terakhir ini — kalau salah, kamu bisa terkunci dari router.

---

## ✅ 9️⃣ Verifikasi

Cek semua konfigurasi berjalan dengan baik:

```
/interface vlan print          → pastikan vlan10, vlan20, vlan30 aktif
/ip address print              → pastikan IP tiap VLAN sudah benar
/ip dhcp-server print          → pastikan DHCP vlan10 & vlan20 running
/ip firewall filter print      → cek urutan rule firewall
/ip firewall nat print         → cek rule masquerade
/snmp print                    → pastikan SNMP enabled
/ping 8.8.8.8                  → tes koneksi internet dari router
```

Uji dari sisi client:
- PC di VLAN 20 (Siswa) **tidak bisa** ping ke VLAN 10 (Guru) ✅
- Server di VLAN 30 **bisa** ping ke VLAN 10 (Guru) ✅
- Client VLAN 10/20 mendapat IP otomatis dari DHCP ✅
- Winbox/SSH ke router dari VLAN 20 **ditolak**, dari VLAN 10/30 **berhasil** ✅

---

**Selanjutnya:** lanjut ke [`2-SETUP-SWITCH.md`](./2-SETUP-SWITCH.md) untuk konfigurasi VM Switch MikroTik (CHR).
