# =====================================================================
#  setup-switch.rsc
#  UKK TKJ 2026 - SPK PAKET 1
#  Konfigurasi Otomatis: VM Switch MikroTik (CHR)
#  Metode: Bridge VLAN Filtering (standar RouterOS v7)
# =====================================================================
#
#  CARA PAKAI (Upload & Jalankan via Winbox):
#
#  1. Buka Winbox, masuk ke menu "Files", lalu drag-and-drop file
#     setup-switch.rsc ini ke dalam direktori utama Files List.
#
#  2. Buka menu "Terminal" di Winbox, lalu ketikkan perintah berikut:
#
#     /import setup-switch.rsc
#
#  3. Tunggu proses selesai, lalu cek hasilnya dengan perintah verifikasi
#     yang ada di bagian paling bawah file ini (lihat komentar VERIFIKASI).
#
#  CATATAN PENTING:
#  - Jalankan script ini pada switch yang MASIH KOSONG / default config
#    supaya tidak bentrok dengan konfigurasi lama.
#  - VLAN Filtering akan diaktifkan PALING TERAKHIR oleh script ini.
#    Setelah VLAN Filtering aktif, akses Winbox lewat ether1/2/3/4 bisa
#    ikut ter-filter. SEGERA sambungkan ulang via Ether5 (Host-Only)
#    atau via MAC-Address jika koneksi Winbox saat ini terputus.
#  - Ether5 SENGAJA TIDAK dimasukkan ke bridge, supaya tetap bisa
#    dipakai sebagai jalur management independen (Host-Only untuk Winbox).
# =====================================================================

:log info "=== MEMULAI IMPORT KONFIGURASI SWITCH - SPK PAKET 1 ==="

# ---------------------------------------------------------------------
# 1. MEMBUAT BRIDGE (VLAN Filtering belum diaktifkan dulu)
# ---------------------------------------------------------------------
/interface bridge
add name=bridge-switch comment="Bridge utama VLAN 10/20/30"

# ---------------------------------------------------------------------
# 2. MENAMBAHKAN PORT KE BRIDGE
#    Ether1 = trunk ke Router
#    Ether2 = access ke VM Guru      (VLAN 10)
#    Ether3 = access ke VM Siswa     (VLAN 20)
#    Ether4 = access ke VM Server    (VLAN 30)
#    Ether5 = TIDAK dimasukkan (dipakai khusus management Host-Only)
# ---------------------------------------------------------------------
/interface bridge port
add bridge=bridge-switch interface=ether1 comment="Trunk ke Router"
add bridge=bridge-switch interface=ether2 pvid=10 comment="Access VLAN10 - Guru"
add bridge=bridge-switch interface=ether3 pvid=20 comment="Access VLAN20 - Siswa"
add bridge=bridge-switch interface=ether4 pvid=30 comment="Access VLAN30 - Server"

# ---------------------------------------------------------------------
# 3. KONFIGURASI VLAN PADA BRIDGE
#    Ether1 = tagged di ketiga VLAN (trunk)
#    Ether2/3/4 = untagged sesuai VLAN masing-masing (access port)
# ---------------------------------------------------------------------
/interface bridge vlan
add bridge=bridge-switch vlan-ids=10 tagged=bridge-switch,ether1 untagged=ether2 comment="VLAN 10 - Guru"
add bridge=bridge-switch vlan-ids=20 tagged=bridge-switch,ether1 untagged=ether3 comment="VLAN 20 - Siswa"
add bridge=bridge-switch vlan-ids=30 tagged=bridge-switch,ether1 untagged=ether4 comment="VLAN 30 - Server"

# ---------------------------------------------------------------------
# 4. KONFIGURASI ETHER5 - MANAGEMENT PORT (HOST-ONLY UNTUK WINBOX)
#    Diberi IP terpisah, DI LUAR bridge, agar tetap bisa diakses
#    walau ada kesalahan konfigurasi VLAN pada bridge.
# ---------------------------------------------------------------------
/ip address
add address=192.168.100.1/24 interface=ether5 comment="Management Winbox - Host Only"

# ---------------------------------------------------------------------
# 5. AKTIFKAN VLAN FILTERING (PALING TERAKHIR)
# ---------------------------------------------------------------------
/interface bridge
set bridge-switch vlan-filtering=yes

:log info "=== KONFIGURASI SWITCH SELESAI DI-IMPORT ==="

# =====================================================================
#  VERIFIKASI (jalankan manual satu per satu di Terminal setelah import)
# =====================================================================
#  /interface bridge print
#  /interface bridge port print
#  /interface bridge vlan print
#  /interface bridge host print
#  /ip address print
#
#  Uji dari client:
#  - VM Guru  (terhubung Ether2) -> otomatis masuk VLAN 10, dapat DHCP dari Router
#  - VM Siswa (terhubung Ether3) -> otomatis masuk VLAN 20, dapat DHCP dari Router
#  - VM Server(terhubung Ether4) -> berada di VLAN 30 (IP static 192.168.30.10)
#  - Winbox tetap bisa diakses via Ether5 (192.168.100.1) walau VLAN filtering aktif
# =====================================================================
