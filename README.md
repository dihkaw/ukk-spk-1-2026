# Tahap 1: Konfigurasi IP Static Manual (dikerjakan sendiri)
Sesuai netplan bawaan Ubuntu 24.04, mketik langsung di terminal server:
```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```
Isi/edit jadi seperti ini (sesuaikan nama interface, cek dulu dengan ip a):
```yaml
network:
  version: 2
  ethernets:
    ens33:                      # ganti sesuai nama interface asli
      dhcp4: no
      addresses:
        - 192.168.30.10/24
      routes:
        - to: default
          via: 192.168.30.1     # gateway VLAN 30 dari router MikroTik
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]   # sementara pakai DNS publik dulu
```
Simpan (Ctrl+O, Enter, Ctrl+X), lalu terapkan:
```bash
sudo chmod 600 /etc/netplan/50-cloud-init.yaml
sudo netplan apply
```
Cek dan pastikan sudah konek internet sebelum lanjut:
```bash
ip a     # pastikan IP 192.168.30.10/24 sudah aktif
```

```bash
ping -c 4 192.168.30.1    # tes gateway
```

```bash
ping -c 4 8.8.8.8     #tes internet
```

Kalau ping 8.8.8.8 berhasil (reply, bukan timeout), baru lanjut ke tahap 2.

#Tahap 2: Download & jalankan bash script
```bash
wget https://raw.githubusercontent.com/dihkaw/ukk-spk-1-2026/main/aplikasi.sh -O setup-server.sh && sudo chmod +x setup-server.sh && sudo ./setup-server.sh
