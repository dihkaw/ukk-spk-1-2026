#!/bin/bash
#
# =============================================================
#  Script Instalasi & Konfigurasi Server - UKK TKJ SPK PAKET 1
#  Target OS  : Ubuntu Server 24.04 LTS
#  IP Server  : 192.168.30.10/24 (VLAN 30)
#  Layanan    : DNS (bind9), Web (nginx + HTTPS), Monitoring (netdata)
#
#  CATATAN:
#  Script ini TIDAK mengubah konfigurasi IP.
#  - IP Static NIC 1 (192.168.30.10/24, VLAN 30) harus SUDAH dikonfigurasi
#    manual dan server sudah bisa akses internet SEBELUM script ini jalan.
#  - NIC 2 (Host-Only, IP dinamis dari DHCP)
#    netplan agar server bisa diakses lewat PuTTY dari PC host
#    (copy-paste dari konsol VMware sering terpotong).
#  - Landing page berupa SATU file: /var/www/lab-smk.xyz/index.html (CSS
#    dan JS ada di dalamnya). Siswa WAJIB mengganti identitas di file ini.
#
#  Cara pakai:
#    sudo chmod +x setup-server.sh
#    sudo ./setup-server.sh
# =============================================================

set -e

# --------- Cek harus dijalankan sebagai root ----------
if [ "$EUID" -ne 0 ]; then
    echo ">> Jalankan script ini dengan sudo/root!"
    echo "   sudo ./setup-server.sh"
    exit 1
fi

# ================= VARIABEL KONFIGURASI =================
IP_ADDRESS="192.168.30.10"    # harus sama dengan IP static yang sudah diset manual
MGMT_IP=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | grep -vx "${IP_ADDRESS}" | head -n1)   # IP NIC 2 (Host-Only, DHCP) untuk PuTTY
DOMAIN="lab-smk.xyz"
ALLOWED_RECURSION_NETS="192.168.30.0/24; 192.168.10.0/24"   # VLAN 30 & VLAN 10 boleh recursive query (VLAN 20 tidak)
WEBROOT="/var/www/${DOMAIN}"

ROUTER_IP="192.168.30.1"       # IP Router MikroTik (VLAN 30) - SNMP client harus sudah "on"
SNMP_COMMUNITY="public"        # sesuaikan dengan SNMP community string di router MikroTik

echo "======================================================"
echo " Memulai konfigurasi server ${DOMAIN} (${IP_ADDRESS})"
echo "======================================================"

# --------- Cek dulu apakah IP server sudah sesuai & internet nyambung ----------
ALL_IPS=$(hostname -I 2>/dev/null || ip addr | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

if ! echo " ${ALL_IPS} " | grep -q " ${IP_ADDRESS} "; then
    echo ">> PERINGATAN: IP ${IP_ADDRESS} tidak ditemukan. IP server saat ini: ${ALL_IPS}"
    echo "   Pastikan IP static sudah dikonfigurasi manual sebelum lanjut."
    printf "   Lanjutkan tetap? (y/n): "
    read confirm
    [ "$confirm" != "y" ] && exit 1
fi

if ! ping -c 2 8.8.8.8 >/dev/null 2>&1; then
    echo ">> ERROR: Server belum terkoneksi ke internet."
    echo "   Selesaikan konfigurasi IP static & gateway secara manual dulu."
    exit 1
fi

echo "   OK - IP: ${ALL_IPS}, internet: terkoneksi."

if [ -z "${MGMT_IP}" ]; then
    echo "   Catatan: NIC Host-Only belum mendapat IP (cek DHCP Host-Only di VMware), PuTTY dari PC host belum bisa dipakai."
else
    echo "   NIC Host-Only terdeteksi: ${MGMT_IP} (untuk PuTTY dari PC host)."
fi

# ================= 1. UPDATE SISTEM =================
echo ">> [1/5] Update sistem, zona waktu, dan SSH server..."
apt update -y

# Zona waktu WIB agar log berwaktu benar
timedatectl set-timezone Asia/Jakarta

# SSH server (untuk PuTTY dari PC host lewat NIC Host-Only)
# apt install -y openssh-server
# systemctl enable --now ssh

# ================= 2. INSTALL & KONFIGURASI BIND9 (DNS SERVER) =================
echo ">> [2/5] Install & konfigurasi BIND9 (DNS Server)..."
apt install -y bind9 bind9utils bind9-doc dnsutils

# --- named.conf.options : disable recursion untuk VLAN 20, izinkan VLAN 10 & VLAN 30 ---
cat > /etc/bind/named.conf.options <<EOF
acl "allowed-recursion" {
    ${ALLOWED_RECURSION_NETS};
    localhost;
};

options {
    directory "/var/cache/bind";

    recursion yes;
    allow-recursion { allowed-recursion; };
    // VLAN 20 (192.168.20.0/24) tidak termasuk allowed-recursion -> otomatis ditolak

    listen-on { any; };
    listen-on-v6 { any; };

    dnssec-validation auto;

    forwarders {
        8.8.8.8;
    };
};
EOF

# --- named.conf.local : definisikan zone ---
cat > /etc/bind/named.conf.local <<EOF
zone "${DOMAIN}" {
    type master;
    file "/etc/bind/db.${DOMAIN}";
};
EOF

# --- File zone / record DNS ---
cat > /etc/bind/db.${DOMAIN} <<EOF
\$TTL    604800
@       IN      SOA     ${DOMAIN}. admin.${DOMAIN}. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ${DOMAIN}.
@       IN      A       ${IP_ADDRESS}
www     IN      A       ${IP_ADDRESS}
monitor IN      A       ${IP_ADDRESS}
EOF

# Cek konfigurasi bind
named-checkconf
named-checkzone ${DOMAIN} /etc/bind/db.${DOMAIN}

systemctl enable named
systemctl restart named
echo "   DNS server aktif untuk zone ${DOMAIN} (www, monitor -> ${IP_ADDRESS})"

# ================= 4. INSTALL & KONFIGURASI NGINX (WEB SERVER) =================
echo ">> [3/5] Install & konfigurasi NGINX (Web Server + HTTPS self-signed)..."
apt install -y nginx openssl

mkdir -p "${WEBROOT}"
mkdir -p /etc/nginx/ssl

# --- Landing Page: SATU file index.html (CSS dan JS di dalamnya) ---
# Siswa WAJIB mengganti blok "var DATA" di bagian atas file agar halaman autentik.
cat > "${WEBROOT}/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lab SMK - Landing Page</title>
<style>
  /* ===== GANTI WARNA TEMA DI SINI ===== */
  :root { --utama: #2563eb; --gelap: #0f172a; --terang: #f1f5f9; }

  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: "Segoe UI", Arial, sans-serif; background: var(--terang); color: #1e293b; line-height: 1.6; }
  .hero { background: linear-gradient(135deg, var(--gelap), var(--utama)); color: #fff; text-align: center; padding: 80px 20px 90px; }
  .hero .label { display: inline-block; background: rgba(255,255,255,.15); padding: 4px 14px; border-radius: 20px; font-size: .85rem; margin-bottom: 16px; }
  .hero h1 { font-size: 2.4rem; margin-bottom: 8px; }
  .hero p { color: #cbd5e1; }
  .badge { display: inline-block; margin-top: 22px; background: #22c55e; color: #052e16; font-weight: 600; padding: 8px 18px; border-radius: 8px; font-size: .9rem; }
  .badge.http { background: #f59e0b; color: #451a03; }
  main { max-width: 960px; margin: -40px auto 40px; padding: 0 20px; }
  .box { background: #fff; border-radius: 14px; padding: 26px; margin-bottom: 20px; box-shadow: 0 6px 18px rgba(15,23,42,.08); }
  h2 { color: var(--gelap); margin-bottom: 12px; font-size: 1.25rem; }
  .cards { display: flex; gap: 16px; flex-wrap: wrap; }
  .card { flex: 1 1 200px; border-top: 4px solid var(--utama); background: var(--terang); border-radius: 10px; padding: 18px; }
  .card h3 { font-size: 1rem; color: var(--utama); margin-bottom: 4px; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 9px 4px; border-bottom: 1px solid #e2e8f0; }
  td:first-child { color: #64748b; width: 40%; }
  .btn { display: inline-block; margin-top: 10px; background: var(--utama); color: #fff; text-decoration: none; padding: 10px 22px; border-radius: 8px; font-weight: 600; }
  .btn:hover { opacity: .9; }
  footer { text-align: center; padding: 24px; color: #64748b; font-size: .9rem; }
</style>
</head>
<body>

<!-- ============================================================
     WAJIB GANTI: isi data diri kamu di bagian ini saja.
     Bagian lain boleh diubah sesuka hati (teks, warna, urutan).
     ============================================================ -->
<script>
  var DATA = {
    nama:       "NAMA SISWA",
    kelas:      "XII TKJ",
    noUjian:    "00-TKJ-000",
    sekolah:    "SMK XYZ",
    tagline:    "Server DNS, Web, dan Monitoring Real-Time",
    dns:        "BIND9",
    web:        "Nginx",
    monitoring: "Netdata"
  };
</script>

<header class="hero">
  <span class="label"><span data-isi="sekolah"></span> | UKK TKJ 2026</span>
  <h1><span data-isi="nama"></span></h1>
  <p><span data-isi="kelas"></span> &middot; No. Ujian <span data-isi="noUjian"></span></p>
  <p data-isi="tagline"></p>
  <div id="badge" class="badge">Memeriksa koneksi...</div>
</header>

<main>
  <section class="box">
    <h2>Layanan Server</h2>
    <div class="cards">
      <div class="card"><h3>DNS Server</h3><span data-isi="dns"></span> &middot; zona lab-smk.xyz</div>
      <div class="card"><h3>Web Server</h3><span data-isi="web"></span> &middot; HTTPS self-signed</div>
      <div class="card"><h3>Monitoring</h3><span data-isi="monitoring"></span> &middot; Router dan Server</div>
    </div>
  </section>

  <section class="box">
    <h2>Informasi Jaringan</h2>
    <table>
      <tr><td>Domain</td><td>lab-smk.xyz</td></tr>
      <tr><td>Alamat IP Server</td><td>192.168.30.10 (VLAN 30)</td></tr>
      <tr><td>Alamat halaman ini</td><td id="alamat">-</td></tr>
      <tr><td>Waktu akses</td><td id="waktu">-</td></tr>
    </table>
    <a class="btn" href="https://monitor.lab-smk.xyz">Buka Dashboard Monitoring</a>
  </section>
</main>

<footer>&copy; 2026 <span data-isi="nama"></span> &middot; <span data-isi="sekolah"></span></footer>

<script>
  // Mengisi semua teks dari DATA di atas
  document.querySelectorAll("[data-isi]").forEach(function (el) {
    el.textContent = DATA[el.getAttribute("data-isi")] || "";
  });
  document.title = DATA.nama + " - " + DATA.sekolah;

  // Status HTTPS, alamat, dan waktu
  var aman = location.protocol === "https:";
  var badge = document.getElementById("badge");
  badge.textContent = aman ? "Dibuka lewat HTTPS (terenkripsi)" : "Dibuka lewat HTTP (tidak terenkripsi)";
  if (!aman) badge.className = "badge http";
  document.getElementById("alamat").textContent = location.href;
  document.getElementById("waktu").textContent = new Date().toLocaleString("id-ID");
</script>
</body>
</html>
HTMLEOF

chown -R www-data:www-data "${WEBROOT}"
chmod 644 "${WEBROOT}/index.html"

# --- Buat sertifikat self-signed untuk HTTPS ---
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/${DOMAIN}.key -out /etc/nginx/ssl/${DOMAIN}.crt -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=${DOMAIN}"

# --- Virtual host nginx (HTTP redirect ke HTTPS + HTTPS) ---
cat > /etc/nginx/sites-available/${DOMAIN} <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};

    ssl_certificate     /etc/nginx/ssl/${DOMAIN}.crt;
    ssl_certificate_key /etc/nginx/ssl/${DOMAIN}.key;

    root ${WEBROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx
echo "   Web server aktif: https://${DOMAIN} (self-signed)"

# ================= 5. INSTALL & KONFIGURASI NETDATA (MONITORING) =================
echo ">> [4/5] Install Netdata (Monitoring Server)..."

# 1. Hapus paket Netdata versi apt jika ada (agar tidak bentrok dengan versi resmi static)
if dpkg -l | grep -q netdata; then
    echo "   Membersihkan Netdata versi apt lama..."
    apt remove --purge -y netdata netdata-* >/dev/null 2>&1
    rm -rf /usr/sbin/netdata /usr/bin/netdata /usr/libexec/netdata /usr/lib/netdata /etc/netdata
fi

# 2. Install Netdata resmi (Static Build: wajib mencakup go.d.plugin SNMP & bebas error repo Ubuntu)
if ! command -v netdata >/dev/null 2>&1 && [ ! -f /usr/libexec/netdata/plugins.d/go.d.plugin ] && [ ! -f /opt/netdata/usr/libexec/netdata/plugins.d/go.d.plugin ]; then
    echo "   Mengunduh dan memasang Netdata Static Build..."
    wget -O /tmp/kickstart.sh https://get.netdata.cloud/kickstart.sh
    bash /tmp/kickstart.sh --non-interactive --stable-channel --static-only --reinstall-even-if-unsafe --disable-telemetry
    rm -f /tmp/kickstart.sh
fi

# 3. Deteksi direktori konfigurasi Netdata (otomatis sesuaikan lokasi /etc atau /opt)
CONF_DIR="/etc/netdata"
[ -d "/opt/netdata/etc/netdata" ] && CONF_DIR="/opt/netdata/etc/netdata"

# 4. Batasi akses Netdata ke Localhost (127.0.0.1)
if [ -f "${CONF_DIR}/netdata.conf" ]; then
    if grep -q "\[web\]" "${CONF_DIR}/netdata.conf"; then
        sed -i '/\[web\]/a \    bind to = 127.0.0.1' "${CONF_DIR}/netdata.conf" 2>/dev/null || true
    else
        cat >> "${CONF_DIR}/netdata.conf" <<EOF

[web]
    bind to = 127.0.0.1
EOF
    fi
fi

systemctl enable netdata
systemctl restart netdata
echo "   Netdata aktif secara internal di 127.0.0.1:19999 (tidak diekspos langsung)"

# --- 5. Tambah host monitoring: ROUTER (via SNMP) ---
echo ">> Konfigurasi monitoring Router MikroTik (${ROUTER_IP}) via SNMP..."
apt install -y snmp

mkdir -p "${CONF_DIR}/go.d"

# Aktifkan plugin SNMP pada go.d.conf
if [ -f "${CONF_DIR}/go.d.conf" ]; then
    if grep -q "^\s*snmp:" "${CONF_DIR}/go.d.conf"; then
        sed -i "s/^\s*snmp:.*/  snmp: yes/" "${CONF_DIR}/go.d.conf"
    else
        echo "  snmp: yes" >> "${CONF_DIR}/go.d.conf"
    fi
else
    cat > "${CONF_DIR}/go.d.conf" <<EOF
modules:
  snmp: yes
EOF
fi

# Konfigurasi job SNMP dengan format YAML Netdata (go.d) yang benar & valid
cat > "${CONF_DIR}/go.d/snmp.conf" <<EOF
jobs:
  - name: router
    update_every: 10
    hostname: '${ROUTER_IP}'
    community: '${SNMP_COMMUNITY}'
    options:
      port: 161
      retries: 1
    charts:
      - id: 'cpu_load'
        title: 'Router CPU Load'
        units: '%'
        family: 'cpu'
        type: line
        dimensions:
          - oid: 1.3.6.1.2.1.25.3.3.1.2.1
            name: cpu
            algorithm: absolute
      - id: 'memory_usage'
        title: 'Router Memory Used'
        units: 'bytes'
        family: 'memory'
        type: area
        dimensions:
          - oid: 1.3.6.1.2.1.25.2.3.1.6.65536
            name: memory_used
            algorithm: absolute
EOF

# Set hak akses direktori konfigurasi agar terbaca oleh user netdata
chown -R netdata:netdata "${CONF_DIR}/go.d" 2>/dev/null || true

systemctl restart netdata
echo "   Host 'router' (${ROUTER_IP}) berhasil dikonfigurasi via SNMP."

# ================= 6. FIREWALL DASAR SERVER (UFW) =================
echo ">> [5/5] Konfigurasi firewall dasar (UFW) pada server..."
apt install -y ufw
ufw allow 22/tcp      # SSH (PuTTY dari PC host lewat NIC Host-Only)
ufw allow 53          # DNS
ufw allow 80/tcp      # HTTP
ufw allow 443/tcp     # HTTPS
ufw deny 19999/tcp    # Netdata TIDAK diakses langsung dari luar, hanya via proxy nginx
ufw --force enable

echo "======================================================"
echo " SELESAI!"
echo " - DNS   : dig @${IP_ADDRESS} ${DOMAIN}"
echo " - Web   : https://${DOMAIN}  (atau https://${IP_ADDRESS})"
echo " - Monitor: https://monitor.${DOMAIN}   (port 19999 tertutup dari luar)"
echo "   Host di monitoring: 'server' (localhost) & 'router' (${ROUTER_IP} via SNMP)"
echo "   Verifikasi SNMP router: snmpwalk -v2c -c ${SNMP_COMMUNITY} ${ROUTER_IP} system"
echo " WAJIB: ganti identitas siswa di ${WEBROOT}/index.html"
echo "   (PuTTY ke ${MGMT_IP:-<IP NIC Host-Only>}, lalu: sudo nano ${WEBROOT}/index.html)"
echo " Pastikan client (VLAN 10/20/30) mengarahkan DNS ke ${IP_ADDRESS}"
echo " agar domain ${DOMAIN} bisa di-resolve."
echo "======================================================"
