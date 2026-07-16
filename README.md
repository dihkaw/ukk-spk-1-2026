# Langkah deployment server
1. [Download](https://drive.google.com/file/d/17JeH2oiVa3eWacV5kAjVZhsoK3u3Ao_S/view?usp=drive_link) file ova Ubuntu 24.04

2. Konfigurasi IP Static Manual (dikerjakan sendiri).
   Sesuai netplan bawaan Ubuntu 24.04, ketik langsung di terminal server:
```bash
sudo nano /etc/netplan/50-cloud-init.yaml
```

3. Isi/edit jadi seperti ini (sesuaikan nama interface, cek dulu dengan ip a):
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

4. Simpan ( tekan Ctrl+X, tekan Y, tekan Enter), lalu terapkan:
```bash
sudo chmod 600 /etc/netplan/50-cloud-init.yaml   # opsional yaa
sudo netplan apply
```

5. Cek dan pastikan sudah konek internet sebelum lanjut:
```bash
ip a     # pastikan IP 192.168.30.10/24 sudah aktif
```

```bash
ping -c 4 192.168.30.1    # tes gateway
```

```bash
ping -c 4 8.8.8.8     #tes internet
```
Kalau ping 8.8.8.8 berhasil (reply, bukan timeout), baru lanjut ke langkah 6.

6. Download & jalankan bash script
```bash
wget https://raw.githubusercontent.com/dihkaw/ukk-spk-1-2026/main/setup-server.sh -O setup-server.sh && sudo chmod +x setup-server.sh && sudo ./setup-server.sh
```

7. Uji ciba di PC client
   Pastikan konfigurasi IP pada client menggunakan alamat DNS utama 192.168.30.10 dan alternate kosong

