# =====================================================================
#  setup-router.rsc
#  UKK TJKT/TKJ 2026 - SPK PAKET 1
#  Konfigurasi Otomatis: VM Router MikroTik (CHR)
# =====================================================================
#
#  CARA PAKAI (Upload & Jalankan via Winbox):
#
#  1. Buka Winbox, masuk ke menu "Files", lalu drag-and-drop file
#     setup-router.rsc ini ke dalam direktori utama Files List.
#
#  2. Buka menu "Terminal" di Winbox, lalu ketikkan perintah berikut:
#
#     /import setup-router.rsc
#
#  3. Tunggu proses selesai, lalu cek hasilnya dengan perintah verifikasi
#     yang ada di bagian paling bawah file ini (lihat komentar VERIFIKASI).
#
#  CATATAN PENTING:
#  - Pastikan Ether1 sudah terhubung ke Internet/Bridge sebelum import,
#    supaya DHCP Client bisa langsung bound.
#  - Pastikan Ether2 sudah terhubung ke Ether1 Switch (trunk) sebelum
#    atau sesudah import (VLAN tetap akan terbentuk meski belum terhubung).
#  - Jalankan script ini pada router yang MASIH KOSONG / default config
#    supaya tidak bentrok dengan konfigurasi lama.
#  - Setelah selesai import, TUTUP dulu koneksi Winbox via Ether2/VLAN,
#    lalu sambungkan ulang lewat Ether3 (Host-Only) atau MAC-Address
#    untuk memastikan rule firewall pembatasan akses tidak mengunci Anda.
# =====================================================================

:log info "=== MEMULAI IMPORT KONFIGURASI ROUTER - SPK PAKET 1 ==="

# ---------------------------------------------------------------------
# 1. KONFIGURASI ETHER1 - DHCP CLIENT (INTERNET)
#    Use Peer DNS: off (DNS akan diatur manual ke server)
# ---------------------------------------------------------------------
/ip dhcp-client
add interface=ether1 use-peer-dns=no disabled=no comment="WAN - Internet"

# ---------------------------------------------------------------------
# 2. KONFIGURASI DNS SERVER
#    Diarahkan ke server internal (192.168.30.10) dan DNS publik (8.8.8.8)
# ---------------------------------------------------------------------
/ip dns
set servers=192.168.30.10,8.8.8.8

# ---------------------------------------------------------------------
# 3. AKTIFKAN SNMP (untuk monitoring oleh server)
#    Community "public" hanya bisa diakses dari IP server monitoring.
#    Sesuaikan community ini dengan SNMP_COMMUNITY di server jika berbeda.
# ---------------------------------------------------------------------
/snmp
set enabled=yes
/snmp community
set [find default=yes] name=public addresses=192.168.30.10/32

# ---------------------------------------------------------------------
# 4. MEMBUAT VLAN 10, 20, 30 DI ATAS ETHER2 (TRUNK KE SWITCH)
# ---------------------------------------------------------------------
/interface vlan
add name=vlan10 vlan-id=10 interface=ether2 comment="VLAN Guru"
add name=vlan20 vlan-id=20 interface=ether2 comment="VLAN Siswa"
add name=vlan30 vlan-id=30 interface=ether2 comment="VLAN Server"

# ---------------------------------------------------------------------
# 5. PENGALAMATAN IP TIAP VLAN
# ---------------------------------------------------------------------
/ip address
add address=192.168.10.1/24 interface=vlan10 comment="Gateway VLAN 10 - Guru"
add address=192.168.20.1/24 interface=vlan20 comment="Gateway VLAN 20 - Siswa"
add address=192.168.30.1/24 interface=vlan30 comment="Gateway VLAN 30 - Server"

# ---------------------------------------------------------------------
# 6. DHCP SERVER UNTUK VLAN 10 (GURU) DAN VLAN 20 (SISWA)
#    VLAN 30 (Server) TIDAK dibuatkan DHCP karena server pakai IP static.
# ---------------------------------------------------------------------
/ip pool
add name=pool-vlan10 ranges=192.168.10.10-192.168.10.254
add name=pool-vlan20 ranges=192.168.20.10-192.168.20.254

/ip dhcp-server
add name=dhcp-vlan10 interface=vlan10 address-pool=pool-vlan10 disabled=no
add name=dhcp-vlan20 interface=vlan20 address-pool=pool-vlan20 disabled=no

/ip dhcp-server network
add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.30.10,8.8.8.8
add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=192.168.30.10,8.8.8.8

# ---------------------------------------------------------------------
# 7. NAT MASQUERADE (AKSES INTERNET UNTUK SEMUA VLAN)
# ---------------------------------------------------------------------
/ip firewall nat
add chain=srcnat out-interface=ether1 action=masquerade comment="NAT Masquerade - Internet"

# ---------------------------------------------------------------------
# 8. FIREWALL RULES
#    Urutan rule di bawah ini SENGAJA disusun top-down sesuai kebutuhan:
#    (a) Izinkan dulu VLAN 30 -> VLAN 10 SEBELUM rule blok VLAN 20 -> VLAN 10
#    (b) Baru blok VLAN 20 -> VLAN 10
#    (c) Logging aktivitas penting
#    (d) Anti brute-force SSH/Winbox (staged address-list)
#    (e) Pembatasan akses SSH/Winbox router hanya dari VLAN 10 & VLAN 30
# ---------------------------------------------------------------------

# (a) Izinkan VLAN 30 (Server) akses ke VLAN 10 (Guru)
/ip firewall filter
add chain=forward src-address=192.168.30.0/24 dst-address=192.168.10.0/24 \
    action=accept comment="Izinkan VLAN30 ke VLAN10"

# (c) Logging percobaan VLAN 20 -> VLAN 10 (sebelum di-drop)
add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 \
    action=log log-prefix="BLOCKED-VLAN20: " comment="Log percobaan VLAN20 ke VLAN10"

# (b) Blok VLAN 20 (Siswa) akses ke VLAN 10 (Guru)
add chain=forward src-address=192.168.20.0/24 dst-address=192.168.10.0/24 \
    action=drop comment="Blok VLAN20 ke VLAN10"

# (c) Logging percobaan akses SSH/Winbox ke router
add chain=input protocol=tcp dst-port=22,8291 action=log log-prefix="LOGIN-ATTEMPT: " \
    comment="Log percobaan akses SSH/Winbox"

# (d) Anti brute-force SSH/Winbox - staged address-list (stage1 -> stage2 -> stage3 -> blacklist)
add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_blacklist action=drop comment="Drop brute force SSH/Winbox"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_stage3 action=add-src-to-address-list \
    address-list=ssh_blacklist address-list-timeout=1d comment="Stage 3 ke blacklist"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_stage2 action=add-src-to-address-list \
    address-list=ssh_stage3 address-list-timeout=1m comment="Stage 2 ke stage3"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    src-address-list=ssh_stage1 action=add-src-to-address-list \
    address-list=ssh_stage2 address-list-timeout=1m comment="Stage 1 ke stage2"

add chain=input protocol=tcp dst-port=22,8291 connection-state=new \
    action=add-src-to-address-list address-list=ssh_stage1 address-list-timeout=1m \
    comment="Percobaan koneksi baru SSH/Winbox"

# (e) Batasi akses SSH/Winbox router HANYA dari VLAN 10 dan VLAN 30
add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.10.0/24 \
    action=accept comment="Izinkan akses VLAN10 ke router"

add chain=input protocol=tcp dst-port=22,8291 src-address=192.168.30.0/24 \
    action=accept comment="Izinkan akses VLAN30 ke router"

add chain=input protocol=tcp dst-port=22,8291 action=drop \
    comment="Blok akses SSH/Winbox selain VLAN10 & VLAN30"

:log info "=== KONFIGURASI ROUTER SELESAI DI-IMPORT ==="

# =====================================================================
#  VERIFIKASI (jalankan manual satu per satu di Terminal setelah import)
# =====================================================================
#  /interface vlan print
#  /ip address print
#  /ip dhcp-server print
#  /ip firewall nat print
#  /ip firewall filter print
#  /snmp print
#  /ping 8.8.8.8
#
#  Uji dari client:
#  - PC VLAN 20 (Siswa)  -> ping ke VLAN 10 (Guru)   HARUS GAGAL
#  - Server VLAN 30      -> ping ke VLAN 10 (Guru)   HARUS BERHASIL
#  - Winbox/SSH dari VLAN 20 ke router               HARUS DITOLAK
#  - Winbox/SSH dari VLAN 10/30 ke router            HARUS BERHASIL
# =====================================================================
