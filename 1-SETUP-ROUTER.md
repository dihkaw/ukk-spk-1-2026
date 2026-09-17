# Tutorial Konfigurasi Router MikroTik CHR via WinBox
## UKK TKJ 2026 — SPK Paket 1

Tutorial ini menggunakan **WinBox versi terbaru** (v3.x / v4.x) untuk mengkonfigurasi **VM Router MikroTik (CHR)** sesuai topologi SPK Paket 1.

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

1. Download **WinBox terbaru** dari situs resmi MikroTik: `https://mikrotik.com/download`
2. Buka WinBox, pada tab **Neighbors** klik **Refresh** untuk mendeteksi VM Router CHR.
3. Klik pada MAC Address router yang muncul → klik **Connect** (login default: `admin`, password kosong).
4. Setelah masuk, disarankan langsung reset konfigurasi default agar bersih:
   - Menu **System → Reset Configuration** → centang **No Default Configuration** → klik **Reset Configuration**.
   - Winbox akan terputus, sambungkan ulang via MAC Address.

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

Buka menu **IP → Firewall → tab Filter Rules**. Tambahkan rule secara **berurutan** (urutan sangat penting — firewall MikroTik memproses rule dari atas ke bawah / top-down!):

### a. Izinkan VLAN 30 akses ke VLAN 10 (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.30.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `accept`

```
/ip firewall filter add chain=forward src-address=192.168.30.0/24 dst-address=192.168.10.0/24 action=accept comment="Izinkan VLAN30 ke VLAN10"
```

### b. Log percobaan VLAN 20 ke VLAN 10 (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `log`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=log log-prefix="BLOCKED-VLAN20: " comment="Log percobaan VLAN20 ke VLAN10"
```

> Rule `log` tidak menghentikan proses (tetap lanjut ke rule berikutnya), jadi harus diletakkan **sebelum** rule drop terkait.

### c. Blok VLAN 20 akses ke VLAN 10 (chain: forward)
- **Chain**: `forward`
- **Src. Address**: `192.168.20.0/24`
- **Dst. Address**: `192.168.10.0/24`
- **Action**: `drop`

```
/ip firewall filter add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 action=drop comment="Blok VLAN20 ke VLAN10"
```

> ⚠️ Urutan a → b → c di atas **wajib** seperti ini: accept VLAN30 duluan, baru log, baru drop VLAN20. Karena keduanya beda subnet source, urutan antar rule VLAN30 dan VLAN20 sebenarnya tidak saling mempengaruhi, tapi tetap disusun begini agar konsisten dan mudah dibaca top-down.

---

### d. Izinkan Akses SSH/Winbox dari VLAN 10 & VLAN 30 (chain: input) — **HARUS PALING ATAS**

⚠️ **Penting:** rule ini **wajib diletakkan paling atas** di chain `input`, **sebelum** rule logging dan mekanisme anti brute-force di bawah. Alasannya: kalau diletakkan di bawah, setiap kali admin dari VLAN10/VLAN30 melakukan reconnect Winbox berkali-kali (hal yang wajar terjadi saat sesi Winbox putus-nyambung), IP admin tersebut akan ikut tercatat naik bertahap oleh sistem staging (stage1 → stage2 → stage3 → **blacklist**) dan akhirnya **admin sendiri bisa terkunci** dari router. Dengan meletakkan rule accept ini paling atas, trafik dari VLAN10/VLAN30 langsung diterima tanpa pernah masuk ke sistem staging/blacklist sama sekali — mekanisme brute-force hanya akan menyaring percobaan dari VLAN20 atau sumber luar yang tidak sah.

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.10.0/24 action=accept comment="Izinkan akses VLAN10 ke router"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.30.0/24 action=accept comment="Izinkan akses VLAN30 ke router"
```

> 💡 Tidak perlu memakai opsi `place-before` — cukup **tambahkan rule ini duluan** (sebelum rule logging/staging di langkah e & f), karena `/ip firewall filter add` otomatis menaruh rule baru di baris paling bawah sesuai urutan penambahan. `place-before` justru berisiko salah, karena penomoran index di firewall MikroTik bersifat **global** (lintas semua chain), bukan khusus per-chain.

⚠️ **Uji dulu sebelum logout!** Pastikan kamu masih terkoneksi dari VLAN 10 atau VLAN 30 (atau Ether3 Host-Only) sebelum melanjutkan ke rule drop di bagian f — kalau salah urutan, kamu bisa terkunci dari router.

### e. Logging Percobaan Akses SSH/Winbox (chain: input)

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 action=log log-prefix="LOGIN-ATTEMPT: " comment="Log percobaan akses SSH/Winbox"
```

Untuk melihat log: menu **Log** di WinBox, atau via terminal:
```
/log print
```

### f. Amankan Brute-Force Login (chain: input)
Buat rule berurutan untuk mendeteksi & blok percobaan login berulang dari sumber yang **belum** diterima oleh rule accept VLAN10/30 di atas:

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_blacklist action=drop comment="Drop brute force SSH/Winbox"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage3 action=add-src-to-address-list address-list=ssh_blacklist address-list-timeout=1d comment="Stage 3 to blacklist"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage2 action=add-src-to-address-list address-list=ssh_stage3 address-list-timeout=1m comment="Stage 2 to stage3"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new src-address-list=ssh_stage1 action=add-src-to-address-list address-list=ssh_stage2 address-list-timeout=1m comment="Stage 1 to stage2"

/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 connection-state=new action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m comment="New connection attempt"
```

**Cara kerja:** setiap percobaan koneksi baru ke port SSH (22) atau Winbox (8291) **yang tidak berasal dari VLAN10/VLAN30** (karena sudah di-accept duluan di rule d) akan dicatat bertahap (stage1 → stage2 → stage3). Jika IP yang sama mencoba lagi dalam rentang waktu singkat, IP tersebut otomatis masuk **blacklist** dan diblokir selama 1 hari.

> 💡 **Catatan:** address-list (`ssh_stage1`, `ssh_stage2`, `ssh_stage3`, `ssh_blacklist`) **tidak perlu dibuat manual** di menu Address Lists. RouterOS otomatis membuatnya begitu ada traffic yang men-trigger action `add-src-to-address-list` pertama kali. Jadi wajar kalau menu **IP → Firewall → Address Lists** masih kosong sebelum ada percobaan koneksi.

### g. Blok Semua Akses SSH/Winbox Selain VLAN 10 & VLAN 30 (chain: input) — paling bawah

Rule penutup (catch-all) di bagian paling bawah chain input untuk port SSH/Winbox:

```
/ip firewall filter add chain=input protocol=tcp dst-port=22,8291 action=drop comment="Blok akses SSH/Winbox selain VLAN10 & VLAN30"
```

### 📌 Urutan Akhir Chain Input (SSH/Winbox) — Ringkasan

| # | Rule | Alasan urutan |
|---|---|---|
| 1 | Accept VLAN10 → router | Wajib paling atas, hindari admin ikut ter-blacklist saat reconnect |
| 2 | Accept VLAN30 → router | Sama seperti di atas |
| 3 | Log percobaan akses SSH/Winbox | Mencatat sisa traffic yang bukan dari VLAN10/30 |
| 4 | Drop jika src di `ssh_blacklist` | Traffic yang sudah lolos ke titik ini otomatis bukan dari VLAN10/30 |
| 5 | Stage3 → blacklist | Eskalasi bertahap |
| 6 | Stage2 → stage3 | Eskalasi bertahap |
| 7 | Stage1 → stage2 | Eskalasi bertahap |
| 8 | New connection → stage1 | Awal pencatatan percobaan baru |
| 9 | Drop semua sisanya (catch-all) | Penutup, blok semua yang tidak match rule di atas |

---

## ✅ 9️⃣ Verifikasi

Cek semua konfigurasi berjalan dengan baik:

```
/interface vlan print          → pastikan vlan10, vlan20, vlan30 aktif
/ip address print              → pastikan IP tiap VLAN sudah benar
/ip dhcp-server print          → pastikan DHCP vlan10 & vlan20 running
/ip firewall filter print      → cek urutan rule firewall (pastikan urutan sesuai tabel di atas)
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

**Selanjutnya:** lanjut ke [`2-setup-switch.md`](./2-setup-switch.md) untuk konfigurasi VM Switch MikroTik (CHR).
