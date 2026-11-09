# LEMBAR LAPORAN PRAKTIK KEJURUAN (CONTOH TERISI)

**UKK TKJ | Paket 1 | KM25.4.2.1**

**Pembangunan Sistem Monitoring Jaringan dan Server Real-Time untuk Peningkatan Kinerja dan Keamanan Layanan Jaringan**

> Contoh isian acuan penguji untuk kombinasi: Debian 12, Apache2, BIND9, Cacti. Isian siswa boleh berbeda selama hasilnya benar dan sesuai soal. Tahun pelajaran dan tanggal sengaja dikosongkan.

| | | | |
|---|---|---|---|
| **No. Ujian** | TKJ-002 | **Nama** | Contoh Siswa |
| **Kelas** | XII TKJ 1 | **Tahun Pelajaran** | ____/____ |
| **OS Server / Web** | Debian 12 (Bookworm) / Apache2 | **DNS / Monitoring** | BIND9 / Cacti |
| **Router dan Switch** | MikroTik CHR, RouterOS 6.49.20 |  |  |

---

## L1. Topologi dan Inventaris Aset (dinilai: U2, U13, P15)

```
[ ZONA WAN / ISP ]                 [ ZONA JARINGAN SEKOLAH ]

  Internet --ether1-- ROUTER CHR --ether2 (trunk)-- SWITCH CHR
  (ISP, DHCP+NAT)     gateway, DHCP,                 |       |       |
                      firewall, SNMP               ether2  ether3  ether4
                                                     |       |       |
                                                 VLAN 10  VLAN 20  VLAN 30
                                                  Guru     Siswa    Server
                                              192.168.10.x 192.168.20.x 192.168.30.10

  Management Host-Only: Router ether3 - Switch ether5 - Server NIC 2 --> PC Host (Winbox / PuTTY)
```

*Gambar 1. Topologi jaringan: zona WAN/ISP terpisah dari jaringan sekolah, dan segmen Server (VLAN 30) terpisah dari segmen pengguna.*

Zona WAN/ISP (pihak ketiga) dipisahkan dari jaringan sekolah oleh Router. Segmen Server (VLAN 30) dipisahkan dari segmen pengguna (VLAN 10 dan 20) oleh firewall Router.

| No | Aset | IP / VLAN | OS / versi | Layanan | Penting | Kelemahan / risiko |
|---|---|---|---|---|---|---|
| 1 | Router | 192.168.10.1, .20.1, .30.1 | RouterOS 6.49.20 | Gateway, DHCP, NAT, firewall, SNMP | T | Brute-force login |
| 2 | Switch | VLAN 10/20/30; manajemen 192.168.100.1 (Host-Only) | RouterOS 6.49.20 | Segmentasi VLAN | T | Salah PVID, VLAN bocor |
| 3 | Server | 192.168.30.10 (VLAN 30); NIC 2 Host-Only (DHCP) | Debian 12 | DNS (BIND9), Web (Apache2), Monitoring (Cacti + MariaDB + SNMP) | T | Layanan down, recursion DNS terbuka, password default Cacti |
| 4 | Klien Guru | DHCP 192.168.10.x | Windows 7 | Pekerjaan guru/admin | S | OS tidak didukung |
| 5 | Klien Siswa | DHCP 192.168.20.x | Windows 7 | Praktik siswa | R | Malware, OS usang |

> T = Tinggi, S = Sedang, R = Rendah. Router dan server adalah aset kritis.

---

## L2. Hasil Pengujian (dinilai: U10)

| No | Pengujian | Perintah dan hasil |
|---|---|---|
| 1 | VLAN berfungsi dan terisolasi | Router `/interface vlan print`: Guru_Admin, Siswa, Server di ether2. Switch `/interface bridge port print`: ether1 trunk, PVID ether2=10, ether3=20, ether4=30; `/interface bridge print`: vlan-filtering=yes. Guru `ipconfig`: 192.168.10.x gateway .10.1. Siswa: 192.168.20.x gateway .20.1. Server `ip a`: 192.168.30.10/24. |
| 2 | VLAN 20 tidak bisa akses VLAN 10 | Siswa `ping 192.168.10.x`: *Request timed out*. Rule drop V20→V10, counter bertambah, log `BLOCKED-VLAN20` muncul. |
| 3 | VLAN 30 bisa ke VLAN 10 | Server `ping 192.168.10.x`: *Reply*, 0% loss. Rule accept V30→V10 berada di atas rule drop. |
| 4 | Domain `lab-smk.xyz`, `www`, `monitor` | `named-checkzone lab-smk.xyz /etc/bind/db.lab-smk.xyz`: OK. Guru `nslookup` ketiga nama: 192.168.30.10. Siswa `nslookup google.com 192.168.30.10`: *REFUSED*. Siswa `ping 8.8.8.8`: *timeout* (Siswa hanya ke Server). |
| 5 | Web dan monitoring via HTTPS | `https://www.lab-smk.xyz`: peringatan sertifikat self-signed, lalu halaman `index.html` milik siswa (vhost :443 dengan DocumentRoot `/var/www/lab-smk`). `https://monitor.lab-smk.xyz`: halaman login Cacti (dialihkan ke `/cacti/`). Modul ssl aktif (`a2enmod ssl`), `apache2ctl configtest`: *Syntax OK*. |
| 6 | Router dan server tampil, 1 grafik CPU/Memory | Cacti > Management > Devices: *Router* (192.168.30.1) dan *Server* (192.168.30.10) berstatus **Up** (SNMP v2c). Graphs: *Host MIB - CPU Utilization* server menampilkan data (muncul setelah 2-3 siklus poller). |
| 7 | Firewall efektif | `/ip firewall filter print`: established, accept V30→V10, log+drop V20→V10, accept Siswa→Server, drop Siswa→lainnya; chain input: drop `blacklist`, log, anti brute-force bertahap, accept VLAN 10/30, drop sisanya. Uji: 5x Winbox dari Siswa, lalu IP Siswa masuk `blacklist`. `/ip service print`: telnet, ftp, www, api nonaktif; ssh dan winbox hanya 192.168.10.0/24 dan 192.168.30.0/24. |
| 8 | Logging aktif | `/log print`: entri `LOGIN-ATTEMPT` dan `BLOCKED-VLAN20`. `/system clock print`: zona Asia/Jakarta, jam benar. Server `journalctl -u ssh -n 5`: log SSH tampil. |

---

## L3. Kebijakan Keamanan Informasi (dinilai: U11, P1, P4, P6, P7, P10, U14)

| Versi | Tanggal | Penanggung jawab | Tinjau ulang |
|---|---|---|---|
| 1.0 | .............. | Kepala Lab TKJ | Setiap 6 bulan |

### L3.1 Password policy

Minimal 12 karakter dengan huruf besar, huruf kecil, angka, dan simbol. Diganti tiap 90 hari. Setiap pengguna memakai akun sendiri dan tidak membagikannya. Password default (admin MikroTik kosong, `admin/admin` pada Cacti) wajib diganti saat awal. Percobaan login berulang otomatis diblokir firewall (4 koneksi baru dalam ±1 menit, blokir 1 hari).

### L3.2 Klasifikasi dan peran-hak akses

| Klasifikasi / VLAN | Boleh | Tidak boleh | Prosedur pengamanan |
|---|---|---|---|
| Guru/Admin (VLAN 10) | Internet, server (web, DNS, monitoring), SSH/Winbox router | Berbagi akun admin | Akun pribadi, password kuat; satu-satunya segmen pengelola perangkat |
| Siswa (VLAN 20) | Web sekolah dan DNS di server | VLAN 10, manajemen router, internet | Firewall antar-VLAN, tanpa hak admin |
| Server (VLAN 30) | VLAN 10 (pemeliharaan), internet untuk pembaruan | Dijangkau Siswa selain DNS dan web | UFW atau firewall host, HTTPS, backup rutin |

### L3.3 Kebijakan penggunaan internet

Internet dipakai untuk belajar dan administrasi. Dilarang mengakses judi, pornografi, dan perangkat lunak bajakan, serta memindai atau menyerang jaringan. Siswa memakai layanan server sekolah, sedangkan akses internet bebas hanya untuk Guru/Admin (diatur firewall). Aktivitas dicatat di log, dan pengguna bertanggung jawab atas akunnya. Pelanggaran dikenai teguran, pembatasan akses, lalu laporan ke pimpinan.

### L3.4 Backup, arsip, dan sanitasi

| Objek | Isi | Frekuensi | File |
|---|---|---|---|
| Router | `/export`, `/system backup save` | Tiap perubahan dan mingguan | `router-config.rsc`, `router-backup.backup` |
| Switch | Sama | Sama | `switch-config.rsc`, `switch-backup.backup` |
| Server | `/etc/bind`, `/etc/apache2`, `/etc/cacti`, `/var/www/lab-smk`; database Cacti (`mysqldump cacti`) | Mingguan | `backup-server-<tanggal>.tar.gz`, `cacti-db.sql` |

Backup disimpan di dua lokasi (PC admin dan media terpisah), 3 versi terakhir. Disk atau VM yang tidak dipakai dihapus aman (format ulang atau hapus data) sebelum dibuang atau dipinjamkan, dan pembuangan aset dicatat.

---

## L4. SOP Penanganan Insiden (dinilai: P11, P17)

Identitas dokumen (versi, tanggal, penanggung jawab, jadwal tinjau ulang) sama dengan tabel di L3.

### SOP-1 Brute-force login

| No | Tindakan | Perintah |
|---|---|---|
| 1 | Deteksi percobaan login | `/log print where message~"LOGIN-ATTEMPT"`; `/ip firewall address-list print` |
| 2 | Blokir IP (otomatis ke `blacklist`; manual bila perlu) | `/ip firewall address-list add list=blacklist address=<IP>` |
| 3 | Periksa apakah ada login berhasil | `/user active print`; `/log print where message~"logged in"` |
| 4 | Amankan: ganti password, periksa layanan | `/user set admin password=...`; `/ip service print` |
| 5 | Catat, laporkan, backup | `/export file=setelah-insiden`; formulir insiden |

### SOP-2 Server down

| No | Tindakan | Perintah |
|---|---|---|
| 1 | Cek konektivitas dan konsol VM; cek status device di Cacti | `ping 192.168.30.10` dari router/klien |
| 2 | Cek layanan dan sumber daya | `systemctl status apache2 bind9 mariadb snmpd`; `df -h`; `free -m` |
| 3 | Baca log penyebab | `journalctl -xeu apache2`; `journalctl -xeu bind9` |
| 4 | Perbaiki lalu pulihkan | `apache2ctl configtest && systemctl restart apache2`; restore dari backup |
| 5 | Verifikasi dan catat | `dig @192.168.30.10 lab-smk.xyz`; `curl -k https://lab-smk.xyz`; buka Cacti |

### Alur eskalasi

| Level | Pihak | Batas waktu |
|---|---|---|
| 1 | Teknisi / Admin Lab | Maks. 15 menit |
| 2 | Kepala Lab / Ketua Program TKJ | Belum pulih dalam 1 jam |
| 3 | Waka Sarpras / Kepala Sekolah | Belum pulih dalam 4 jam |

---

## L5. Analisis, Rujukan, dan Rekomendasi (dinilai: P2, P5, U6, P9, P3, P12, U12, P13, P14)

### L5.1 Kelemahan kondisi awal

| Kelemahan | Dampak | Mitigasi |
|---|---|---|
| Tanpa segmentasi VLAN | Siswa menjangkau perangkat Guru dan server | VLAN 10/20/30 dan firewall antar-VLAN |
| Brute-force login router | Router bisa diambil alih | Anti brute-force, akses dibatasi VLAN 10/30, layanan tak perlu dimatikan |
| Tanpa monitoring | Gangguan terlambat diketahui | Cacti untuk router dan server (SNMP) |
| Web lambat | Layanan terganggu, penyebab tidak diketahui | Grafik CPU/Memory di Cacti dengan batas wajar |
| Tanpa kebijakan | Tindakan tidak seragam | Kebijakan dan SOP terdokumentasi |

### L5.2 Jenis serangan dan kontrol

| Serangan | Kontrol pencegahan |
|---|---|
| Brute force | Anti brute-force (blacklist), password kuat, password default Cacti diganti |
| DoS / web lambat | Monitoring CPU/Memory di Cacti, alert |
| Sniffing | HTTPS dan segmentasi VLAN |
| VLAN hopping | Port access hanya menerima frame tanpa tag, ingress filtering |
| Penyalahgunaan recursion DNS | Recursion dibatasi ke VLAN 10 dan 30 |

### L5.3 Standar dan rujukan

ISO/IEC 27001 (kontrol akses, logging, backup) dan CIS Benchmark (hardening). Rujukan dokumen: soal UKK Paket 1 (KM25.4.2.1), serta dokumentasi resmi MikroTik, Debian, BIND9, Apache2, dan Cacti. Kaitannya: kontrol akses → VLAN dan firewall, logging → `/log`, backup → `/export` dan `mysqldump`.

### L5.4 Persyaratan keamanan per perangkat/layanan

| Perangkat / layanan | Persyaratan |
|---|---|
| Router | Password default diganti; telnet/ftp/www/api nonaktif; SSH/Winbox hanya VLAN 10/30; MAC-Winbox dibatasi; anti brute-force; log; backup |
| Switch | Trunk dan access sesuai VLAN; frame-types dan ingress filtering; manajemen hanya dari Host-Only; backup |
| Server | IP static; firewall host hanya port layanan; pembaruan berkala |
| DNS | Recursion hanya VLAN 10 dan 30 |
| Web | HTTPS (self-signed), vhost `www` dan `monitor` terpisah |
| Monitoring (Cacti) | Password `admin` default diganti; akses lewat HTTPS; SNMP hanya dari 192.168.30.10 |

### L5.5 Rekomendasi

- **Pengadaan:** UPS, penyimpanan backup eksternal, spesifikasi server sesuai soal (RAM ≥ 8 GB, disk ≥ 500 GB), ganti Windows 7 dengan OS yang masih didukung.
- **Teknologi tambahan:** IDS/IPS (mis. Suricata) karena firewall hanya berbasis aturan, SSH berkunci publik atau 2FA, alert Cacti lewat plugin Thold atau email, backup otomatis terjadwal.
- **Keamanan fisik:** ruang server dikunci, daftar petugas berhak, rak dan kabel terkunci, buku log masuk atau CCTV, pembatasan akses sesuai tingkat risiko aset.

Saya menyatakan laporan ini hasil pekerjaan saya sendiri.

| Penguji | Peserta |
|---|---|
| ( .................... ) | ( Contoh Siswa ) |
