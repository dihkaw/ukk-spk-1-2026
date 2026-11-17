# Setup Server Manual — UKK TKJ 2026 SPK Paket 1
## Ubuntu Server 24.04 LTS — Tanpa Bash Script (Full Manual)

Server ini akan menjalankan 3 layanan utama: **DNS (`bind9`)**, **Web (`nginx` + HTTPS self-signed)**, dan **Monitoring (`netdata` + SNMP router MikroTik)** pada segmen **VLAN 30 (`192.168.30.10/24`)**.

> 💡 **Kerjakan lewat PuTTY dari PC host, bukan lewat konsol VMware.** Copy-paste ke konsol VMware sering terpotong (tidak lengkap). Karena itu server memakai **NIC kedua (Host-Only)** untuk akses SSH. Konsol VMware hanya dipakai pada tahap awal (konfigurasi IP static & pengecekan koneksi), lalu seluruh konfigurasi layanan dikerjakan dari PuTTY.

> ⚡ **Catatan Otomatisasi:** Langkah manual pada panduan ini setara dengan isi skrip otomatis `setup-server.sh` pada `README.md`. Gunakan panduan ini jika ingin mengerjakan langkah demi langkah secara manual.

---

## 📋 Daftar Isi
1. [Deploy OVA & Konfigurasi IP Static (2 NIC)](#1-deploy-ova--konfigurasi-ip-static-2-nic)
   - [1b. Akses Server lewat PuTTY (dari PC Host)](#1b-akses-server-lewat-putty-dari-pc-host)
2. [Update Repository, Sistem & Zona Waktu](#2-update-repository-sistem--zona-waktu)
3. [Instalasi & Konfigurasi DNS Server (BIND9)](#3-instalasi--konfigurasi-dns-server-bind9)
4. [Instalasi & Konfigurasi Web Server (Nginx + HTTPS)](#4-instalasi--konfigurasi-web-server-nginx--https)
5. [Instalasi & Konfigurasi Monitoring (Netdata + SNMP)](#5-instalasi--konfigurasi-monitoring-netdata--snmp)
6. [Firewall Server (UFW)](#6-firewall-server-ufw)
7. [Verifikasi Akhir & Uji Coba di PC Client](#7-verifikasi-akhir--uji-coba-di-pc-client)

---

## 1. Deploy OVA & Konfigurasi IP Static (2 NIC)

1. Import/deploy template **OVA Ubuntu Server 24.04 LTS** pada VMware dan pastikan VM server memiliki **dua NIC**:

| NIC | Adapter di VMware | Alamat | Fungsi |
|---|---|---|---|
| NIC 1 (mis. `ens33`) | LAN Segment `Switch-Server` | `192.168.30.10/24`, gateway `192.168.30.1` | VLAN 30: DNS, Web, Monitoring |
| NIC 2 (mis. `ens34`) | Host-Only | IP **dinamis** (DHCP dari VMware), tanpa default route | Management: PuTTY dari PC host |

2. Masuk lewat **konsol VMware** (hanya untuk bagian ini), lalu cek nama interface yang terpasang:

```bash
ip a
```

3. Edit file netplan bawaan Ubuntu 24.04:

```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

4. Isi/edit menjadi seperti berikut (sesuaikan nama interface `ens33` dan `ens34` dengan hasil `ip a`):

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

> ⚠️ Pastikan **DHCP Host-Only aktif** di VMware (*Virtual Network Editor*, pilih VMnet Host-Only, centang *Use local DHCP service*). Jika VMnet ini dipakai bersama Host-Only switch (`192.168.100.1`), pastikan rentang DHCP tidak bentrok dengan IP statis switch maupun PC host.

5. Simpan file (`Ctrl+O`, `Enter`, `Ctrl+X`), lalu terapkan:

```bash
sudo chmod 600 /etc/netplan/50-cloud-init.yaml   # opsional
sudo netplan apply
```

6. Verifikasi IP dan koneksi internet **sebelum lanjut ke tahap berikutnya**:

```bash
ip a                     # pastikan IP 192.168.30.10/24 aktif & NIC 2 mendapat IP DHCP
ip -4 a show ens34       # CATAT IP NIC 2 ini untuk koneksi PuTTY
ping -c 4 192.168.30.1   # tes gateway (Router MikroTik)
ping -c 4 8.8.8.8        # tes internet
```

✅ Pastikan `ping 8.8.8.8` berhasil (mendapat *reply*, bukan *timeout*) sebelum melanjutkan.

---

## 1b. Akses Server lewat PuTTY (dari PC Host)

1. Pada template OVA Ubuntu 24.04, layanan SSH umumnya sudah aktif. *(Opsional: jika SSH belum terpasang, jalankan perintah berikut di konsol VMware)*:

   ```bash
   sudo apt update && sudo apt install -y openssh-server   # Abaikan jika sudah ada ssh dan bisa konek ke server
   sudo systemctl enable --now ssh
   ```

2. Di **PC host**, pastikan adapter Host-Only berada satu jaringan dengan NIC 2 server, lalu uji koneksi dari Command Prompt:

   ```cmd
   ping <IP-NIC-2>
   ```

3. Buka **PuTTY**: isi **Host Name** dengan `<IP-NIC-2>`, **Port** `22`, **Connection type** `SSH`, klik **Open**, terima *host key*, lalu login menggunakan akun Ubuntu.

4. Mulai tahap ini, **seluruh perintah dan pembuatan file dikerjakan lewat PuTTY**. Untuk menempelkan teks (*paste*), cukup **klik kanan** di jendela PuTTY.

---

## 2. Update Repository, Sistem & Zona Waktu

Arahkan repository Ubuntu ke server utama (`archive.ubuntu.com`), lalu perbarui indeks paket:

```bash
sudo sed -i 's|http://id.archive.ubuntu.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources
sudo apt update -y
```

Atur zona waktu ke WIB (`Asia/Jakarta`) agar pencatatan log server akurat:

```bash
sudo timedatectl set-timezone Asia/Jakarta
timedatectl                # pastikan Time zone: Asia/Jakarta
```

---

## 3. Instalasi & Konfigurasi DNS Server (BIND9)

### 3.1 Install BIND9

```bash
sudo apt install -y bind9 bind9utils bind9-doc dnsutils
```

### 3.2 Konfigurasi `named.conf.options` (Pembatasan Recursion)

Buka file konfigurasi opsi BIND9:

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

Jika muncul `OK`, aktifkan dan restart layanan:

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

Tes *recursion* (domain eksternal). Dari Server/VLAN 30 dan Guru/VLAN 10 harus berhasil, sedangkan dari Siswa/VLAN 20 harus **REFUSED**:

```bash
dig @192.168.30.10 google.com
```

---

## 4. Instalasi & Konfigurasi Web Server (Nginx + HTTPS)

### 4.1 Install Nginx & OpenSSL

```bash
sudo apt install -y nginx openssl
```

### 4.2 Buat Folder Website & SSL

```bash
sudo mkdir -p /var/www/lab-smk.xyz
sudo mkdir -p /etc/nginx/ssl
```

### 4.3 Buat `index.html` (Satu File, CSS dan JS Built-in)

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
    <title>Hello World</title>
</head>
<body>
    <h1>Hello, World!</h1>
</body>
</html>
```

Simpan (`Ctrl+O`, `Enter`, `Ctrl+X`).

> **WAJIB:** Ubah identitas di bagian `var DATA` pada `/var/www/lab-smk.xyz/index.html` (`nama`, `kelas`, `noUjian`, `sekolah`) agar halaman web autentik milik kamu sendiri dan tidak lagi menampilkan `"NAMA SISWA"`.

### 4.4 Set Kepemilikan File

```bash
sudo chown -R www-data:www-data /var/www/lab-smk.xyz
sudo chmod 644 /var/www/lab-smk.xyz/index.html
```

### 4.5 Buat Sertifikat SSL Self-Signed

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/nginx/ssl/lab-smk.xyz.key -out /etc/nginx/ssl/lab-smk.xyz.crt -subj "/C=ID/ST=JawaTengah/L=Purwokerto/O=SMK/OU=TKJ/CN=lab-smk.xyz"
```

### 4.6 Buat Virtual Host Nginx (HTTP Redirect ke HTTPS)

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

### 4.7 Aktifkan Virtual Host & Restart Nginx

```bash
sudo ln -sf /etc/nginx/sites-available/lab-smk.xyz /etc/nginx/sites-enabled/lab-smk.xyz
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
```

### 4.8 Tes Web Server

```bash
curl -k https://lab-smk.xyz
```

---

## 5. Instalasi & Konfigurasi Monitoring (Netdata + SNMP)

### 5.1 Bersihkan Versi Lama (Jika Ada) & Install Netdata via Repository Resmi (PackageCloud)

Sesuai `setup-server.sh`, instalasi Netdata menggunakan repository resmi PackageCloud agar modul `go.d` (SNMP) terpasang lengkap dan stabil:

```bash
# 1. Hapus versi lama jika ada
sudo apt remove --purge -y netdata netdata-* >/dev/null 2>&1 || true
sudo rm -rf /etc/netdata /var/lib/netdata /var/cache/netdata /usr/share/netdata /var/log/netdata

# 2. Tambah repository resmi Netdata (PackageCloud)
curl -s https://packagecloud.io/install/repositories/netdata/netdata/script.deb.sh | sudo bash

# 3. Install Netdata & SNMP CLI tools
sudo apt update -o Acquire::Retries=5 -o Acquire::http::Timeout=60
sudo apt install -y -o Acquire::Retries=10 -o Acquire::http::Timeout=120 --fix-missing netdata snmp
```

### 5.2 Konfigurasi `netdata.conf` (Bind ke Localhost `127.0.0.1`)

```bash
sudo mkdir -p /etc/netdata/go.d
sudo nano /etc/netdata/netdata.conf
```

Ganti/isi menjadi:

```ini
[global]
    run as user = netdata

[web]
    bind to = 127.0.0.1
```

Simpan.

### 5.3 Aktifkan Modul SNMP pada Netdata (`go.d.conf`)

```bash
sudo nano /etc/netdata/go.d.conf
```

Isi:

```yaml
modules:
  snmp: yes
```

Simpan.

### 5.4 Buat Konfigurasi Job SNMP untuk MikroTik Router CHR (`snmp.conf`)

```bash
sudo nano /etc/netdata/go.d/snmp.conf
```

Isi (memantau **CPU Load**, **System Uptime**, dan **RAM Used** pada Router MikroTik `192.168.30.1`):

```yaml
jobs:
  - name: mikrotik_router
    update_every: 1
    hostname: '192.168.30.1'
    community: 'public'
    options:
      port: 161
      version: 2
      timeout: 2
    charts:
      - id: 'cpu_load'
        title: 'MikroTik Router CHR - CPU Load'
        units: '%'
        family: 'MikroTik Router CHR'
        type: line
        dimensions:
          - oid: 1.3.6.1.2.1.25.3.3.1.2.1
            name: cpu
            algorithm: absolute
      - id: 'system_uptime'
        title: 'MikroTik Router CHR - System Uptime'
        units: 'ticks'
        family: 'MikroTik Router CHR'
        type: line
        dimensions:
          - oid: 1.3.6.1.2.1.1.3.0
            name: uptime
            algorithm: absolute
      - id: 'memory_usage'
        title: 'MikroTik Router CHR - RAM Used'
        units: 'bytes'
        family: 'MikroTik Router CHR'
        type: area
        dimensions:
          - oid: 1.3.6.1.2.1.25.2.3.1.6.65536
            name: ram_used
            algorithm: absolute
```

Simpan.

Atur hak akses direktori `/etc/netdata` lalu restart Netdata:

```bash
sudo chown -R netdata:netdata /etc/netdata
sudo systemctl enable netdata
sudo systemctl restart netdata
```

Verifikasi apakah router MikroTik merespons query SNMP:

```bash
snmpwalk -v2c -c public 192.168.30.1 system
snmpwalk -v2c -c public 192.168.30.1 1.3.6.1.2.1.25.3.3.1.2
snmpwalk -v2c -c public 192.168.30.1 1.3.6.1.2.1.25.2.3.1.6
```

### 5.5 Buat Reverse Proxy Nginx untuk `monitor.lab-smk.xyz` (HTTPS + WebSocket)

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

        # Support Streaming & WebSocket Netdata
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_buffering off;
    }
}
```

Simpan, lalu aktifkan virtual host:

```bash
sudo ln -sf /etc/nginx/sites-available/monitor.lab-smk.xyz /etc/nginx/sites-enabled/monitor.lab-smk.xyz
sudo nginx -t
sudo systemctl restart nginx
```

---

## 6. Firewall Server (UFW)

Aktifkan UFW dan hanya izinkan port layanan yang dibutuhkan (port internal Netdata `19999` diblokir dari luar):

```bash
sudo apt install -y ufw
sudo ufw allow 22/tcp      # SSH (PuTTY dari PC host lewat NIC Host-Only)
sudo ufw allow 53          # DNS
sudo ufw allow 80/tcp      # HTTP
sudo ufw allow 443/tcp     # HTTPS
sudo ufw deny 19999/tcp    # Netdata TIDAK diakses langsung dari luar, hanya via proxy nginx
sudo ufw --force enable
sudo ufw status verbose
```

---

## 7. Verifikasi Akhir & Uji Coba di PC Client

### 7.1 Cek Layanan di Server

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

### 7.2 Pengujian di PC Client (Guru VLAN 10 & Siswa VLAN 20)

Sesuai `README.md` langkah 8:
1. Pastikan konfigurasi IP pada PC client (DHCP dari router) menggunakan **alamat DNS utama `192.168.30.10` dan alternate DNS kosong**.
2. Uji akses browser ke `https://www.lab-smk.xyz` (muncul peringatan sertifikat *self-signed*, lanjutkan dan pastikan tampil identitas siswa) serta `https://monitor.lab-smk.xyz` (dashboard Netdata menampilkan grafik **server** dan **MikroTik Router CHR**).
3. Uji `nslookup google.com 192.168.30.10`: dari **Guru (VLAN 10)** harus berhasil terjawab, sedangkan dari **Siswa (VLAN 20)** harus ditolak (`REFUSED`).

**Checklist Hasil Akhir:**
- [ ] IP Static `192.168.30.10/24` aktif & terkoneksi ke internet
- [ ] NIC 2 Host-Only mendapat IP dinamis (DHCP) & dapat diakses lewat PuTTY dari PC host
- [ ] `dig lab-smk.xyz` mengembalikan `192.168.30.10`
- [ ] Query *recursive* DNS dari VLAN 20 ditolak (`REFUSED`), sedangkan dari VLAN 10 & 30 berhasil
- [ ] `https://www.lab-smk.xyz` menampilkan halaman web satu file `index.html` dengan **identitas sendiri**
- [ ] `https://monitor.lab-smk.xyz` menampilkan dashboard Netdata dengan dukungan WebSocket & grafik CPU/Uptime/RAM **MikroTik Router CHR**
- [ ] Firewall UFW aktif (port `22, 53, 80, 443` terbuka; port `19999` tertutup)
