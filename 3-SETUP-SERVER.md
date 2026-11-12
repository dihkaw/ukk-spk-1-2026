# Setup Server Manual — UKK TKJ 2026 SPK Paket 1
## Ubuntu Server 24.04 LTS — Tanpa Bash Script (Full Manual)

Server ini akan menjalankan 3 layanan: **DNS (bind9)**, **Web (nginx + HTTPS)**, dan **Monitoring (netdata + SNMP router)**, sesuai topologi VLAN 30 (`192.168.30.10/24`).

> 💡 **Kerjakan lewat PuTTY dari PC host, bukan lewat konsol VMware.** Copy-paste ke konsol VMware sering terpotong (tidak lengkap). Karena itu server memakai **NIC kedua (Host-Only)** untuk akses SSH. Konsol VMware hanya dipakai di bagian 1 dan 1b (perintah pendek), lalu semuanya dikerjakan dari PuTTY.

---

## 📋 Daftar Isi
1. [Konfigurasi IP Static (2 NIC)](#1-konfigurasi-ip-static)
   - [1b. Akses Server lewat PuTTY](#1b-akses-server-lewat-putty-dari-pc-host)
2. [Update Sistem](#2-update-sistem)
3. [Instalasi & Konfigurasi DNS Server (bind9)](#3-instalasi--konfigurasi-dns-server-bind9)
4. [Instalasi & Konfigurasi Web Server (nginx + HTTPS)](#4-instalasi--konfigurasi-web-server-nginx--https)
5. [Instalasi & Konfigurasi Monitoring (netdata + SNMP)](#5-instalasi--konfigurasi-monitoring-netdata--snmp)
6. [Firewall Server (UFW)](#6-firewall-server-ufw)
7. [Verifikasi Akhir](#7-verifikasi-akhir)

---

## 1. Konfigurasi IP Static

Server memakai **dua NIC**:

| NIC | Adapter di VMware | Alamat | Fungsi |
|---|---|---|---|
| NIC 1 (mis. `ens33`) | LAN Segment `Switch-Server` | `192.168.30.10/24`, gateway `192.168.30.1` | VLAN 30: DNS, Web, Monitoring |
| NIC 2 (mis. `ens34`) | Host-Only | IP **dinamis** (DHCP dari VMware), tanpa default route | Management: PuTTY dari PC host |

Masuk lewat **konsol VMware** (hanya untuk bagian ini), lalu cek nama interface yang terpasang:

```bash
ip a
```

Edit file netplan:

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

Isi/edit menjadi:

```yaml
network:
  version: 2
  ethernets:
    ens33:                      # NIC 1 (VLAN 30) - ganti sesuai nama hasil 'ip a'
      dhcp4: no
      addresses:
        - 192.168.30.10/24
      routes:
        - to: default
          via: 192.168.30.1     # gateway VLAN 30 dari router MikroTik
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]   # sementara DNS publik dulu
    ens34:                      # NIC 2 (Host-Only) - ganti sesuai nama hasil 'ip a'
      dhcp4: yes
      dhcp4-overrides:
        use-routes: false       # jangan ambil default route dari DHCP Host-Only
        use-dns: false          # jangan ambil DNS dari DHCP Host-Only
```

> ⚠️ Pastikan **DHCP Host-Only aktif** di VMware (Virtual Network Editor, pilih VMnet Host-Only, centang "Use local DHCP service"). Jika VMnet ini dipakai bersama Host-Only switch (`192.168.100.1`), rentang DHCP-nya tidak boleh mencakup alamat yang sudah dipakai (switch dan PC host).

Simpan file (`Ctrl+O`, `Enter`, `Ctrl+X`), lalu terapkan:

```bash
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```

Verifikasi IP dan koneksi internet **sebelum lanjut ke tahap berikutnya**:

```bash
ip a                     # pastikan 192.168.30.10/24 aktif, dan NIC 2 (ens34) mendapat IP dari DHCP
ip -4 a show ens34       # CATAT IP NIC 2 ini untuk PuTTY
ping -c 4 192.168.30.1   # tes gateway (Router MikroTik)
ping -c 4 8.8.8.8        # tes internet
```

✅ Pastikan `ping 8.8.8.8` berhasil (ada reply, bukan timeout) sebelum melanjutkan.

---

## 1b. Akses Server lewat PuTTY (dari PC Host)

1. Pasang SSH server (masih di konsol VMware, perintahnya pendek) OPSIONAL yaaa:

   ```bash
   sudo apt update
   sudo apt install -y openssh-server
   sudo systemctl enable --now ssh
   ```

2. Di **PC host**, pastikan adapter Host-Only memakai IP satu subnet dengan NIC 2 (mis. 192.168.100.2/24)” menjadi “pastikan adapter Host-Only PC host satu jaringan dengan NIC 2, lalu tes ping ke IP NIC 2 yang tadi dicatat dari Command Prompt:

   ```
   ping <IP-NIC-2>
   ```

3. Buka **PuTTY**: **Host Name** `<IP-NIC-2>`, **Port** `22`, **Connection type** SSH, klik **Open**, terima host key, lalu login dengan username dan password Ubuntu.

4. Mulai sekarang **semua perintah dan isi file dikerjakan dari PuTTY**. Untuk paste, cukup **klik kanan** di jendela PuTTY.

---

## 2. Update Repository dan Sistem

```bash
sudo sed -i 's|http://id.archive.ubuntu.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources && sudo apt update -y
```

Atur zona waktu agar log berwaktu benar:

```bash
sudo timedatectl set-timezone Asia/Jakarta
timedatectl                # pastikan Time zone: Asia/Jakarta
```

---

## 3. Instalasi & Konfigurasi DNS Server (bind9)

### 3.1 Install bind9

```bash
sudo apt install -y bind9 bind9utils bind9-doc dnsutils
```

### 3.2 Konfigurasi `named.conf.options`

Buka file:

```bash
sudo nano /etc/bind/named.conf.options
```

Ganti seluruh isinya menjadi:

```
acl "allowed-recursion" {
    192.168.30.0/24;
    192.168.10.0/24;
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
```

Simpan (`Ctrl+O`, `Enter`, `Ctrl+X`).

### 3.3 Konfigurasi `named.conf.local` (Definisi Zone)

```bash
sudo nano /etc/bind/named.conf.local
```

Isi:

```
zone "lab-smk.xyz" {
    type master;
    file "/etc/bind/db.lab-smk.xyz";
};
```

Simpan.

### 3.4 Buat File Zone / Record DNS

```bash
sudo nano /etc/bind/db.lab-smk.xyz
```

Isi:

```
$TTL    604800
@       IN      SOA     lab-smk.xyz. admin.lab-smk.xyz. (
                              3         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      lab-smk.xyz.
@       IN      A       192.168.30.10
www     IN      A       192.168.30.10
monitor IN      A       192.168.30.10
```

Simpan.

### 3.5 Cek Konfigurasi & Restart Service

```bash
sudo named-checkconf
sudo named-checkzone lab-smk.xyz /etc/bind/db.lab-smk.xyz
```

Jika muncul `OK`, lanjutkan:

```bash
sudo systemctl enable named
sudo systemctl restart named
sudo systemctl status named
```

### 3.6 Tes DNS

```bash
dig @192.168.30.10 lab-smk.xyz
dig @192.168.30.10 monitor.lab-smk.xyz
```

Tes recursion (domain luar). Dari server/VLAN 30 dan Guru/VLAN 10 harus berhasil, sedangkan dari Siswa/VLAN 20 harus **REFUSED**:

```bash
dig @192.168.30.10 google.com
```

---

## 4. Instalasi & Konfigurasi Web Server (nginx + HTTPS)

### 4.1 Install nginx & openssl

```bash
sudo apt install -y nginx openssl
```

### 4.2 Buat Folder Website

```bash
sudo mkdir -p /var/www/lab-smk.xyz
sudo mkdir -p /etc/nginx/ssl
```

### 4.3 Buat `index.html` (satu file, CSS dan JS di dalamnya)

Landing page cukup **satu file**, jadi mudah diganti. Lewat PuTTY:

```bash
sudo nano /var/www/lab-smk.xyz/index.html
```

Paste isi berikut (klik kanan di PuTTY):

```html
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
```

Simpan (`Ctrl+O`, `Enter`, `Ctrl+X`).

**WAJIB: ganti identitas agar halaman autentik milik kamu sendiri.** Buka kembali file ini (`sudo nano ...`) dan ubah blok `var DATA` di bagian atas:

| Isian | Contoh |
|---|---|
| `nama` | nama lengkapmu |
| `kelas` | `XII TKJ 1` |
| `noUjian` | nomor ujianmu |
| `sekolah` | nama sekolahmu |
| `dns`, `web`, `monitoring` | aplikasi yang kamu pakai (mis. `Apache2`, `Cacti`) |

Warna tema bisa diubah lewat `--utama` di bagian `:root`. Karena file statis, tidak perlu restart nginx; cukup muat ulang browser (`Ctrl+F5`).

> Alternatif jika paste terpotong: kirim file dari PC host dengan `pscp` (ikut terpasang bersama PuTTY), misalnya `pscp index.html NAMA_USER@192.168.100.10:/home/NAMA_USER/`, lalu di PuTTY jalankan `sudo cp ~/index.html /var/www/lab-smk.xyz/index.html`.

### 4.4 Set Kepemilikan File

```bash
sudo chown -R www-data:www-data /var/www/lab-smk.xyz
sudo chmod 644 /var/www/lab-smk.xyz/index.html
```

### 4.5 Buat Sertifikat SSL Self-Signed

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/lab-smk.xyz.key -out /etc/nginx/ssl/lab-smk.xyz.crt -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=lab-smk.xyz"
```

### 4.6 Buat Virtual Host Nginx (HTTP → HTTPS)

```bash
sudo nano /etc/nginx/sites-available/lab-smk.xyz
```

Isi:

```nginx
server {
    listen 80;
    server_name lab-smk.xyz www.lab-smk.xyz;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name lab-smk.xyz www.lab-smk.xyz;

    ssl_certificate     /etc/nginx/ssl/lab-smk.xyz.crt;
    ssl_certificate_key /etc/nginx/ssl/lab-smk.xyz.key;

    root /var/www/lab-smk.xyz;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

Simpan.

### 4.7 Aktifkan Virtual Host & Hapus Default

```bash
sudo ln -sf /etc/nginx/sites-available/lab-smk.xyz /etc/nginx/sites-enabled/lab-smk.xyz
sudo rm -f /etc/nginx/sites-enabled/default
```

### 4.8 Cek Konfigurasi & Restart Nginx

```bash
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
```

### 4.9 Tes Web Server

```bash
curl -k https://lab-smk.xyz
```

Atau buka browser (dari client yang DNS-nya sudah mengarah ke 192.168.30.10): `https://lab-smk.xyz`

---

## 5. Instalasi & Konfigurasi Monitoring (netdata + SNMP)

### 5.1 Install Netdata

```bash
bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --non-interactive --stable-channel
```

Jika gagal (misal karena jaringan terbatas), install via apt:

```bash
sudo apt install -y netdata
```

### 5.2 Batasi Netdata Hanya Bisa Diakses dari Localhost

```bash
sudo nano /etc/netdata/netdata.conf
```

Cari bagian `[web]`, tambahkan/ubah baris:

```
[web]
    bind to = 127.0.0.1
```

Simpan.

```bash
sudo systemctl enable netdata
sudo systemctl restart netdata
```

### 5.3 Install Tools SNMP (untuk verifikasi manual)

```bash
sudo apt install -y snmp
```

### 5.4 Aktifkan Plugin SNMP pada Netdata

```bash
sudo nano /etc/netdata/go.d.conf
```

Pastikan ada baris berikut di dalam `modules:`:

```yaml
modules:
  snmp: yes
```

Simpan.

### 5.5 Buat Konfigurasi Job SNMP untuk Monitoring Router

```bash
sudo mkdir -p /etc/netdata/go.d
sudo nano /etc/netdata/go.d/snmp.conf
```

Isi (sesuaikan `community` dengan yang dikonfigurasi di router MikroTik):

```yaml
jobs:
  - name: router
    update_every: 1
    hostname: '192.168.30.1'
    community: 'public'
    options:
      port: 161
      retries: 1
    charts:
      - table:
          - name: cpu_load
            title: 'Router CPU Load'
            units: '%'
            family: 'cpu'
            type: line
            dimensions:
              - oid: 1.3.6.1.2.1.25.3.3.1.2.1
                name: cpu
                algorithm: absolute
      - table:
          - name: memory_usage
            title: 'Router Memory Used'
            units: 'bytes'
            family: 'memory'
            type: area
            dimensions:
              - oid: 1.3.6.1.2.1.25.2.3.1.6.65536
                name: memory_used
                algorithm: absolute
```

Simpan.

⚠️ **Sebelum lanjut, verifikasi dulu OID benar-benar didukung router:**

```bash
snmpwalk -v2c -c public 192.168.30.1 1.3.6.1.2.1.25.3.3.1.2
snmpwalk -v2c -c public 192.168.30.1 1.3.6.1.2.1.25.2.3.1.6
```

Jika index OID berbeda (tergantung versi RouterOS), sesuaikan angka di akhir OID pada `snmp.conf` sebelum restart.

```bash
sudo systemctl restart netdata
```

### 5.6 Buat Reverse Proxy HTTPS untuk Netdata (`monitor.lab-smk.xyz`)

```bash
sudo nano /etc/nginx/sites-available/monitor.lab-smk.xyz
```

Isi:

```nginx
server {
    listen 80;
    server_name monitor.lab-smk.xyz;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name monitor.lab-smk.xyz;

    ssl_certificate     /etc/nginx/ssl/lab-smk.xyz.crt;
    ssl_certificate_key /etc/nginx/ssl/lab-smk.xyz.key;

    location / {
        proxy_pass http://127.0.0.1:19999;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Connection "keep-alive";
    }
}
```

Simpan.

```bash
sudo ln -sf /etc/nginx/sites-available/monitor.lab-smk.xyz /etc/nginx/sites-enabled/monitor.lab-smk.xyz
sudo nginx -t
sudo systemctl restart nginx
```

### 5.7 Tes Monitoring

```bash
curl -k https://monitor.lab-smk.xyz
snmpwalk -v2c -c public 192.168.30.1 system
```

Atau buka browser: `https://monitor.lab-smk.xyz` — pastikan muncul dashboard Netdata dengan host **server** (localhost) dan **router** (via SNMP).

---

## 6. Firewall Server (UFW)

```bash
sudo apt install -y ufw
sudo ufw allow 22/tcp      # SSH (PuTTY dari PC host lewat NIC Host-Only)
sudo ufw allow 53          # DNS
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw deny 19999/tcp    # Netdata TIDAK boleh diakses langsung dari luar
sudo ufw --force enable
```

Cek status:

```bash
sudo ufw status verbose
```

---

## 7. Verifikasi Akhir

Jalankan semua perintah berikut untuk memastikan semua layanan berjalan normal:

```bash
sudo systemctl status named       # DNS Server
sudo systemctl status nginx       # Web Server
sudo systemctl status netdata     # Monitoring
sudo ufw status                   # Firewall

dig @192.168.30.10 lab-smk.xyz
dig @192.168.30.10 monitor.lab-smk.xyz
curl -k https://lab-smk.xyz
curl -sk https://lab-smk.xyz | grep -c "NAMA SISWA"   # harus 0 (identitas sudah diganti)
curl -k https://monitor.lab-smk.xyz
snmpwalk -v2c -c public 192.168.30.1 system
```

**Checklist hasil akhir:**

- [ ] IP Static `192.168.30.10/24` aktif & bisa akses internet
- [ ] NIC 2 Host-Only mendapat IP dinamis (DHCP), dan server bisa diakses lewat PuTTY dari PC host
- [ ] `dig lab-smk.xyz` mengembalikan `192.168.30.10`
- [ ] `dig` dari VLAN 20 untuk domain luar (recursive) **ditolak** (status: REFUSED), sedangkan dari VLAN 10 dan VLAN 30 **berhasil**
- [ ] `https://lab-smk.xyz` menampilkan landing page (satu file `index.html`) dengan **identitas sendiri** (tidak lagi memuat `NAMA SISWA`)
- [ ] `https://monitor.lab-smk.xyz` menampilkan dashboard Netdata (HTTPS, bukan HTTP)
- [ ] Dashboard monitoring menampilkan 2 host: **server** dan **router** (CPU/Memory)
- [ ] Port 19999 tidak bisa diakses langsung dari luar (`ufw deny`)
- [ ] Firewall UFW aktif dengan port 22/53/80/443 terbuka

---

**Selesai!** Semua layanan (DNS, Web, Monitoring) sudah berjalan secara manual tanpa bash script, sesuai topologi SPK Paket 1.
