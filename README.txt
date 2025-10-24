# RHEL & Podman Kapsamlı Uzman Rehberi

## Sistem ve DevOps Uzmanları için Eksiksiz Referans Kılavuzu

**Hedef Dağıtımlar:** Red Hat Enterprise Linux 9.x, AlmaLinux 9.x, Rocky Linux 9.x

**Podman Sürümleri:** 4.x - 5.x

**Hedef Kitle:** Sistem Yöneticileri, DevOps Mühendisleri, Site Reliability Engineers

**Sürüm:** 1.0 (Birleştirilmiş ve Genişletilmiş Sürüm)

**Son Güncelleme:** 2025-10-23

---

## İçindekiler

1. [Sistem Temelleri ve Mimari](#1-sistem-temelleri-ve-mimari)
2. [Depolama Yönetimi (LVM, XFS, Stratis)](#2-depolama-yönetimi)
3. [Ağ Yönetimi ve Güvenlik Duvarı](#3-ağ-yönetimi-ve-güvenlik-duvarı)
4. [Sorun Giderme ve Performans Analizi](#4-sorun-giderme-ve-performans)
5. [Podman Temelleri ve Mimari](#5-podman-temelleri-ve-mimari)
6. [Podman İleri Seviye Networking](#6-podman-ileri-seviye-networking)
7. [Podman Kalıcılık: systemd ve Quadlet](#7-podman-kalıcılık-systemd-ve-quadlet)

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

8. [Container Registry Yönetimi](#8-container-registry-yönetimi)
9. [Güvenlik: SELinux, Seccomp, Scanning](#9-güvenlik-selinux-seccomp-scanning)
10. [Production Deployment Patterns](#10-production-deployment-patterns)
11. [CI/CD Entegrasyonu](#11-cicd-entegrasyonu)
12. [Monitoring ve Logging](#12-monitoring-ve-logging)
13. [Backup ve Disaster Recovery](#13-backup-ve-disaster-recovery)
14. [İleri Seviye Konular](#14-ileri-seviye-konular)
15. [Teknik Terimler ve En İyi Uygulamalar](#15-teknik-terimler-ve-en-iyi-uygulamalar)

---

## 1) Sistem Temelleri ve Mimari

> **Bu Bölümün Önemi:** Container teknolojileri, alttaki Linux sisteminin yeteneklerine dayanır. RHEL ekosistemini, systemd'yi ve sistem mimarisini anlamadan Podman'ı production ortamında güvenli ve verimli kullanamazsınız. Bu bölüm, container yönetiminin temelini oluşturan sistem bileşenlerini ve bunların neden kritik olduğunu açıklar.


### 1.1 RHEL 9 Ekosistemi ve Türevleri

**Neden Bu Bilgi Önemli?** RHEL 9 ve türevleri arasındaki farkları bilmek, doğru dağıtımı seçmenizi ve beklenmeyen uyumluluk sorunlarından kaçınmanızı sağlar. Her dağıtım, farklı kullanım senaryoları ve destek modelleri sunar.


**RHEL 9 Aile Ağacı:**

```
┌─────────────────────────────────────────┐
│     CentOS Stream 9 (upstream)          │
│         ↓                               │
│   Red Hat Enterprise Linux 9            │
│         ↓                               │
│   ┌─────────┬──────────────┬─────────┐ │
│   │AlmaLinux│ Rocky Linux  │ Oracle  │ │
│   │    9.x  │     9.x      │ Linux 9 │ │
│   └─────────┴──────────────┴─────────┘ │
└─────────────────────────────────────────┘
```

**Temel Farklar ve Uyumluluk:**

- **AlmaLinux 9:** CloudLinux sponsorluğunda, 1:1 RHEL binary uyumluluğu hedefler
- **Rocky Linux 9:** CentOS kurucusu Gregory Kurtzer tarafından başlatıldı, topluluk odaklı
- **Oracle Linux 9:** Oracle desteğinde, Unbreakable Enterprise Kernel seçeneği sunar
- **Kernel:** 5.14.x serisi (RHEL 9.0 bazlı, sürekli backport'larla güncellenir)
- **systemd:** v250+ (init sistemi ve servis yönetimi)
- **Paket Yöneticisi:** DNF 4.x (yum komutları hala çalışır, dnf'ye alias)

**Önemli Değişiklikler (RHEL 8'den 9'a):**

- Python 3.9 varsayılan (önceden 3.6)
- OpenSSL 3.0 (TLS 1.3 varsayılan)
- Wayland varsayılan display server
- cgroup v2 unified hierarchy (cgroup v1 deprecated)
- XFS ve Stratis gelişmiş dosya sistemi özellikleri
- nftables firewall backend (iptables deprecated)

### 1.2 Sistem Mimarisi ve Bileşenler

**Neden Mimariyi Anlamalıyız?** Container'lar izole ortamlar gibi görünse de, aslında host kernel'i paylaşır. Sistem katmanlarını anlamak, performans sorunlarını çözmenize, güvenlik açıklarını kapatmanıza ve kaynak yönetimini optimize etmenize yardımcı olur.

**Kullanım Senaryosu:** Bir container'ın network sorunu olduğunda, problemin container içinde mi, host network stack'inde mi, yoksa firewall'da mı olduğunu anlamak için bu mimariyi bilmelisiniz.


**Katmanlı Sistem Mimarisi:**

```
┌─────────────────────────────────────────────────────┐
│                   User Space                        │
├─────────────────────────────────────────────────────┤
│  Applications & Services                            │
│   ├─ systemd (init, PID 1)                          │
│   ├─ Podman/Buildah (container runtime)             │
│   ├─ NetworkManager (ağ yönetimi)                   │
│   └─ firewalld (dinamik firewall)                   │
├─────────────────────────────────────────────────────┤
│               System Libraries                      │
│   ├─ glibc 2.34+                                    │
│   ├─ systemd-libs                                   │
│   └─ SELinux libs (libselinux, libsepol)            │
├─────────────────────────────────────────────────────┤
│            Linux Kernel 5.14.x                      │
│   ├─ cgroup v2 (unified hierarchy)                  │
│   ├─ namespace (PID, NET, MNT, UTS, IPC, USER)      │
│   ├─ SELinux (Enforcing mode)                       │
│   ├─ Netfilter/nftables                             │
│   └─ Device drivers & modules                       │
├─────────────────────────────────────────────────────┤
│                   Hardware                          │
└─────────────────────────────────────────────────────┘
```

### 1.3 systemd Derinlemesine

**Neden systemd Bu Kadar Kritik?** Modern Linux'ta systemd, init sisteminden çok daha fazlasıdır. Container'ların otomatik başlatılması, kaynak limitleri, güvenlik izolasyonu ve log yönetimi için systemd entegrasyonu şarttır. Production ortamında container'ları manuel başlatmak yerine, systemd ile yönetmek güvenilirlik ve sürdürülebilirlik sağlar.

**Gerçek Dünya Senaryosu:** Sunucu yeniden başlatıldığında, tüm container'larınızın otomatik olarak başlamasını ve doğru sırayla dependency'lerini çözmesini istiyorsunuz. Bu ancak systemd entegrasyonu ile mümkündür.


**systemd Unit Tipleri:**

```bash
# Tüm unit tiplerini listele
systemctl -t help

# Yaygın tipler:
# - service:  Hizmetler (arka plan süreçleri)
# - socket:   Socket aktivasyonu
# - target:   Grup hedefleri (runlevel benzeri)
# - mount:    Dosya sistemi bağlama noktaları
# - timer:    Zamanlı görevler (cron benzeri)
# - path:     Dosya/dizin izleme tetikleyicileri
# - slice:    Kaynak kontrolü için cgroup hiyerarşisi
# - scope:    Harici süreçlerin gruplandırılması
```

**Unit Dosyası Anatomisi:**

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application Service
Documentation=https://docs.example.com/myapp
After=network-online.target
Wants=network-online.target
Requires=postgresql.service
Before=nginx.service

# Bağımlılık çakışmasını önle
Conflicts=myapp-old.service

[Service]
Type=notify
# Type seçenekleri:
#  - simple:  Fork etmez, exec sonrası hazır sayılır
#  - forking: Fork eder, parent çıkınca hazır
#  - notify:  sd_notify() ile hazır sinyali gönderir (önerilen)
#  - oneshot: Tek seferlik çalışır, RemainAfterExit=yes ile kombine
#  - dbus:    D-Bus üzerinden register olur

User=appuser
Group=appgroup
WorkingDirectory=/opt/myapp

# Güvenlik sertleştirme
PrivateTmp=yes                    # /tmp izolasyonu
ProtectSystem=strict              # / ve /usr read-only
ProtectHome=yes                   # /home erişimi engelle
NoNewPrivileges=yes               # setuid/setgid engelle
CapabilityBoundingSet=CAP_NET_BIND_SERVICE  # Sadece port 1024 altı bind
ReadOnlyPaths=/etc /usr
ReadWritePaths=/var/log/myapp /var/lib/myapp

# Kaynak limitleri
MemoryMax=2G                      # OOM öncesi maksimum
MemoryHigh=1.8G                   # Soft limit, ağır swap tetikler
CPUQuota=200%                     # 2 CPU eşdeğeri
TasksMax=256                      # Maksimum thread/process
IOWeight=500                      # I/O önceliği (100-10000)

# Restart stratejisi
Restart=on-failure
RestartSec=5s
StartLimitBurst=3                 # 10 saniyede 3 başarısız deneme sonrası pes et
StartLimitIntervalSec=10s

# Environment
Environment="NODE_ENV=production"
EnvironmentFile=/etc/myapp/env

# Komutlar
ExecStartPre=/opt/myapp/bin/pre-start.sh
ExecStart=/opt/myapp/bin/server --config /etc/myapp/config.yaml
ExecReload=/bin/kill -HUP $MAINPID
ExecStop=/bin/kill -SIGTERM $MAINPID
ExecStopPost=/opt/myapp/bin/cleanup.sh

# Timeout'lar
TimeoutStartSec=30s
TimeoutStopSec=30s

# Watchdog
WatchdogSec=30s

[Install]
WantedBy=multi-user.target
# multi-user.target = runlevel 3 (çok kullanıcılı, ağ aktif, GUI yok)
# graphical.target  = runlevel 5 (+ GUI)
Also=myapp-worker.service
```

**systemd Operasyonları:**

```bash
# Unit yönetimi
systemctl daemon-reload                # systemd yeniden yükler (unit dosyası değişikliklerini uygular)

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** systemd'nin configuration dosyalarını yeniden okumasını sağlar
- **Ne Zaman:** Unit dosyası (.service, .socket vb.) oluşturduğunuzda veya düzenlediğinizde
- **Neden Gerekli:** systemd dosyaları cache'ler, bu komut olmadan değişiklikler aktif olmaz
- **Senaryo:** `/etc/systemd/system/myapp.service` dosyasını oluşturduktan sonra MUTLAKA çalıştırın
systemctl enable myapp.service         # servisi sistem açılışında otomatik başlatır

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Servisi sistem boot sırasında otomatik başlatır
- **Arka Planda Ne Olur:** target.wants/ dizininde symlink oluşturulur
- **Production İçin KRİTİK:** Container servisleri enable edilmezse reboot sonrası manuel başlatma gerekir
- **Senaryo:** Yeni deploy edilen uygulama sunucu restart sonrası otomatik başlamalı
systemctl enable --now myapp.service   # Enable ve start birlikte
systemctl disable myapp.service        # Servisi otomatik başlatmaktan çıkarır
systemctl start myapp.service          # Servisi başlatır

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Servisi hemen başlatır (otomatik başlatma ayarı yapmaz)
- **enable vs start:** enable=otomatik başlatma ayarı, start=hemen başlat
- **Kullanım:** Test amaçlı veya geçici servisler için
- **Dikkat:** Sadece start yaptıysanız, reboot sonrası servis başlamaz
systemctl stop myapp.service           # Servisi durdurur
systemctl restart myapp.service        # Servisi yeniden başlatır
systemctl reload myapp.service         # Servis yapılandırmasını yeniden yükler (config reload, SIGHUP)

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Servisin konfigürasyonunu yeniden okur, mevcut bağlantıları KESMEDEN
- **restart vs reload:** restart=tüm bağlantılar kesilir, reload=graceful reload
- **Senaryo:** nginx config değişikliği, aktif kullanıcıları etkilemeden
- **Dikkat:** Her servis reload desteklemez, ExecReload tanımlı olmalı
systemctl status myapp.service         # Servis durumunu verir
systemctl is-active myapp.service      # Servisin aktif olup olmadığını gösterir
systemctl is-enabled myapp.service     # Servisin açılışta aktif olup olmadığını gösterir
systemctl is-failed myapp.service      # Servisin başarısız olup olmadığını kontrol eder

# Maskeleme (başlatmayı tamamen engelle - symlink -> /dev/null)
systemctl mask myapp.service

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Servisi tamamen devre dışı bırakır, hiçbir şekilde başlatılamaz
- **Teknik:** /dev/null'a symlink oluşturur
- **disable vs mask:** disable=manual başlatılabilir, mask=hiç başlatılamaz
- **Senaryo:** Güvenlik riski olan eski servisi kilitleme, yanlışlıkla başlatmayı engelleme
systemctl unmask myapp.service

# Override dosyası oluştur (mevcut unit'i değiştirmeden özelleştir)
systemctl edit myapp.service           # /etc/systemd/system/myapp.service.d/override.conf oluşturur
systemctl cat myapp.service            # Aktif unit dosyasını göster

# Log izleme
journalctl -u myapp.service                         # Tüm loglar
journalctl -u myapp.service -f                      # Canlı izleme (follow)

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Servis log'larını gerçek zamanlı izler (tail -f benzeri)
- **Kullanım:** Deployment sonrası canlı izleme, hata ayıklama
- **Avantaj:** Structured logging, renklendirme, filtreleme
- **Senaryo:** Yeni versiyonu deploy ettiniz, uygulama düzgün başladı mı kontrol ediyorsunuz
journalctl -u myapp.service -n 100                  # Son 100 satır
journalctl -u myapp.service --since "2025-10-18 09:00"
journalctl -u myapp.service --since "1 hour ago"
journalctl -u myapp.service --until "10 minutes ago"
journalctl -u myapp.service -p err                  # Sadece error ve üstü
journalctl -u myapp.service -o json-pretty          # JSON formatında

# Journal yönetimi
journalctl --disk-usage                             # Journal disk kullanımı
journalctl --vacuum-size=500M                       # 500MB'a kadar temizle

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Journal log'larını boyut limitine göre temizler
- **Neden Gerekli:** /var/log/journal/ zamanla çok büyür, disk dolar
- **Alternatifler:** --vacuum-time=30d (30 günlük tutma)
- **Senaryo:** /var dolmak üzere, eski log'ları temizleyerek yer açıyorsunuz
journalctl --vacuum-time=30d                        # 30 günden eski logları sil
journalctl --verify                                 # Journal bütünlüğünü kontrol et

# Dependency analizi
systemctl list-dependencies myapp.service           # Bu unit'in bağımlılıkları
systemctl list-dependencies myapp.service --reverse # Neye bağımlı (tersine)
systemctl list-dependencies myapp.service --all     # Tüm bağımlılık ağacı

# systemd-analyze ile performans
systemd-analyze                                     # Boot süresi
systemd-analyze blame                               # En yavaş başlayanlar

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Boot sırasında en yavaş başlayan servisleri listeler
- **Kullanım:** Boot süresini optimize etme
- **Analiz:** Hangi servisler boot'u yavaşlatıyor gösterir
- **Senaryo:** Sunucu açılışı çok uzun sürüyor, darboğazları bulup optimize edin
systemd-analyze critical-chain                      # Kritik yol analizi

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Boot sırasındaki dependency zincirini ve gecikmeleri gösterir
- **Fark:** blame=en yavaş servisler, critical-chain=dependency darboğazı
- **Görsel:** ASCII tree formatında bağımlılık zinciri
- **Senaryo:** Hangi servis diğerlerini bekliyor, sıralama optimizasyonu
systemd-analyze critical-chain myapp.service        # Belirli unit için kritik yol

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Boot sırasındaki dependency zincirini ve gecikmeleri gösterir
- **Fark:** blame=en yavaş servisler, critical-chain=dependency darboğazı
- **Görsel:** ASCII tree formatında bağımlılık zinciri
- **Senaryo:** Hangi servis diğerlerini bekliyor, sıralama optimizasyonu
systemd-analyze plot > boot.svg                     # Görsel timeline
systemd-analyze dot | dot -Tsvg > dependencies.svg  # Bağımlılık grafiği
systemd-analyze security myapp.service              # Güvenlik analizi

# Tüm failed servisleri göster
systemctl --failed
systemctl list-units --state=failed

# Belirli tip unit'leri listele
systemctl list-units --type=service
systemctl list-units --type=timer
systemctl list-sockets
```

**systemd Timer Kullanımı (Cron Alternatifi):**

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Backup Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup.sh

# /etc/systemd/system/backup.timer
[Unit]
Description=Daily Backup Timer

[Timer]
OnCalendar=daily                     # Her gün 00:00
# OnCalendar örnekleri:
#  - hourly, daily, weekly, monthly
#  - *-*-* 02:00:00  (her gün 02:00)
#  - Mon *-*-* 00:00:00  (her pazartesi)
#  - Mon..Fri *-*-* 18:00  (hafta içi 18:00)

Persistent=true                      # Kaçırılan zamanları telafi et (sistem kapalıysa)
RandomizedDelaySec=30min             # ±30 dakika rastgele gecikme (load dağıtımı için)

[Install]
WantedBy=timers.target
```

```bash
# Timer'ı etkinleştir
systemctl enable --now backup.timer

# Timer durumunu kontrol et
systemctl list-timers                # Aktif timerlar ve sonraki çalışma zamanları
systemctl status backup.timer        # Son çalışma zamanı ve durum
```

### 1.4 Kernel Parametreleri ve Tuning

**Sysctl ile Kernel Parametreleri:**

```bash
# Geçici değişiklik (reboot sonrası kaybolur)
sysctl -w net.ipv4.ip_forward=1
sysctl -w vm.swappiness=10

# Mevcut değerleri görüntüle
sysctl net.ipv4.ip_forward
sysctl -a | grep tcp

# Kalıcı konfigürasyon
cat > /etc/sysctl.d/99-custom.conf <<EOF
# Network tuning
net.core.somaxconn = 4096                # Listen queue boyutu
net.core.netdev_max_backlog = 5000       # Paket işleme queue
net.ipv4.tcp_max_syn_backlog = 8192      # SYN flood koruması
net.ipv4.tcp_syncookies = 1              # SYN cookie'ler (DDoS koruması)

# TCP optimizasyonu
net.ipv4.tcp_fin_timeout = 15            # FIN-WAIT-2 timeout (saniye)
net.ipv4.tcp_tw_reuse = 1                # TIME-WAIT socket yeniden kullanımı
net.ipv4.tcp_keepalive_time = 600        # Keepalive başlangıç süresi (saniye)
net.ipv4.tcp_keepalive_intvl = 10        # Keepalive aralığı
net.ipv4.tcp_keepalive_probes = 3        # Keepalive probe sayısı

# TCP window scaling (high bandwidth networks için)
net.ipv4.tcp_window_scaling = 1
net.core.rmem_max = 134217728            # 128MB receive buffer
net.core.wmem_max = 134217728            # 128MB send buffer
net.ipv4.tcp_rmem = 4096 87380 67108864  # min default max
net.ipv4.tcp_wmem = 4096 65536 67108864

# Virtual memory (yüksek yüklü sistemler için)
vm.swappiness = 10                       # Swap kullanımını azalt (0-100, default 60)
vm.dirty_ratio = 15                      # Dirty page flush tetikleme % (default 20)
vm.dirty_background_ratio = 5            # Arka plan flush % (default 10)
vm.vfs_cache_pressure = 50               # Cache vs inode/dentry reclaim (default 100)

# File descriptor limitleri
fs.file-max = 2097152                    # Sistem geneli FD limiti
fs.inotify.max_user_watches = 524288     # inotify izleyici limiti
fs.inotify.max_user_instances = 512      # inotify instance limiti

# Container workload için
kernel.pid_max = 4194304                 # Maksimum PID sayısı
kernel.threads-max = 4194304             # Maksimum thread sayısı

# IP forwarding (container networking için kritik)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Bridge netfilter (container bridge için)
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Değişiklikleri uygula
sysctl -p /etc/sysctl.d/99-custom.conf

# Mevcut değerleri kontrol
sysctl -a | grep tcp_fin_timeout
sysctl net.ipv4.ip_forward
```

**User Limits (ulimit):**

```bash
# Geçici (mevcut shell için)
ulimit -n 65535                          # FD limiti
ulimit -u 8192                           # Kullanıcı başına process limiti
ulimit -a                                # Tüm limitleri göster

# Kalıcı: /etc/security/limits.conf veya /etc/security/limits.d/*.conf
cat > /etc/security/limits.d/99-custom.conf <<EOF
# Format: <domain> <type> <item> <value>
# domain: kullanıcı adı, @grup, * (tümü)
# type: soft (uyarı), hard (maksimum)
*           soft    nofile      65535
*           hard    nofile      65535
*           soft    nproc       8192
*           hard    nproc       8192
@containeradmin  soft  nofile  131072
@containeradmin  hard  nofile  131072
EOF

# PAM modülü aktif mi kontrol (genelde varsayılan aktiftir)
grep pam_limits /etc/pam.d/system-auth

# Systemd service'ler için (unit dosyasında)
[Service]
LimitNOFILE=131072                      # File descriptor limiti
LimitNPROC=8192                         # Process limiti
LimitMEMLOCK=infinity                   # Locked memory limiti
```

### 1.5 Kernel Modülleri

```bash
# Yüklü modüller
lsmod | head -20
lsmod | grep overlay                     # Overlay FS modülü (container için kritik)
lsmod | grep br_netfilter                # Bridge netfilter (container networking)

# Modül detayları
modinfo overlay
modinfo br_netfilter

# Modül yükleme (geçici, reboot sonrası kaybolur)
modprobe overlay
modprobe br_netfilter

# Kalıcı yükleme
cat > /etc/modules-load.d/container.conf <<EOF
overlay
br_netfilter
EOF

# Modül kaldırma
modprobe -r module_name

# Modül parametreleri
cat > /etc/modprobe.d/kvm.conf <<EOF
options kvm_intel nested=1               # Nested virtualization
EOF

# Kernel module dependency göster
modprobe --show-depends overlay
```

### 1.6 DNF Paket Yöneticisi

```bash
# Paket arama ve bilgi
dnf search podman
dnf info podman
dnf list installed | grep podman
dnf list available | grep container

# Paket kurulum
dnf install -y podman buildah skopeo
dnf install -y @container-tools          # Paket grubu kurulumu

# Paket güncelleme
dnf update                               # Tüm sistem güncelleme
dnf update podman                        # Tek paket güncelleme
dnf check-update                         # Güncellenebilir paketleri listele

# Paket kaldırma
dnf remove package-name
dnf autoremove                           # Kullanılmayan bağımlılıkları temizle

# Repository yönetimi
dnf repolist                             # Aktif repo'ları listele
dnf repolist --all                       # Tüm repo'ları listele
dnf config-manager --set-enabled repo-id  # Repo aktifleştir
dnf config-manager --set-disabled repo-id # Repo devre dışı bırak

# Üçüncü parti repo ekleme
dnf install -y epel-release              # EPEL (Extra Packages for Enterprise Linux)

# Cache yönetimi
dnf clean all                            # Tüm cache'i temizle
dnf makecache                            # Metadata cache'i yenile

# İşlem geçmişi
dnf history                              # Tüm işlemleri listele
dnf history info <ID>                    # İşlem detayı
dnf history undo <ID>                    # İşlemi geri al
dnf history rollback <ID>                # Belirtilen ID'ye kadar geri al

# Paket bağımlılık analizi
dnf deplist podman                       # Bağımlılıkları listele
dnf repoquery --requires podman          # Gereksinimleri sorgula
dnf repoquery --whatrequires podman      # Bu paketi neyin kullandığını sorgula

# Module streams (AppStream)
dnf module list                          # Mevcut module'leri listele
dnf module list postgresql               # Belirli module sürümleri
dnf module info postgresql:15            # Module detayı
dnf module enable postgresql:15          # Module enable
dnf module install postgresql:15         # Module install
dnf module reset postgresql              # Module reset
```



### 2.4 Stratis (Modern Storage Yönetimi)

**Stratis Nedir:**

Stratis, LVM + XFS kombinasyonunu basitleştiren modern bir volume management
sistemidir. Red Hat tarafından geliştirilmiş, ZFS ve Btrfs benzeri özellikleri
hedefler.

**Stratis Kurulum:**

```bash
# Stratis kurulumu
dnf install -y stratisd stratis-cli
systemctl enable --now stratisd

# Durum kontrolü
stratis daemon version
systemctl status stratisd
```
**Stratis Pool Yönetimi:**

```bash
# Pool oluşturma
stratis pool create pool1 /dev/sdb
stratis pool create pool2 /dev/sdc /dev/sdd  # Multiple disks

# Pool'a disk ekleme
stratis pool add-data pool1 /dev/sde

# Pool listeleme
stratis pool list
stratis pool list --stopped

# Pool detayları
stratis pool

# Pool silme
stratis pool destroy pool1
```
**Stratis Filesystem Yönetimi:**

```bash
# Filesystem oluşturma
stratis filesystem create pool1 fs1
stratis filesystem create pool1 fs2 --size 100G  # Size limiti

# Filesystem listeleme
stratis filesystem list
stratis filesystem list pool1

# Mount işlemi
mkdir -p /stratis/pool1/fs1
mount /stratis/pool1/fs1 /mnt/fs1

# UUID öğren
lsblk --output=UUID /stratis/pool1/fs1

# fstab girişi (UUID ile)
UUID=$(lsblk -no UUID /stratis/pool1/fs1)
echo "UUID=$UUID /mnt/fs1 xfs defaults,x-systemd.requires=stratisd.service 0 0" >> /etc/fstab

# Filesystem genişletme
stratis filesystem set-size pool1 fs1 200G

# Filesystem silme
umount /mnt/fs1
stratis filesystem destroy pool1 fs1
```
**Stratis Snapshot:**

```bash
# Snapshot oluşturma
stratis filesystem snapshot pool1 fs1 fs1_snap_$(date +%F)

# Snapshot listeleme
stratis filesystem list pool1

# Snapshot mount
mkdir /mnt/snapshot
mount /stratis/pool1/fs1_snap_2025-10-20 /mnt/snapshot

# Snapshot'tan geri yükleme
umount /mnt/fs1
umount /mnt/snapshot
stratis filesystem destroy pool1 fs1
stratis filesystem rename pool1 fs1_snap_2025-10-20 fs1
mount /stratis/pool1/fs1 /mnt/fs1

# Snapshot silme
umount /mnt/snapshot
stratis filesystem destroy pool1 fs1_snap_2025-10-20
```
**Stratis Encryption:**

```bash
# Encrypted pool oluşturma
stratis key set --capture-key mykey
stratis pool create --key-desc mykey pool_encrypted /dev/sdf

# Pool unlock
stratis key set --capture-key mykey
stratis pool unlock
```
- - -
## 3\) Ağ Yönetimi ve Güvenlik Duvarı


## 3\) Ağ Yönetimi ve Güvenlik Duvarı

### 3.1 NetworkManager Temelleri

**nmcli Temel Operasyonlar:**

```bash
# Bağlantı durumu
nmcli general status
nmcli device status
nmcli connection show
nmcli connection show --active

# Interface detayları
nmcli device show eth0
ip addr show eth0
ip link show eth0

# Yeni bağlantı oluşturma (statik IP)
nmcli connection add type ethernet \
    con-name eth0-static \
    ifname eth0 \
    ipv4.method manual \
    ipv4.addresses 10.0.1.100/24 \
    ipv4.gateway 10.0.1.1 \
    ipv4.dns "8.8.8.8 8.8.4.4" \
    ipv4.dns-search "example.com" \
    ipv6.method disabled

# DHCP bağlantısı
nmcli connection add type ethernet \
    con-name eth1-dhcp \
    ifname eth1 \
    ipv4.method auto

# Bağlantı düzenleme
nmcli connection modify eth0-static ipv4.dns "1.1.1.1 1.0.0.1"
nmcli connection modify eth0-static +ipv4.dns 8.8.8.8
nmcli connection modify eth0-static -ipv4.dns 8.8.8.8
nmcli connection modify eth0-static ipv4.addresses 10.0.1.101/24

# MTU ayarı
nmcli connection modify eth0-static ethernet.mtu 9000

# Bağlantı aktivasyonu
nmcli connection up eth0-static
nmcli connection down eth0-static
nmcli connection reload
nmcli device reapply eth0

# Bağlantı silme
nmcli connection delete eth0-static

# VLAN yapılandırma
nmcli connection add type vlan \
    con-name vlan100 \
    ifname vlan100 \
    dev eth0 \
    id 100 \
    ipv4.method manual \
    ipv4.addresses 192.168.100.10/24

# Bridge yapılandırma
nmcli connection add type bridge \
    con-name br0 \
    ifname br0 \
    ipv4.method manual \
    ipv4.addresses 192.168.1.1/24

nmcli connection add type ethernet \
    slave-type bridge \
    con-name br0-eth0 \
    ifname eth0 \
    master br0

# Team (bonding alternatifi)
nmcli connection add type team \
    con-name team0 \
    ifname team0 \
    team.runner activebackup \
    ipv4.method manual \
    ipv4.addresses 10.0.1.50/24

nmcli connection add type ethernet \
    slave-type team \
    con-name team0-eth0 \
    ifname eth0 \
    master team0
```
**Ağ Sorun Giderme:**

```bash
# IP bilgileri
ip addr show
ip route show
ip -s link show eth0  # İstatistikler

# DNS test
nslookup google.com
dig google.com
host google.com

# Bağlantı testi
ping -c 4 8.8.8.8
ping6 -c 4 2001:4860:4860::8888
traceroute google.com
mtr google.com

# Port testi
telnet google.com 80
nc -zv google.com 443
curl -v https://google.com

# Network interface istatistikleri
ethtool eth0
ethtool -S eth0  # Detailed stats

# ARP tablosu
ip neigh show
arp -n

# Socket durumu
ss -tulpn
ss -tunap
netstat -tulpn
```
### 3.2 firewalld Detaylı Kullanım

**Zone Kavramı:**

```bash
# Mevcut zone'ları listele
firewall-cmd --get-zones

# Aktif zone'lar
firewall-cmd --get-active-zones

# Default zone
firewall-cmd --get-default-zone
firewall-cmd --set-default-zone=public

# Zone detayları
firewall-cmd --zone=public --list-all
firewall-cmd --list-all-zones

**💡 FIREWALL-CMD - GÜVENLİK DUVARI YÖNETİMİ**
- **--list-all:** Mevcut zone konfigürasyonunu gösterir
- **Zone Nedir:** Ağ arayüzleri için güvenlik profili
- **Default Zone:** public (en kısıtlayıcı)


# Zone oluşturma
firewall-cmd --permanent --new-zone=myzone
firewall-cmd --reload

# Zone silme
firewall-cmd --permanent --delete-zone=myzone
```
**Zone Güvenlik Seviyeleri:**

```
trusted  → Tüm trafik kabul (no filtering)
home     → Ev ağı, güvenilir
internal → İç ağ
work     → İş yeri ağı
public   → Genel ağlar (default)
external → Dış ağ, NAT zone
dmz      → DMZ, sınırlı servisler
block    → Tüm trafik reddedilir (icmp-host-prohibited)
drop     → Tüm trafik sessizce düşürülür
```
**Temel firewalld Operasyonlar:**

```bash
# Servis ekleme/çıkarma
firewall-cmd --zone=public --add-service=http
firewall-cmd --zone=public --add-service=https
firewall-cmd --zone=public --remove-service=ssh
firewall-cmd --zone=public --list-services

# Port ekleme/çıkarma
firewall-cmd --zone=public --add-port=8080/tcp
firewall-cmd --zone=public --add-port=50000-50100/udp
firewall-cmd --zone=public --remove-port=8080/tcp
firewall-cmd --zone=public --list-ports

# Kalıcı kural
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --reload

# Her iki modu da güncelleme
firewall-cmd --add-service=mysql

**💡 SERVICE AÇMA - ÖN TANIMLI KURALLAR**
- **Fark:** add-port tek port, add-service tanımlı kural seti
- **Örnekler:** http (80), https (443), ssh (22)
- **Avantaj:** Birden fazla port ve protocol tek komutla

firewall-cmd --permanent --add-service=mysql

# Runtime konfigürasyonu permanent yap
firewall-cmd --runtime-to-permanent

# Kaynak IP bazlı kurallar
firewall-cmd --zone=internal --add-source=192.168.1.0/24
firewall-cmd --zone=public --add-source=10.0.0.0/8
firewall-cmd --zone=internal --list-sources

# Interface'i zone'a atama
firewall-cmd --zone=dmz --change-interface=eth1
firewall-cmd --zone=dmz --add-interface=eth1
firewall-cmd --get-zone-of-interface=eth1

# Masquerade (NAT)
firewall-cmd --zone=external --add-masquerade
firewall-cmd --zone=external --query-masquerade

# Direct rules (iptables benzeri)
firewall-cmd --direct --add-rule ipv4 filter INPUT 0 -p tcp --dport 9000 -j ACCEPT
```
**Rich Rules:**

```bash
# Belirli IP'den SSH izni
firewall-cmd --add-rich-rule='rule family="ipv4" source address="203.0.113.10" service name="ssh" accept'

# IP aralığından HTTP izni
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" service name="http" accept'

# Port forwarding
firewall-cmd --add-rich-rule='rule family="ipv4" forward-port port="80" protocol="tcp" to-port="8080"'
firewall-cmd --add-rich-rule='rule family="ipv4" forward-port port="80" protocol="tcp" to-port="8080" to-addr="10.0.1.50"'

# IP aralığını blokla
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.50.0/24" reject'
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.50.0/24" drop'

# Rate limiting
firewall-cmd --add-rich-rule='rule service name="ssh" limit value="10/m" accept'
firewall-cmd --add-rich-rule='rule service name="http" limit value="100/s" accept'

# Logging
firewall-cmd --add-rich-rule='rule service name="http" log prefix="HTTP: " level="info" limit value="5/m" accept'
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" log prefix="INTERNAL: " level="info" accept'

# Time-based rules
firewall-cmd --add-rich-rule='rule family="ipv4" source address="192.168.1.0/24" service name="http" log prefix="HTTP-ALLOW: " level="info" limit value="3/m" accept'

# Protocol-based
firewall-cmd --add-rich-rule='rule protocol value="icmp" accept'
firewall-cmd --add-rich-rule='rule protocol value="igmp" accept'

# Rich rules listeleme
firewall-cmd --list-rich-rules
firewall-cmd --list-all

**💡 FIREWALL-CMD - GÜVENLİK DUVARI YÖNETİMİ**
- **--list-all:** Mevcut zone konfigürasyonunu gösterir
- **Zone Nedir:** Ağ arayüzleri için güvenlik profili
- **Default Zone:** public (en kısıtlayıcı)

```
**IPSet ile Toplu IP Yönetimi:**

```bash
# IPSet oluştur
firewall-cmd --permanent --new-ipset=blacklist --type=hash:ip
firewall-cmd --permanent --new-ipset=whitelist --type=hash:net

# IP ekle
firewall-cmd --permanent --ipset=blacklist --add-entry=192.168.1.100
firewall-cmd --permanent --ipset=whitelist --add-entry=10.0.0.0/8

# IPSet'i rule'da kullan
firewall-cmd --permanent --add-rich-rule='rule source ipset="blacklist" drop'
firewall-cmd --permanent --add-rich-rule='rule source ipset="whitelist" accept'

firewall-cmd --reload
```
**firewalld Troubleshooting:**

```bash
# Log seviyesi artır
firewall-cmd --set-log-denied=all

# Logları izle
journalctl -f -u firewalld
tail -f /var/log/messages | grep -i kernel

# Panic mode (tüm ağı kapat)
firewall-cmd --panic-on
firewall-cmd --query-panic
firewall-cmd --panic-off

# Test modu
firewall-cmd --check-config
firewall-cmd --reload --check

# Backup/Restore
cp -r /etc/firewalld /etc/firewalld.backup
```
### 3.3 nftables (Firewalld Backend)

**nftables İnceleme:**

```bash
# Mevcut ruleset
nft list ruleset
nft list table inet firewalld
nft list chain inet firewalld filter_IN_public

# Counters
nft list ruleset -a
```
- - -

## 4\) Sorun Giderme ve Performans

### 4.1 Sistem Performans Metrikleri

**USE Method (Utilization, Saturation, Errors):**

```
┌───────────────────────────────────────────────┐
│            Resource Monitoring                │
├──────────┬────────────┬────────────┬──────────┤
│ Resource │Utilization │ Saturation │  Errors  │
├──────────┼────────────┼────────────┼──────────┤
│   CPU    │   %user    │ Run queue  │    ?     │
│          │   %sys     │   length   │          │
├──────────┼────────────┼────────────┼──────────┤
│  Memory  │   Used     │  Swapping  │  OOM     │
│          │ vs Total   │  si/so     │  kills   │
├──────────┼────────────┼────────────┼──────────┤
│  Disk    │   %util    │  Avg wait  │   Errors │
│    I/O   │    IOPS    │   (await)  │  in dmesg│
├──────────┼────────────┼────────────┼──────────┤
│ Network  │ Bandwidth  │   Drops    │  Errors  │
│          │   usage    │  Overruns  │ in ifcfg │
└──────────┴────────────┴────────────┴──────────┘
```
**CPU Analizi:**

```bash
# Genel CPU durumu
top
htop
atop

# CPU core bazlı
mpstat -P ALL 2 5
sar -u ALL 2 5

# Load average
uptime
cat /proc/loadavg
w

# Context switch izleme
vmstat 1 10
sar -w 2 5

# CPU çalan process'leri bul
ps aux --sort=-%cpu | head -20
top -b -n 1 | head -20
pidstat -u 2 5

# Per-thread CPU
ps -eLf
top -H

# CPU affinity
taskset -c -p <PID>
```
**Memory Analizi:**

```bash
# Memory durumu
free -h
free -m -s 2  # 2 saniye aralıkla

# Detaylı memory bilgisi
cat /proc/meminfo | head -20
vmstat -s
sar -r 2 5

# Memory çalan process'ler
ps aux --sort=-%mem | head -20
pmap -x <PID>
smem -rs uss

# Swap kullanımı
swapon --show
cat /proc/swaps
vmstat -s | grep swap

# OOM killer logları
journalctl -k | grep -i "oom"
dmesg | grep -i "oom"
grep -i "killed process" /var/log/messages

# Slab cache
slabtop
cat /proc/slabinfo | head -20

# Memory leak tespiti
valgrind --leak-check=full ./myapp
```
**Disk I/O Analizi:**

```bash
# Real-time I/O monitoring
iostat -xz 2
iostat -xz -p sda 2

# Process bazlı I/O
iotop -oPa
pidstat -d 2 5

# Disk saturation
iostat -x 2 | awk '$10 > 80'

# I/O scheduler kontrol
cat /sys/block/sda/queue/scheduler
echo "mq-deadline" > /sys/block/sda/queue/scheduler
# none, mq-deadline, bfq, kyber

# fio ile disk performans testi
fio --name=random-write --ioengine=libaio --rw=randwrite --bs=4k --size=1G --numjobs=4 --runtime=60 --group_reporting
```
**Network Analizi:**

```bash
# Network istatistikleri
ip -s link
netstat -i
sar -n DEV 2 5

# Bandwidth monitoring
iftop -i eth0
nload eth0
bmon

# Connection tracking
ss -s
ss -tunap
netstat -anp

# Packet loss
ping -c 100 8.8.8.8 | tail -5
mtr --report --report-cycles 100 google.com

# tcpdump
tcpdump -i eth0 port 80
tcpdump -i eth0 host 192.168.1.100
tcpdump -i eth0 -w capture.pcap
```
### 4.2 systemd-analyze ile Boot Performansı

```bash
# Boot zamanı
systemd-analyze
systemd-analyze time

# En yavaş servisler
systemd-analyze blame

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Boot sırasında en yavaş başlayan servisleri listeler
- **Kullanım:** Boot süresini optimize etme
- **Analiz:** Hangi servisler boot'u yavaşlatıyor gösterir
- **Senaryo:** Sunucu açılışı çok uzun sürüyor, darboğazları bulup optimize edin

# Critical path
systemd-analyze critical-chain

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Boot sırasındaki dependency zincirini ve gecikmeleri gösterir
- **Fark:** blame=en yavaş servisler, critical-chain=dependency darboğazı
- **Görsel:** ASCII tree formatında bağımlılık zinciri
- **Senaryo:** Hangi servis diğerlerini bekliyor, sıralama optimizasyonu
systemd-analyze critical-chain sshd.service

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Boot sırasındaki dependency zincirini ve gecikmeleri gösterir
- **Fark:** blame=en yavaş servisler, critical-chain=dependency darboğazı
- **Görsel:** ASCII tree formatında bağımlılık zinciri
- **Senaryo:** Hangi servis diğerlerini bekliyor, sıralama optimizasyonu

# Grafik oluştur
systemd-analyze plot > boot.svg

# Dependency grafiği
systemd-analyze dot | dot -Tsvg > dependencies.svg

# Security analizi
systemd-analyze security
systemd-analyze security sshd.service
```
### 4.3 strace ve ltrace ile Debugging

```bash
# System call trace
strace ls
strace -c ls  # Summary
strace -p <PID>  # Running process
strace -f -p <PID>  # Include child processes
strace -tt -T ls  # Timestamps and duration
strace -e open,read,write ls
strace -o output.txt ls

# Library call trace
ltrace ls
ltrace -p <PID>
ltrace -c ls
```
### 4.4 perf ile Profiling

```bash
# CPU profiling
perf record -a sleep 10
perf report

# Process profiling
perf record -p <PID> sleep 30
perf report

# Function profiling
perf record -g ./myapp
perf report --stdio

# CPU events
perf list
perf stat ls
perf stat -e cpu-cycles,instructions ls
```
### 4.5 Yaygın Sorunlar ve Çözümler

**Out of Memory (OOM):**

```bash
# OOM killer'ı kontrol et
dmesg | grep -i "out of memory"
journalctl -k | grep -i "oom"

# Memory limitleri artır (cgroup v2)
echo "memory.high 1G" > /sys/fs/cgroup/myapp.slice/memory.high
echo "memory.max 2G" > /sys/fs/cgroup/myapp.slice/memory.max

# Swap ekle
dd if=/dev/zero of=/swapfile bs=1M count=4096
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# Process OOM score ayarla
echo -1000 > /proc/<PID>/oom_score_adj  # -1000 = never kill
```
**High Load Average:**

```bash
# Load source tespiti
uptime
top
htop

# CPU bound mı, I/O bound mu?
iostat -x 2 5
vmstat 2 5

# Process analizi
ps aux --sort=-pcpu
ps aux --sort=-vsz

# Uninterruptible sleep (D state) processes
ps aux | awk '$8 ~ /D/ { print }'
```
**Disk Full:**

```bash
# Disk kullanımı
df -h
du -sh /*
du -sh /var/* | sort -h

# Büyük dosyaları bul
find / -type f -size +100M -exec ls -lh {} \;
find / -type f -size +100M 2>/dev/null | xargs ls -lh

# Deleted but open files
lsof | grep deleted
lsof +L1

# Journal temizle
journalctl --vacuum-size=100M
```
**Yavaş Ağ:**

```bash
# Bandwidth test
iperf3 -s  # Server
iperf3 -c server_ip  # Client

# MTU problemi
ping -M do -s 1472 8.8.8.8
tracepath google.com

# DNS problemi
time nslookup google.com
cat /etc/resolv.conf
```
- - -

## 5\) Podman Temelleri ve Mimari

### 5.1 Podman vs Docker

**Temel Farklar:**


|Özellik             |Podman                    |Docker                |
|--------------------|--------------------------|----------------------|
|**Mimari**          |Daemonless                |Daemon-based          |
|**Root Gereksinimi**|Rootless çalışabilir      |Root gerektirir       |
|**systemd Entegrasyonu**|Native                    |Sınırlı               |
|**Pod Desteği**     |✅ Native                  |❌ Yok                 |
|**OCI Uyumluluğu**  |✅ Tam                     |✅ Tam                 |
|**Docker-compose**  |❌ Yok (podman-compose var)|✅ Var                 |
|**Swarm**           |❌ Yok                     |✅ Var                 |
|**Socket**          |UNIX socket               |TCP socket            |
|**RHEL Default**    |✅ Evet                    |❌ Hayır               |
|**Güvenlik**        |Rootless, SELinux         |Root, optional SELinux|

**Podman Mimarisi:**

```
┌─────────────────────────────────────────────┐
│         User / CLI Interface                │
│           podman, buildah                   │
├─────────────────────────────────────────────┤
│              Conmon                         │
│      (Container Monitor)                    │
├─────────────────────────────────────────────┤
│              runc / crun                    │
│         (OCI Runtime)                       │
├─────────────────────────────────────────────┤
│         Linux Kernel Features               │
│  Namespaces, cgroups, SELinux, seccomp      │
└─────────────────────────────────────────────┘
```
**Docker vs Podman Komut Karşılaştırması:**

```bash
# Docker
docker run -d nginx
docker ps
docker build -t myapp .

# Podman (aynı komutlar)
podman run -d nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman ps

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı
podman build -t myapp .

# Docker alias oluştur
alias docker=podman
```
### 5.2 Podman Kurulum ve Temel Kullanım

**Kurulum:**

```bash
# RHEL 9 / AlmaLinux / Rocky Linux
dnf install -y podman podman-docker buildah skopeo

# Podman-compose (isteğe bağlı)
pip3 install podman-compose

# Sürüm kontrolü
podman --version
podman info

# Rootless setup kontrolü
podman info | grep -i rootless
loginctl enable-linger $USER
```
**Container Registry Yapılandırması:**

```bash
# Registry konfigürasyonu
cat /etc/containers/registries.conf

# Unqualified image search order
[registries.search]
registries = ["docker.io", "quay.io", "registry.access.redhat.com"]

# Insecure registry
[[registry]]
location = "registry.local:5000"
insecure = true

# Registry mirror
[[registry]]
location = "docker.io"
[[registry.mirror]]
location = "mirror.local:5000"
insecure = true
```
**Storage Yapılandırması:**

```bash
# Storage driver
cat /etc/containers/storage.conf

[storage]
driver = "overlay"
runroot = "/run/containers/storage"
graphroot = "/var/lib/containers/storage"

[storage.options]
additionalimagestores = []
pull_options = {enable_partial_images = "true"}

[storage.options.overlay]
mountopt = "nodev,metacopy=on"
```
### 5.3 Temel Container Operasyonları

**Image İşlemleri:**

```bash
# Image çekme
podman pull nginx:latest
podman pull quay.io/myorg/myapp:v1.0
podman pull docker.io/library/alpine:3.18

# Image listeleme
podman images
podman images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.Created}}"
podman images --filter "dangling=true"

# Image silme
podman rmi nginx:latest
podman rmi $(podman images -q)  # Tümünü sil
podman image prune  # Dangling images
podman image prune -a  # Unused images

# Image inspect
podman inspect nginx:latest

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect nginx:latest --format '{{.Config.Env}}'

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect nginx:latest --format '{{json .Config}}' | jq

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme

# Image history
podman history nginx:latest
podman history --no-trunc nginx:latest

# Image search
podman search nginx
podman search --limit 5 nginx
```
**Container Çalıştırma:**

```bash
# Basic run
podman run nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d nginx  # Detached

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --name web nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -it alpine sh  # Interactive

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Port mapping
podman run -d -p 8080:80 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d -p 127.0.0.1:8080:80 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d -p 8080:80 -p 8443:443 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Environment variables
podman run -d -e "APP_ENV=production" myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --env-file /path/to/env.list myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Resource limits
podman run -d --memory=512m --cpus=0.5 nginx

**💡 MEMORY LİMİT - OOM PREVENTİON**
- **Amaç:** Container'ın maximum memory kullanımını sınırlar
- **Neden Kritik:** Memory leak olan container host'u çökertebilir
- **--memory-swap:** Total memory+swap limiti
- **Production:** TÜM container'lara memory limit koyun


**💡 CPU LİMİT - RESOURCE SHARING**
- **Amaç:** Container'ın kullanabileceği CPU miktarını sınırlar
- **Format:** 1.5 = 1.5 CPU core, 0.5 = yarım core
- **Neden:** CPU-intensive container diğerlerini aç bırakmasın
- **Alternatif:** --cpu-shares (relative weight)


**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --memory-reservation=256m --memory=512m nginx

**💡 MEMORY LİMİT - OOM PREVENTİON**
- **Amaç:** Container'ın maximum memory kullanımını sınırlar
- **Neden Kritik:** Memory leak olan container host'u çökertebilir
- **--memory-swap:** Total memory+swap limiti
- **Production:** TÜM container'lara memory limit koyun


**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Restart policy
podman run -d --restart=always nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --restart=on-failure:3 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Hostname
podman run -d --hostname=webserver nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# DNS
podman run -d --dns=8.8.8.8 --dns-search=example.com nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Cleanup
podman run -d --rm nginx  # Auto-remove after exit

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```
**Container Yönetimi:**

```bash
# Container listeleme
podman ps

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı
podman ps -a

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı
podman ps --format "table {{.ID}}\t{{.Names}}\t{{.Status}}"

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı
podman ps --filter "status=running"

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı
podman ps --filter "name=web"

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı

# Container kontrol
podman start web
podman stop web
podman stop -t 30 web  # 30 saniye grace period
podman restart web
podman pause web
podman unpause web
podman kill web
podman kill -s SIGTERM web

# Container silme
podman rm web
podman rm -f web  # Force (running container)
podman container prune  # Stopped containers

# Container logs
podman logs web

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
podman logs -f web  # Follow

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
podman logs --tail 100 web

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
podman logs --since 1h web

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
podman logs --timestamps web

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme

# Container exec
podman exec web ls /usr/share/nginx/html

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
podman exec -it web bash

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
podman exec -u root web apt update

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma

# Container inspect
podman inspect web

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect web --format '{{.State.Status}}'

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect web --format '{{.NetworkSettings.IPAddress}}'

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect web --format '{{json .Mounts}}' | jq

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme

# Container stats
podman stats
podman stats --no-stream
podman stats web

# Container diff
podman diff web

# Container export/import
podman export web > web.tar
podman import web.tar myimage:latest

# Container commit
podman commit web myimage:v2
```
### 5.4 Rootless Podman

**Rootless Kurulum:**

```bash
# User namespace kontrolü
sysctl user.max_user_namespaces
# 0 ise enable et
echo "user.max_user_namespaces=15000" >> /etc/sysctl.conf
sysctl -p

# Subuid/subgid yapılandırması
grep $USER /etc/subuid /etc/subgid

# Yoksa ekle
usermod --add-subuids 100000-165535 $USER
usermod --add-subgids 100000-165535 $USER

# Rootless container çalıştır
podman run -d -p 8080:80 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Port binding (< 1024)
# Rootless kullanıcılar privileged portları kullanamaz
# Çözüm 1: Yüksek port kullan (8080, 8443)
# Çözüm 2: setcap ile capability ver
# Çözüm 3: Reverse proxy kullan (nginx, haproxy)

# Persistent service (user systemd)
mkdir -p ~/.config/systemd/user/
podman generate systemd --new --files --name web
mv container-web.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now container-web.service

# Linger enable (boot'ta başlat)
loginctl enable-linger $USER
loginctl show-user $USER | grep Linger
```
**Rootless Sınırlamalar:**

- Privileged port binding yapılamaz (< 1024)
- Ping çalışmaz (CAP_NET_RAW yok)
- Bazı volume mount'lar sorunlu olabilir
- Performance overhead var (user namespace)

### 5.5 Image Build

**Dockerfile Örnekleri:**

```dockerfile
# Basit Dockerfile
FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL maintainer="admin@example.com" \
      version="1.0" \
      description="My Application"

RUN dnf install -y httpd && \
    dnf clean all

COPY index.html /var/www/html/
COPY --chown=apache:apache app.conf /etc/httpd/conf.d/

EXPOSE 80

USER apache

CMD ["/usr/sbin/httpd", "-DFOREGROUND"]
# Multi-stage build
FROM golang:1.21 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o myapp .

FROM alpine:latest
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/myapp .
EXPOSE 8080
CMD ["./myapp"]
# Node.js örneği
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

FROM node:18-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 3000
USER node
CMD ["node", "dist/server.js"]
```
**Image Build:**

```bash
# Build
podman build -t myapp:v1.0 .
podman build -t myapp:v1.0 -f Dockerfile.prod .
podman build --no-cache -t myapp:v1.0 .

# Build arguments
podman build --build-arg VERSION=1.2.3 -t myapp:v1.0 .

# Multi-platform build
podman build --platform linux/amd64,linux/arm64 -t myapp:v1.0 .

# Build secrets
echo "token=secret123" > mysecret.txt
podman build --secret id=mysecret,src=mysecret.txt -t myapp:v1.0 .

# Dockerfile'da kullan
# RUN --mount=type=secret,id=mysecret cat /run/secrets/mysecret

# Image history
podman history myapp:v1.0

# Image save/load
podman save -o myapp.tar myapp:v1.0
gzip myapp.tar
podman load -i myapp.tar.gz
```
**Buildah ile Advanced Build:**

```bash
# Scratch'ten container
newcontainer=$(buildah from scratch)
scratchmnt=$(buildah mount $newcontainer)

# Package install
dnf install --installroot $scratchmnt --releasever 9 \
    --setopt install_weak_deps=false --nodocs -y \
    bash coreutils httpd

buildah unmount $newcontainer

# Config
buildah config --port 80 $newcontainer
buildah config --cmd '/usr/sbin/httpd -DFOREGROUND' $newcontainer
buildah config --author 'admin@example.com' $newcontainer
buildah config --label version=1.0 $newcontainer

# Commit
buildah commit $newcontainer myapp:buildah

# Push
buildah push myapp:buildah docker://quay.io/myorg/myapp:v1.0
```
### 5.6 Volumes ve Bind Mounts

**Volume Types:**

```bash
# Named volume
podman volume create mydata

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Persistent storage için named volume oluşturur
- **Fark:** Bind mount vs volume - volume'lar Podman yönetir
- **Avantaj:** Volume'lar taşınabilir, backup'lanabilir
- **Senaryo:** Database verisi container silinse bile kalmalı
podman volume ls
podman volume inspect mydata

podman run -d --name db \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -v mydata:/var/lib/postgresql/data \
  postgres:15

# Anonymous volume
podman run -d --name db \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -v /var/lib/postgresql/data \
  postgres:15

# Bind mount
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -v /opt/website:/usr/share/nginx/html:ro \
  nginx

# Read-write
podman run -d --name app \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -v /data:/app/data:rw \
  myapp

# Tmpfs mount
podman run -d --name app \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  myapp

# Volume from another container
podman run -d --name app1 -v data:/data myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --name app2 --volumes-from app1 myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Volume cleanup
podman volume prune
podman volume rm mydata
podman volume rm $(podman volume ls -q)
```
**SELinux ve Volumes:**

```bash
# SELinux context sorunları
podman run -d -v /data:/data myapp
# Permission denied hatası

# Çözüm 1: Private label (her container'a özel)
podman run -d -v /data:/data:Z myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Çözüm 2: Shared label (container'lar arası paylaşım)
podman run -d -v /data:/data:z myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# SELinux kontrol
ls -lZ /data
# drwxr-xr-x. 2 root root system_u:object_r:container_file_t:s0:c123,c456 ...

# Manuel context ayarlama
chcon -R -t container_file_t /data
restorecon -R /data

**💡 RESTORECON - CONTEXT RESTORE**
- **Amaç:** Dosya context'ini policy'e göre düzeltir
- **Ne Zaman:** Manuel chcon sonrası veya file move sonrası
- **-R flag:** Recursive, tüm alt dizinleri düzelt


# SELinux audit log
ausearch -m avc -ts recent | grep podman
```
- - -

## 6\) Podman İleri Seviye Networking

### 6.1 Network Modları

**Bridge Network (Default):**

```bash
# Varsayılan bridge
podman network ls

**💡 NETWORK LS - AĞ LİSTELEME**
- **Ne Gösterir:** Mevcut network'ler, driver tipi, subnet
- **Default Networks:** podman (bridge), host, none
- **Kullanım:** Container neden network'e erişemiyor debug'u

# NETWORK ID    NAME        DRIVER
# 2f259bab93aa  podman      bridge

# Container'ları listele
podman network inspect podman

**💡 NETWORK INSPECT - AĞ DETAYLARI**
- **Amaç:** Network config detaylarını JSON olarak gösterir
- **Bilgiler:** Subnet, gateway, DNS servers, connected containers
- **Debug:** Hangi container'lar bu network'e bağlı?


# Custom bridge
podman network create --driver bridge mynet

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır

podman network create --subnet 10.88.0.0/16 --gateway 10.88.0.1 mynet

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır

podman network create --subnet 10.88.0.0/16 --ip-range 10.88.5.0/24 mynet

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır


# IPv6 desteği
podman network create --ipv6 --subnet 2001:db8::/64 mynet6

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır


# Custom DNS
podman network create --dns 8.8.8.8 --dns 8.8.4.4 mynet

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır


# Container'ı network'e bağla
podman run -d --name web --network mynet nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --name db --network mynet postgres

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Container içinden diğer container'a erişim
podman exec web ping db  # Hostname ile erişim

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
podman exec web curl http://db:5432

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma

# Network inspect
podman network inspect mynet

**💡 NETWORK INSPECT - AĞ DETAYLARI**
- **Amaç:** Network config detaylarını JSON olarak gösterir
- **Bilgiler:** Subnet, gateway, DNS servers, connected containers
- **Debug:** Hangi container'lar bu network'e bağlı?


# Multiple networks
podman run -d --name app --network mynet --network frontend nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Network disconnect/connect
podman network disconnect mynet web
podman network connect mynet web

# IP belirle
podman run -d --name web --network mynet --ip 10.88.0.100 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# MAC address
podman run -d --name web --network mynet --mac-address 02:42:ac:11:00:02 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Network silme
podman network rm mynet
podman network prune
```
**Host Network:**

```bash
# Host network kullanımı
podman run -d --network host nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Container host network'ü kullanır
# Port mapping gerekmiyor
# Performance avantajı var
# Güvenlik riski var (host network'e doğrudan erişim)

curl http://localhost:80
```
**None Network:**

```bash
# Ağ izolasyonu
podman run -d --network none alpine sleep 3600

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Container ağa erişemez
# Loopback (127.0.0.1) kullanılabilir
```
**Slirp4netns (Rootless default):**

```bash
# Rootless container'lar için user-mode networking
podman run -d -p 8080:80 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Port mapping: host:8080 -> slirp4netns -> container:80
```
### 6.2 Pod Kullanımı

**Pod Kavramı:**

Pod, Kubernetes'ten gelen bir konsepttir. Aynı network namespace'i paylaşan
container'lar grubudur.

```
┌────────────────────────────────┐
│           Pod: webapp          │
│   ┌──────────┐   ┌──────────┐  │
│   │          │   │          │  │
│   │  nginx   │   │   app    │  │
│   │ (port 80)│   │(port 8080│  │
│   │          │   │          │  │
│   └──────────┘   └──────────┘  │
│                                │
│   Shared: Network, IPC, UTS    │
│   Pod IP: 10.88.0.10           │
└────────────────────────────────┘
```
**Pod Oluşturma:**

```bash
# Pod oluşturma
podman pod create --name webapp -p 8080:80 -p 8443:443

# Pod'a container ekleme
podman run -d --pod webapp --name nginx nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --pod webapp --name app myapp:v1.0

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --pod webapp --name redis redis

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Pod içindeki container'lar
# - Aynı network namespace (localhost ile iletişim)
# - Aynı IPC namespace
# - Aynı UTS namespace (hostname)

# App container'dan nginx'e erişim
podman exec app curl http://localhost:80

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma

# Pod listeleme
podman pod ls
podman pod ps

# Pod içindeki container'ları göster
podman ps --pod

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı

# Pod yönetimi
podman pod start webapp
podman pod stop webapp
podman pod restart webapp
podman pod pause webapp
podman pod unpause webapp

# Pod inspect
podman pod inspect webapp
podman pod inspect webapp --format '{{.InfraContainerID}}'

# Infra container
# Her pod'un bir infra (pause) container'ı var
# Bu container network namespace'i tutar
podman ps -a --filter "pod=webapp"

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı

# Pod silme
podman pod rm webapp
podman pod rm -f webapp  # Force

# Pod logs
podman pod logs webapp
```
**Kubernetes YAML ile Pod:**

```yaml
# webapp-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  labels:
    app: webapp
    env: production
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
      hostPort: 8080
    volumeMounts:
    - name: nginx-conf
      mountPath: /etc/nginx/nginx.conf
      subPath: nginx.conf
    
  - name: app
    image: quay.io/myorg/myapp:v1.0
    env:
    - name: DATABASE_URL
      value: "postgresql://db.local:5432/mydb"
    - name: REDIS_URL
      value: "redis://localhost:6379"
    resources:
      limits:
        memory: "512Mi"
        cpu: "500m"
      requests:
        memory: "256Mi"
        cpu: "250m"
    
  - name: redis
    image: redis:7-alpine
    command: ["redis-server"]
    args: ["--appendonly", "yes"]
    
  volumes:
  - name: nginx-conf
    hostPath:
      path: /opt/webapp/nginx.conf
      type: File
# Pod deployment
podman play kube webapp-pod.yaml

# Generate YAML from pod
podman generate kube webapp > webapp-pod.yaml

# Pod'u güncelle
# YAML'i düzenle
podman play kube webapp-pod.yaml

# Pod remove
podman play kube --down webapp-pod.yaml
```
### 6.3 Advanced Networking

**Multi-network Container:**

```bash
# İki network oluştur
podman network create frontend --subnet 10.10.0.0/24

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır

podman network create backend --subnet 10.20.0.0/24

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır


# Container'ı her iki network'e bağla
podman run -d --name app \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --network frontend \
  --network backend \
  myapp

# Container'ın iki IP adresi var
podman inspect app --format '{{.NetworkSettings.Networks}}'

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme

# Runtime'da network ekle/çıkar
podman network connect backend app
podman network disconnect frontend app
```
**Custom DNS:**

```bash
# Container DNS
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --dns 8.8.8.8 \
  --dns 1.1.1.1 \
  --dns-search example.com \
  --dns-option ndots:2 \
  nginx

# /etc/hosts entry
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --add-host db.local:10.0.1.50 \
  --add-host cache.local:10.0.1.51 \
  nginx

# Verify
podman exec web cat /etc/resolv.conf

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
podman exec web cat /etc/hosts

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
```
**Port Mapping Advanced:**

```bash
# Multiple ports
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -p 8080:80 \
  -p 8443:443 \
  -p 9090:9090 \
  nginx

# Random host port
podman run -d --name web -p 80 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman port web

# UDP port
podman run -d --name dns -p 53:53/udp nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Specific interface
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -p 192.168.1.100:8080:80 \
  nginx
```
**Network Aliases:**

```bash
# Alias ile erişim
podman run -d --name web1 \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --network mynet \
  --network-alias web \
  nginx

podman run -d --name web2 \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --network mynet \
  --network-alias web \
  nginx

# Her iki container da "web" hostname'i ile erişilebilir
podman run --rm --network mynet alpine ping web
# Round-robin DNS
```
**Macvlan Network:**

```bash
# Macvlan oluştur
podman network create -d macvlan \

**💡 NETWORK CREATE - ÖZEL AĞ OLUŞTURMA**
- **Amaç:** Container'lar için izole network oluşturur
- **Neden:** Default bridge yerine özel subnet, DNS, isolation
- **Bridge vs Host:** Bridge=izole, Host=host network kullan
- **Senaryo:** Frontend ve backend container'larını ayır

  --subnet 192.168.1.0/24 \
  --gateway 192.168.1.1 \
  -o parent=eth0 \
  macvlan1

# Container doğrudan fiziksel ağda
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --network macvlan1 \
  --ip 192.168.1.100 \
  nginx

# Host'tan erişim yok (macvlan sınırlaması)
```
- - -

## 7\) Podman Kalıcılık: systemd ve Quadlet

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


### 7.1 systemd ile Container Yönetimi

**Generate systemd Unit:**

```bash
# Container oluştur
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  -p 8080:80 \
  -v /opt/website:/usr/share/nginx/html:Z \
  nginx

# Unit dosyası oluştur
podman generate systemd --new --files --name web

# Oluşan dosya: container-web.service
cat container-web.service

# Root için
sudo mv container-web.service /etc/systemd/system/

# Rootless için
mkdir -p ~/.config/systemd/user/
mv container-web.service ~/.config/systemd/user/

# Enable ve start
sudo systemctl daemon-reload

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** systemd'nin configuration dosyalarını yeniden okumasını sağlar
- **Ne Zaman:** Unit dosyası (.service, .socket vb.) oluşturduğunuzda veya düzenlediğinizde
- **Neden Gerekli:** systemd dosyaları cache'ler, bu komut olmadan değişiklikler aktif olmaz
- **Senaryo:** `/etc/systemd/system/myapp.service` dosyasını oluşturduktan sonra MUTLAKA çalıştırın
sudo systemctl enable container-web.service
sudo systemctl start container-web.service
sudo systemctl status container-web.service

# Rootless
systemctl --user daemon-reload
systemctl --user enable container-web.service
systemctl --user start container-web.service

# Linger enable (boot'ta başlat)
sudo loginctl enable-linger $USER
```
**Custom systemd Unit:**

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My Application Container
After=network-online.target
Wants=network-online.target
Requires=container-db.service
Before=nginx.service

[Service]
Type=notify
NotifyAccess=all

# Container yönetimi
ExecStartPre=/usr/bin/podman pull quay.io/myorg/myapp:latest
ExecStart=/usr/bin/podman run \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --rm \
  --name myapp \
  --network=host \
  -v /opt/app/data:/data:Z \
  -e APP_ENV=production \
  --health-cmd="curl -f http://localhost:8080/health || exit 1" \

**💡 HEALTH CHECK - LIVENESS PROBE**
- **Amaç:** Container'ın healthy olup olmadığını otomatik kontrol
- **Çalışma:** Belirtilen komutu periyodik çalıştırır
- **Exit 0:** Healthy, diğer değerler=unhealthy
- **Restart Policy:** Unhealthy container otomatik restart edilir

  --health-interval=30s \
  --health-timeout=10s \
  --health-retries=3 \
  quay.io/myorg/myapp:latest

ExecStop=/usr/bin/podman stop -t 10 myapp
ExecStopPost=/usr/bin/podman rm -f myapp

Restart=on-failure
RestartSec=30s
TimeoutStartSec=300
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
```
**Pod için systemd:**

```bash
# Pod oluştur
podman pod create --name webapp -p 8080:80

podman run -d --pod webapp --name nginx nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --pod webapp --name app myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Pod için unit oluştur
podman generate systemd --new --files --name webapp

# webapp-pod.service ve container-*.service dosyaları oluşur

sudo mv webapp-pod.service container-*.service /etc/systemd/system/

sudo systemctl daemon-reload

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** systemd'nin configuration dosyalarını yeniden okumasını sağlar
- **Ne Zaman:** Unit dosyası (.service, .socket vb.) oluşturduğunuzda veya düzenlediğinizde
- **Neden Gerekli:** systemd dosyaları cache'ler, bu komut olmadan değişiklikler aktif olmaz
- **Senaryo:** `/etc/systemd/system/myapp.service` dosyasını oluşturduktan sonra MUTLAKA çalıştırın
sudo systemctl enable webapp-pod.service
sudo systemctl start webapp-pod.service
```
### 7.2 Quadlet (Modern Yaklaşım)

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


**Quadlet Nedir:**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


Quadlet, Podman 4.4+ ile gelen native systemd entegrasyonudur. `.container`, `

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

.volume`, `.network`, `.kube` dosyaları ile systemd unit'leri otomatik oluşturur.

**Quadlet Container:**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


```ini
# /etc/containers/systemd/myapp.container
[Unit]
Description=My Application Container
After=network-online.target
Wants=network-online.target

[Container]
Image=quay.io/myorg/myapp:latest
PublishPort=8080:8080
Volume=/opt/data:/data:Z
Volume=myapp-cache:/cache:Z
Environment=DATABASE_URL=postgresql://db.local/mydb
Environment=APP_ENV=production
EnvironmentFile=/etc/myapp/env

# Auto update
AutoUpdate=registry

# Network
Network=mynet

# Security
SecurityLabelDisable=false
User=1000:1000

# Health check
HealthCmd=curl -f http://localhost:8080/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthRetries=3

[Service]
Restart=always
TimeoutStartSec=900
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target default.target
# Systemd reload (Quadlet generator çalışır)

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

sudo systemctl daemon-reload

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** systemd'nin configuration dosyalarını yeniden okumasını sağlar
- **Ne Zaman:** Unit dosyası (.service, .socket vb.) oluşturduğunuzda veya düzenlediğinizde
- **Neden Gerekli:** systemd dosyaları cache'ler, bu komut olmadan değişiklikler aktif olmaz
- **Senaryo:** `/etc/systemd/system/myapp.service` dosyasını oluşturduktan sonra MUTLAKA çalıştırın

# Otomatik oluşan service
sudo systemctl status myapp.service

# Enable ve start
sudo systemctl enable --now myapp.service

# Logs
journalctl -u myapp.service -f

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Servis log'larını gerçek zamanlı izler (tail -f benzeri)
- **Kullanım:** Deployment sonrası canlı izleme, hata ayıklama
- **Avantaj:** Structured logging, renklendirme, filtreleme
- **Senaryo:** Yeni versiyonu deploy ettiniz, uygulama düzgün başladı mı kontrol ediyorsunuz

# Auto-update (image güncellemelerini çeker)
podman auto-update
```
**Quadlet Pod (Kubernetes YAML):**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


```yaml
# /etc/containers/systemd/webapp-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: webapp
spec:
  containers:
  - name: nginx
    image: nginx:latest
    ports:
    - containerPort: 80
      hostPort: 8080
      
  - name: app
    image: myapp:v1.0
    env:
    - name: DATABASE_URL
      value: postgresql://db/mydb
# /etc/containers/systemd/webapp.kube
[Unit]
Description=Web Application Pod
After=network-online.target

[Kube]
Yaml=/etc/containers/systemd/webapp-pod.yaml
AutoUpdate=registry

[Install]
WantedBy=multi-user.target
sudo systemctl daemon-reload

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** systemd'nin configuration dosyalarını yeniden okumasını sağlar
- **Ne Zaman:** Unit dosyası (.service, .socket vb.) oluşturduğunuzda veya düzenlediğinizde
- **Neden Gerekli:** systemd dosyaları cache'ler, bu komut olmadan değişiklikler aktif olmaz
- **Senaryo:** `/etc/systemd/system/myapp.service` dosyasını oluşturduktan sonra MUTLAKA çalıştırın
sudo systemctl enable --now webapp.service
```
**Quadlet Network:**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


```ini
# /etc/containers/systemd/mynet.network
[Network]
Subnet=10.88.0.0/16
Gateway=10.88.0.1
Label=app=production
```
**Quadlet Volume:**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


```ini
# /etc/containers/systemd/data.volume
[Volume]
Label=app=myapp
```
**Rootless Quadlet:**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


```bash
# User seviye için
mkdir -p ~/.config/containers/systemd/

# myapp.container dosyasını kopyala

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

cp myapp.container ~/.config/containers/systemd/

systemctl --user daemon-reload
systemctl --user enable --now myapp.service

# Linger
loginctl enable-linger $USER
```
### 7.3 Auto-Update

```bash
# Auto-update label ekle
podman run -d --name web \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --label "io.containers.autoupdate=registry" \
  nginx:latest

# Systemd timer ile otomatik güncelleme
sudo systemctl enable --now podman-auto-update.timer

# Manuel güncelleme
sudo podman auto-update

# Dry-run
sudo podman auto-update --dry-run

# Auto-update logları
journalctl -u podman-auto-update.service
```
- - -

## 8\) Container Registry Yönetimi

### 8.1 Public Registry Kullanımı

**Registry Konfigürasyonu:**

```bash
# Registry listesi
cat /etc/containers/registries.conf

[registries.search]
registries = ["docker.io", "quay.io", "registry.access.redhat.com"]

[registries.insecure]
registries = ["registry.local:5000"]

[[registry]]
location = "docker.io"
blocked = false

[[registry.mirror]]
location = "mirror.local:5000"
insecure = true
```
**Registry Login:**

```bash
# Docker Hub
podman login docker.io
podman login -u username -p password docker.io

# Quay.io
podman login quay.io

# Private registry
podman login registry.local:5000 -u admin

# Credential storage
cat ~/.config/containers/auth.json
cat /run/user/$(id -u)/containers/auth.json

# Logout
podman logout docker.io
podman logout --all
```
**Image Push/Pull:**

```bash
# Pull
podman pull docker.io/library/nginx:latest
podman pull quay.io/myorg/myapp:v1.0

# Tag
podman tag myapp:v1.0 quay.io/myorg/myapp:v1.0

# Push
podman push quay.io/myorg/myapp:v1.0

# Multi-arch manifest
podman manifest create myapp:latest
podman manifest add myapp:latest myapp:amd64
podman manifest add myapp:latest myapp:arm64
podman manifest push myapp:latest docker://quay.io/myorg/myapp:latest
```
### 8.2 Local Registry Setup

**Basic Registry:**

```bash
# Registry container
podman run -d -p 5000:5000 \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name registry \
  --restart=always \
  -v registry-data:/var/lib/registry \
  docker.io/library/registry:2

# Test
curl http://localhost:5000/v2/_catalog

# Push image
podman tag nginx:latest localhost:5000/nginx:latest
podman push localhost:5000/nginx:latest

# Pull image
podman pull localhost:5000/nginx:latest
```
**TLS ile Registry:**

```bash
# Dizinler oluştur
mkdir -p /opt/registry/{certs,auth,data}

# Self-signed certificate
openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout /opt/registry/certs/domain.key \
  -x509 -days 365 \
  -out /opt/registry/certs/domain.crt \
  -subj "/CN=registry.local" \
  -addext "subjectAltName=DNS:registry.local,IP:192.168.1.100"

# Basic auth
dnf install -y httpd-tools
htpasswd -Bbn admin MyPassword123 > /opt/registry/auth/htpasswd

# Registry with TLS and Auth
podman run -d -p 5000:5000 \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name registry \
  --restart=always \
  -v /opt/registry/data:/var/lib/registry \
  -v /opt/registry/certs:/certs \
  -v /opt/registry/auth:/auth \
  -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/domain.crt \
  -e REGISTRY_HTTP_TLS_KEY=/certs/domain.key \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry Realm" \
  registry:2

# Trust certificate
sudo cp /opt/registry/certs/domain.crt /etc/pki/ca-trust/source/anchors/registry.local.crt
sudo update-ca-trust

# Test
curl https://registry.local:5000/v2/_catalog -u admin:MyPassword123

# Login
podman login registry.local:5000 -u admin

# Push/Pull
podman tag myapp:v1.0 registry.local:5000/myapp:v1.0
podman push registry.local:5000/myapp:v1.0
podman pull registry.local:5000/myapp:v1.0
```
**Registry Garbage Collection:**

```bash
# Registry içinde
podman exec -it registry registry garbage-collect /etc/docker/registry/config.yml

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma

# Dry-run
podman exec -it registry registry garbage-collect --dry-run /etc/docker/registry/config.yml

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
```
**Registry UI:**

```bash
# Docker Registry UI
podman run -d -p 8080:80 \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name registry-ui \
  -e REGISTRY_URL=https://registry.local:5000 \
  -e REGISTRY_TITLE="My Registry" \
  joxit/docker-registry-ui:latest
```
### 8.3 Skopeo ile Registry İşlemleri

**Skopeo Kullanımı:**

```bash
# Image inspect (pull etmeden)
skopeo inspect docker://docker.io/nginx:latest
skopeo inspect docker://quay.io/myorg/myapp:v1.0

# Image copy (registry'ler arası)
skopeo copy \
  docker://docker.io/nginx:latest \
  docker://registry.local:5000/nginx:latest

# Image copy (authentication ile)
skopeo copy \
  --src-creds user1:pass1 \
  --dest-creds user2:pass2 \
  docker://source.registry.com/app:v1 \
  docker://dest.registry.com/app:v1

# Local tarball'a copy
skopeo copy \
  docker://nginx:latest \
  docker-archive:/tmp/nginx.tar:nginx:latest

# OCI format
skopeo copy \
  docker://nginx:latest \
  oci:/tmp/nginx-oci:latest

# Image delete
skopeo delete docker://registry.local:5000/old-image:v1.0

# Image tags listele
skopeo list-tags docker://docker.io/library/nginx

# Image sync (multiple images)
skopeo sync \
  --src docker --dest dir \
  docker.io/nginx:latest \
  docker.io/alpine:latest \
  /tmp/images/
```
### 8.4 Harbor Registry

**Harbor Nedir:**

Harbor, CNCF graduated projedir. Enterprise-grade container registry'dir.
Vulnerability scanning, image signing, RBAC, replication gibi özellikleri
vardır.

**Harbor Kurulum (Podman ile):**

```bash
# Harbor compose dosyası
# Not: Harbor resmi olarak docker-compose kullanır
# Podman-compose ile çalışabilir ama production için önerilmez

# Alternatif: Harbor Helm chart ile Kubernetes'e deploy
# veya Harbor offline installer

# Basit test kurulumu
podman run -d -p 8080:8080 \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name harbor-jobservice \
  goharbor/harbor-jobservice:v2.9.0

# Production için Kubernetes/OpenShift önerilir
```
**Harbor Kullanımı:**

```bash
# Login
podman login harbor.local -u admin

# Project oluştur (UI'dan)

# Push
podman tag myapp:v1.0 harbor.local/myproject/myapp:v1.0
podman push harbor.local/myproject/myapp:v1.0

# Pull
podman pull harbor.local/myproject/myapp:v1.0
```
- - -

## 9\) Güvenlik: SELinux, Seccomp, Scanning

### 9.1 SELinux ve Containers

**SELinux Context:**

```bash
# Container label görüntüleme
podman inspect web | grep -i label

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect web -f '{{.ProcessLabel}}'

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman inspect web -f '{{.MountLabel}}'

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme

# Örnek çıktı:
# ProcessLabel: system_u:system_r:container_t:s0:c123,c456
# MountLabel: system_u:object_r:container_file_t:s0:c123,c456

# Custom label
podman run --security-opt label=level:s0:c100,c200 nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# SELinux devre dışı (ÖNERİLMEZ!)
podman run --security-opt label=disable nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# SELinux type
podman run --security-opt label=type:container_runtime_t nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```
**Volume SELinux Context:**

```bash
# Private label (:Z)
# Her container için unique context
podman run -d -v /data:/data:Z nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
ls -lZ /data
# drwxr-xr-x. root root system_u:object_r:container_file_t:s0:c123,c456 /data

# Shared label (:z)
# Birden fazla container paylaşabilir
podman run -d -v /data:/data:z nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
ls -lZ /data
# drwxr-xr-x. root root system_u:object_r:container_file_t:s0 /data

# No relabel
podman run -d -v /data:/data:ro nginx
# Existing context korunur
```
**SELinux Troubleshooting:**

```bash
# AVC denial logları
ausearch -m avc -ts recent
ausearch -m avc -ts recent | grep container

journalctl -t setroubleshoot --since "1 hour ago"

# Real-time AVC monitoring
tail -f /var/log/audit/audit.log | grep AVC

# setroubleshoot
dnf install -y setroubleshoot-server
sealert -a /var/log/audit/audit.log
sealert -a /var/log/audit/audit.log > /tmp/selinux-report.txt

# audit2allow - policy oluştur
ausearch -m avc -ts recent | audit2allow -M mycontainer
semodule -i mycontainer.pp

# SELinux booleans
getsebool -a | grep container
setsebool -P container_manage_cgroup on

# SELinux troubleshooting workflow
# 1. AVC denial bul
ausearch -m avc -ts recent | grep denied

# 2. Context kontrol et
ls -lZ /problem/path

# 3. Correct context uygula
chcon -R -t container_file_t /problem/path
# veya
restorecon -Rv /problem/path

**💡 RESTORECON - CONTEXT RESTORE**
- **Amaç:** Dosya context'ini policy'e göre düzeltir
- **Ne Zaman:** Manuel chcon sonrası veya file move sonrası
- **-R flag:** Recursive, tüm alt dizinleri düzelt


# 4. Kalıcı policy (gerekirse)
ausearch -m avc -ts recent | audit2allow -M mypolicy
semodule -i mypolicy.pp
```
**SELinux Policy Örnekleri:**

```bash
# Container'ın belirli bir porta bind olmasına izin ver
ausearch -m avc -c nginx | audit2allow -M nginx_port_bind
semodule -i nginx_port_bind.pp

# Custom directory access
cat > mycontainer.te <<EOF
module mycontainer 1.0;

require {
    type container_t;
    type user_home_t;
    class dir { read getattr open search };
    class file { read getattr open };
}

allow container_t user_home_t:dir { read getattr open search };
allow container_t user_home_t:file { read getattr open };
EOF

checkmodule -M -m -o mycontainer.mod mycontainer.te
semodule_package -o mycontainer.pp -m mycontainer.mod
semodule -i mycontainer.pp
```
### 9.2 Seccomp Profiles

**Seccomp Nedir:**

Seccomp (Secure Computing Mode), Linux kernel özelliğidir. Container'ların
yapabileceği system call'ları kısıtlar.

```
┌─────────────────────────────────────────┐
│         Container Process               │
│     (seccomp filter applied)            │
├─────────────────────────────────────────┤
│  Allowed Syscalls    │ Blocked Syscalls │
│  - read, write       │ - reboot         │
│  - open, close       │ - mount          │
│  - socket, connect   │ - swapon         │
│  - fork, exec        │ - kexec_load     │
└─────────────────────────────────────────┘
```
**Default Seccomp:**

```bash
# Varsayılan seccomp profili
cat /usr/share/containers/seccomp.json | jq '.syscalls | length'

# Container'ın seccomp profili
podman inspect web | grep -i seccomp

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme

# Seccomp devre dışı (GÜVENLİK RİSKİ!)
podman run --security-opt seccomp=unconfined alpine

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Check syscalls
podman run --rm alpine sh -c 'apk add strace && strace ls'

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```
**Custom Seccomp:**

```bash
# Minimum seccomp profili
cat > /etc/containers/seccomp/minimal.json <<'EOF'
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": [
        "accept",
        "accept4",
        "access",
        "arch_prctl",
        "bind",
        "brk",
        "chdir",
        "clone",
        "close",
        "connect",
        "dup",
        "dup2",
        "epoll_create",
        "epoll_ctl",
        "epoll_wait",
        "execve",
        "exit",
        "exit_group",
        "fcntl",
        "fstat",
        "futex",
        "getcwd",
        "getdents",
        "getpid",
        "getsockname",
        "getsockopt",
        "getuid",
        "listen",
        "lseek",
        "madvise",
        "mmap",
        "mprotect",
        "munmap",
        "open",
        "openat",
        "poll",
        "read",
        "readlink",
        "recvfrom",
        "rt_sigaction",
        "rt_sigprocmask",
        "sched_yield",
        "sendto",
        "set_robust_list",
        "setsockopt",
        "socket",
        "stat",
        "uname",
        "wait4",
        "write"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF

# Profil kullanımı
podman run --security-opt seccomp=/etc/containers/seccomp/minimal.json alpine

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Test et
podman run --rm --security-opt seccomp=/etc/containers/seccomp/minimal.json alpine reboot
# Operation not permitted
```
**Seccomp Debug:**

```bash
# Hangi syscall block edildi?
# strace ile test
podman run --rm --security-opt seccomp=unconfined alpine sh -c 'apk add strace && strace reboot'
# Seccomp enabled container'da dene
podman run --rm alpine reboot
# Operation not permitted

# Kernel log
dmesg | grep audit
```
### 9.3 Linux Capabilities

**Capabilities Nedir:**

Geleneksel Unix'te root (UID 0) tüm yetkiye sahiptir. Capabilities, bu yetkiyi
parçalara böler.

```bash
# Tüm capabilities
capsh --print

# Common capabilities:
# CAP_NET_BIND_SERVICE - Bind to ports < 1024
# CAP_NET_ADMIN - Network admin operations
# CAP_SYS_ADMIN - System admin operations
# CAP_SYS_TIME - Change system time
# CAP_CHOWN - Change file ownership
# CAP_SETUID - Set UID
# CAP_SETGID - Set GID

# Container default capabilities
podman run --rm alpine sh -c 'apk add libcap && capsh --print'

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Capability ekleme
podman run --cap-add NET_ADMIN alpine ip link add dummy0 type dummy

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Capability çıkarma
podman run --cap-drop NET_RAW alpine ping -c 1 8.8.8.8
# Network is unreachable

# Tüm capabilities'i kaldır, sadece gerekenleri ekle
podman run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Privileged container (TÜM capabilities)
podman run --privileged alpine
# GÜVENLİK RİSKİ! Sadece gerektiğinde kullan
```
**Güvenli Production Container:**

```bash
podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name secure-app \
  --cap-drop ALL \
  --cap-add CHOWN \
  --cap-add SETGID \
  --cap-add SETUID \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /run \
  --security-opt no-new-privileges \
  --security-opt label=type:container_t \
  -v /app/data:/data:Z \
  myapp:latest

# Açıklama:
# --cap-drop ALL: Tüm capabilities kaldır
# --cap-add CHOWN/SETGID/SETUID: Sadece gerekli capabilities
# --read-only: Root filesystem read-only
# --tmpfs: Geçici yazılabilir alanlar
# --security-opt no-new-privileges: Privilege escalation engelle
# --security-opt label=type:container_t: SELinux type
```
### 9.4 Container Security Scanning

**Trivy:**

```bash
# Trivy kurulumu
wget https://github.com/aquasecurity/trivy/releases/download/v0.48.0/trivy_0.48.0_Linux-64bit.tar.gz
tar zxvf trivy_0.48.0_Linux-64bit.tar.gz
sudo mv trivy /usr/local/bin/

# Image scan
trivy image nginx:latest
trivy image --severity HIGH,CRITICAL nginx:latest
trivy image --severity CRITICAL --exit-code 1 nginx:latest

# Specific vulnerabilities
trivy image --ignore-unfixed nginx:latest

# JSON output
trivy image --format json --output report.json nginx:latest

# Template output
trivy image --format template --template "@contrib/html.tpl" -o report.html nginx:latest

# Local image scan
podman build -t myapp:latest .
trivy image myapp:latest

# Filesystem scan
trivy fs /path/to/project

# Config file scan
trivy config /path/to/kubernetes/manifests

# SBOM generation
trivy image --format cyclonedx --output sbom.json nginx:latest
trivy image --format spdx-json --output sbom-spdx.json nginx:latest

# Vulnerability DB update
trivy image --download-db-only
```
**Trivy CI/CD Integration:**

```bash
# GitLab CI
# .gitlab-ci.yml
security_scan:
  stage: test
  script:
    - trivy image --exit-code 1 --severity CRITICAL myapp:latest

# GitHub Actions
# .github/workflows/security.yml
- name: Run Trivy
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'myapp:latest'
    severity: 'CRITICAL,HIGH'
```
**Clair (Alternative Scanner):**

```bash
# Clair server (PostgreSQL gerekli)
podman run -d --name postgres -e POSTGRES_PASSWORD=password postgres:13

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --name clair -p 6060:6060 quay.io/coreos/clair:latest

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Clair CLI
clairctl analyze myapp:latest
```
**Anchore (Alternative Scanner):**

```bash
# Anchore Engine
podman run -d --name anchore-db -e POSTGRES_PASSWORD=mysecretpassword postgres:13

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run -d --name anchore-engine -p 8228:8228 anchore/anchore-engine:latest

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Anchore CLI
anchore-cli image add docker.io/library/nginx:latest
anchore-cli image wait nginx:latest
anchore-cli image vuln nginx:latest all
```
### 9.5 Image Signing (Cosign)

**Cosign Kurulum:**

```bash
# Cosign kurulum
wget https://github.com/sigstore/cosign/releases/download/v2.2.0/cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign

# Key pair oluştur
cosign generate-key-pair
# cosign.key ve cosign.pub oluşur

# Password korumalı
# Enter password for private key: ****
```
**Image Signing:**

```bash
# Image sign
cosign sign --key cosign.key quay.io/myorg/myapp:v1.2.3

# Keyless signing (Sigstore)
cosign sign quay.io/myorg/myapp:v1.2.3
# Browser'da authentication

# Verify
cosign verify --key cosign.pub quay.io/myorg/myapp:v1.2.3

# Verify output
cosign verify --key cosign.pub quay.io/myorg/myapp:v1.2.3 | jq
```
**Signature Policy Enforcement:**

```bash
# /etc/containers/policy.json
{
  "default": [
    {
      "type": "reject"
    }
  ],
  "transports": {
    "docker": {
      "quay.io/myorg": [
        {
          "type": "signedBy",
          "keyType": "GPGKeys",
          "keyPath": "/etc/pki/containers/cosign.pub"
        }
      ]
    }
  }
}

# Test
podman pull quay.io/myorg/myapp:v1.2.3
# Signature verification passed
```
### 9.6 User Namespaces

**User Namespace Mapping:**

```bash
# Rootless container - automatic mapping
podman unshare cat /proc/self/uid_map
# 0    1000    1
# 1  100000  65536

# Container içinde root (UID 0) -> Host'ta 1000
# Container içinde UID 1 -> Host'ta 100000

# Custom mapping
podman run --uidmap 0:100000:65536 --gidmap 0:100000:65536 alpine

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Manual subuid/subgid
echo "myuser:200000:65536" >> /etc/subuid
echo "myuser:200000:65536" >> /etc/subgid
```
- - -

## 10\) Production Deployment Patterns

### 10.1 High Availability Setup

**Multi-Host with Load Balancer:**

```
┌────────────────────────────────────────────┐
│         Load Balancer (HAProxy)            │
│           VIP: 10.0.1.100                  │
└──────┬──────────────────────────┬──────────┘
       │                          │
   ┌───▼──── ┐               ┌────▼───┐
   │ Node1  │                │ Node2  │
   │Podman  │                │Podman  │
   └───┬────┘                └────┬───┘
       │                          │
       └──────────┬──────┬────────┘
                  │      │
         ┌────────▼──────▼──────┐
         │   Shared Storage     │
         │   (NFS/GlusterFS)    │
         └──────────────────────┘
```
**Node Setup (Node1, Node2):**

```bash
# Shared storage mount
sudo mkdir -p /mnt/shared/app-data
sudo mount -t nfs nfs-server.local:/exports/app-data /mnt/shared/app-data

# /etc/fstab entry
echo 'nfs-server.local:/exports/app-data /mnt/shared/app-data nfs defaults,_netdev 0 0' | sudo tee -a /etc/fstab

# Quadlet configuration

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

sudo mkdir -p /etc/containers/systemd
sudo cat > /etc/containers/systemd/app.container <<'EOF'
[Unit]
Description=Application Server
After=network-online.target mnt-shared-app\x2ddata.mount
Wants=network-online.target

[Container]
Image=quay.io/myorg/app:stable
Environment=DATABASE_URL=postgresql://db.local/appdb
Environment=NODE_ENV=production
PublishPort=8080:8080
Volume=/mnt/shared/app-data:/app/data:Z
HealthCmd=curl -f http://localhost:8080/health || exit 1
HealthInterval=30s

[Service]
Restart=always
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** systemd'nin configuration dosyalarını yeniden okumasını sağlar
- **Ne Zaman:** Unit dosyası (.service, .socket vb.) oluşturduğunuzda veya düzenlediğinizde
- **Neden Gerekli:** systemd dosyaları cache'ler, bu komut olmadan değişiklikler aktif olmaz
- **Senaryo:** `/etc/systemd/system/myapp.service` dosyasını oluşturduktan sonra MUTLAKA çalıştırın
sudo systemctl enable --now app.service
```
**HAProxy Configuration:**

```bash
# /etc/haproxy/haproxy.cfg
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon
    maxconn 4096

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5s
    timeout client 50s
    timeout server 50s

frontend http_front
    bind *:80
    default_backend http_back

frontend stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s

backend http_back
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    
    server node1 10.0.1.10:8080 check inter 2s rise 3 fall 3
    server node2 10.0.1.11:8080 check inter 2s rise 3 fall 3
    server node3 10.0.1.12:8080 check inter 2s rise 3 fall 3 backup

# Enable ve start
sudo systemctl enable --now haproxy
```
### 10.2 Blue-Green Deployment

**Blue-Green Pattern:**

```
┌─────────────────────────────────────┐
│         Load Balancer               │
│    (Traffic Switch Point)           │
└───────────┬─────────────────────────┘
            │
     ┌──────┴──────┐
     │             │
┌────▼────┐   ┌───▼─────┐
│  Blue   │   │  Green  │
│ v1.2.3  │   │ v1.2.4  │
│(Active) │   │(Standby)│
└─────────┘   └─────────┘
```
**Implementation:**

```bash
# Blue deployment (current)
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name app-blue \
  -p 8081:8080 \
  -l deployment=blue \
  -l version=v1.2.3 \
  --health-cmd="curl -f http://localhost:8080/health" \

**💡 HEALTH CHECK - LIVENESS PROBE**
- **Amaç:** Container'ın healthy olup olmadığını otomatik kontrol
- **Çalışma:** Belirtilen komutu periyodik çalıştırır
- **Exit 0:** Healthy, diğer değerler=unhealthy
- **Restart Policy:** Unhealthy container otomatik restart edilir

  quay.io/myorg/app:v1.2.3

# Green deployment (new)
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name app-green \
  -p 8082:8080 \
  -l deployment=green \
  -l version=v1.2.4 \
  --health-cmd="curl -f http://localhost:8080/health" \

**💡 HEALTH CHECK - LIVENESS PROBE**
- **Amaç:** Container'ın healthy olup olmadığını otomatik kontrol
- **Çalışma:** Belirtilen komutu periyodik çalıştırır
- **Exit 0:** Healthy, diğer değerler=unhealthy
- **Restart Policy:** Unhealthy container otomatik restart edilir

  quay.io/myorg/app:v1.2.4

# Test green
for i in {1..10}; do curl http://localhost:8082/health; done

# Switch traffic (HAProxy backend güncelle)
# Option 1: HAProxy dynamic configuration
echo "set server http_back/app weight 0" | sudo socat stdio /run/haproxy/admin.sock
echo "set server http_back/app-green weight 100" | sudo socat stdio /run/haproxy/admin.sock

# Option 2: Systemd unit değiştir ve restart

# Success: Remove blue
sudo podman stop app-blue
sudo podman rm app-blue

# Rollback gerekirse: Green'i durdur, Blue'yu başlat
```
**Automated Blue-Green Script:**

```bash
#!/bin/bash
# blue-green-deploy.sh

set -e

NEW_VERSION=$1
CURRENT_COLOR=$(podman ps --filter "label=deployment=blue" --filter "status=running" -q && echo "blue" || echo "green")

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı
NEW_COLOR=$([ "$CURRENT_COLOR" = "blue" ] && echo "green" || echo "blue")

echo "Current: $CURRENT_COLOR"
echo "Deploying: $NEW_COLOR with version $NEW_VERSION"

# Deploy new version
podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name app-$NEW_COLOR \
  -p 808$([ "$NEW_COLOR" = "blue" ] && echo "1" || echo "2"):8080 \
  -l deployment=$NEW_COLOR \
  -l version=$NEW_VERSION \
  quay.io/myorg/app:$NEW_VERSION

# Health check
echo "Waiting for health check..."
for i in {1..30}; do
  if curl -sf http://localhost:808$([ "$NEW_COLOR" = "blue" ] && echo "1" || echo "2")/health; then
    echo "Health check passed"
    break
  fi
  sleep 2
done

# Switch traffic
echo "Switching traffic to $NEW_COLOR"
# HAProxy backend switch logic

# Remove old
sleep 30
podman stop app-$CURRENT_COLOR
podman rm app-$CURRENT_COLOR

echo "Deployment complete: $NEW_COLOR ($NEW_VERSION)"
```
### 10.3 Canary Deployment

**Canary Pattern:**

```
                ┌─────────────┐
                │    Users    │
                └──────┬──────┘
                       │
                ┌──────▼──────┐
                │Load Balancer│
                └──┬───────┬──┘
                   │       │
        90%        │       │      10%
    ┌──────────────┘       └──────────────┐
    │                                     │
┌───▼──────┐                       ┌──────▼───┐
│ Stable   │                       │  Canary  │
│ v1.2.3   │                       │  v1.2.4  │
│ (Many)   │                       │  (Few)   │
└──────────┘                       └──────────┘
```
**HAProxy Weighted Backend:**

```bash
# /etc/haproxy/haproxy.cfg
backend http_back
    balance roundrobin
    
    # Stable: 90%
    server stable1 10.0.1.10:8080 check weight 45
    server stable2 10.0.1.11:8080 check weight 45
    
    # Canary: 10%
    server canary1 10.0.1.12:8080 check weight 10

# Gradual increase
# Canary OK? weight 10 -> 20 -> 50 -> 90
# Stable: weight 90 -> 80 -> 50 -> 10 -> 0
```
**Canary Monitoring:**

```bash
# Metrics collection
# Error rate, latency, resource usage
# Compare stable vs canary

# Rollback if error rate > threshold
if [ "$CANARY_ERROR_RATE" -gt "5" ]; then
  echo "Rolling back canary"
  podman stop app-canary
  # HAProxy weight 0
fi
```
### 10.4 Rolling Update

**Rolling Update Pattern:**

```bash
#!/bin/bash
# rolling-update.sh

NODES=("node1" "node2" "node3")
NEW_VERSION=$1

for NODE in "${NODES[@]}"; do
  echo "Updating $NODE..."
  
  # SSH to node
  ssh root@$NODE << EOF
    # Pull new image
    podman pull quay.io/myorg/app:$NEW_VERSION
    
    # Update container
    podman stop app
    podman rm app
    podman run -d --name app -p 8080:8080 quay.io/myorg/app:$NEW_VERSION

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
    
    # Health check
    for i in {1..30}; do
      if curl -sf http://localhost:8080/health; then
        echo "Health check passed on $NODE"
        exit 0
      fi
      sleep 2
    done
    
    echo "Health check failed on $NODE"
    exit 1
EOF

  if [ $? -ne 0 ]; then
    echo "Update failed on $NODE, aborting"
    exit 1
  fi
  
  echo "Waiting before next node..."
  sleep 30
done

echo "Rolling update complete"
```
### 10.5 Immutable Infrastructure

**Immutable Container Pattern:**

```bash
# Read-only root filesystem
podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name app \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  --tmpfs /run:rw,noexec,nosuid,size=50m \
  -v app-config:/etc/app:ro,Z \
  -v app-logs:/var/log/app:rw,Z \
  quay.io/myorg/app:v1.0

# Configuration as code
# Dockerfile
FROM myapp:base
COPY config.yaml /etc/app/config.yaml
RUN chmod 444 /etc/app/config.yaml
```
**Configuration Management:**

```bash
# ConfigMaps (Kubernetes-style)
cat > app-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  config.yaml: |
    server:
      port: 8080
      host: 0.0.0.0
    database:
      host: db.local
      port: 5432
EOF

# Podman play kube ile kullan
podman play kube app-pod.yaml
```
- - -

## 11\) CI/CD Entegrasyonu

### 11.1 GitLab CI/CD

**GitLab Runner Kurulum:**

```bash
# GitLab Runner kurulum
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | sudo bash
sudo dnf install -y gitlab-runner

# Runner registration
sudo gitlab-runner register \
  --url "https://gitlab.com/" \
  --registration-token "YOUR_TOKEN" \
  --executor "shell" \
  --description "podman-runner"

# Podman kullanımı için
sudo usermod -aG podman gitlab-runner
```
**GitLab CI Pipeline:**

```yaml
# .gitlab-ci.yml
variables:
  IMAGE_NAME: quay.io/myorg/myapp
  IMAGE_TAG: $CI_COMMIT_SHA

stages:
  - build
  - test
  - scan
  - deploy

build:
  stage: build
  script:
    - podman build -t ${IMAGE_NAME}:${IMAGE_TAG} .
    - podman tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
    - echo "$REGISTRY_PASSWORD" | podman login quay.io -u "$REGISTRY_USER" --password-stdin
    - podman push ${IMAGE_NAME}:${IMAGE_TAG}
    - podman push ${IMAGE_NAME}:latest
  only:
    - main
    - develop

test:
  stage: test
  script:
    - podman run --rm ${IMAGE_NAME}:${IMAGE_TAG} npm test

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  only:
    - main
    - develop

security_scan:
  stage: scan
  script:
    - trivy image --exit-code 0 --severity HIGH,CRITICAL ${IMAGE_NAME}:${IMAGE_TAG}
  allow_failure: true

deploy_staging:
  stage: deploy
  script:
    - ssh deployer@staging.local "podman pull ${IMAGE_NAME}:${IMAGE_TAG}"
    - ssh deployer@staging.local "systemctl --user restart myapp.service"
  only:
    - develop

deploy_production:
  stage: deploy
  script:
    - ssh deployer@prod1.local "podman pull ${IMAGE_NAME}:${IMAGE_TAG}"
    - ssh deployer@prod1.local "systemctl restart myapp.service"
    - sleep 30
    - ssh deployer@prod2.local "podman pull ${IMAGE_NAME}:${IMAGE_TAG}"
    - ssh deployer@prod2.local "systemctl restart myapp.service"
  only:
    - main
  when: manual
```
### 11.2 GitHub Actions

**GitHub Actions Workflow:**

```yaml
# .github/workflows/ci.yml
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: quay.io
  IMAGE_NAME: myorg/myapp

jobs:
  build:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      
      - name: Set up Podman
        run: |
          sudo dnf install -y podman
      
      - name: Build image
        run: |
          podman build -t ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} .
          podman tag ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} \
                     ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
      
      - name: Run tests
        run: |
          podman run --rm ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }} npm test

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
      
      - name: Security scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: '${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'
      
      - name: Login to Registry
        run: |
          echo "${{ secrets.REGISTRY_PASSWORD }}" | \
            podman login ${{ env.REGISTRY }} -u ${{ secrets.REGISTRY_USER }} --password-stdin
      
      - name: Push image
        run: |
          podman push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
          podman push ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest

  deploy:
    needs: build
    runs-on: self-hosted
    if: github.ref == 'refs/heads/main'
    steps:
      - name: Deploy to production
        run: |
          ssh deployer@prod.local << 'EOF'
            podman pull ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
            sudo systemctl restart myapp.service
          EOF
```
### 11.3 Jenkins Pipeline

**Jenkinsfile:**

```groovy
// Jenkinsfile
pipeline {
    agent any
    
    environment {
        REGISTRY = 'quay.io'
        IMAGE_NAME = 'myorg/myapp'
        IMAGE_TAG = "${env.BUILD_ID}"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        
        stage('Build') {
            steps {
                script {
                    sh "podman build -t ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} ."
                }
            }
        }
        
        stage('Test') {
            steps {
                script {
                    sh "podman run --rm ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} npm test"

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
                }
            }
        }
        
        stage('Security Scan') {
            steps {
                script {
                    sh "trivy image --exit-code 0 --severity HIGH,CRITICAL ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }
        
        stage('Push') {
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: 'registry-creds', usernameVariable: 'USER', passwordVariable: 'PASS')]) {
                        sh "echo \$PASS | podman login ${REGISTRY} -u \$USER --password-stdin"
                        sh "podman push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                    }
                }
            }
        }
        
        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                script {
                    sshagent(['ssh-key']) {
                        sh "ssh deployer@prod.local 'podman pull ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}'"
                        sh "ssh deployer@prod.local 'sudo systemctl restart myapp.service'"
                    }
                }
            }
        }
    }
    
    post {
        always {
            sh "podman logout ${REGISTRY}"
        }
        failure {
            mail to: 'team@example.com',
                 subject: "Failed Pipeline: ${currentBuild.fullDisplayName}",
                 body: "Something is wrong with ${env.BUILD_URL}"
        }
    }
}
```
- - -

## 12\) Monitoring ve Logging

### 12.1 Prometheus + Grafana

**Prometheus Setup:**

```yaml
# prometheus-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: monitoring
spec:
  containers:
  - name: prometheus
    image: prom/prometheus:latest
    ports:
    - containerPort: 9090
      hostPort: 9090
    volumeMounts:
    - name: prometheus-config
      mountPath: /etc/prometheus
    - name: prometheus-data
      mountPath: /prometheus
    
  - name: grafana
    image: grafana/grafana:latest
    ports:
    - containerPort: 3000
      hostPort: 3000
    volumeMounts:
    - name: grafana-data
      mountPath: /var/lib/grafana
    env:
    - name: GF_SECURITY_ADMIN_PASSWORD
      value: "admin123"
  
  volumes:
  - name: prometheus-config
    hostPath:
      path: /opt/monitoring/prometheus
  - name: prometheus-data
    hostPath:
      path: /var/lib/prometheus
  - name: grafana-data
    hostPath:
      path: /var/lib/grafana
```
**Prometheus Config:**

```yaml
# /opt/monitoring/prometheus/prometheus.yml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  - job_name: 'node-exporter'
    static_configs:
      - targets: ['node1:9100', 'node2:9100', 'node3:9100']
  
  - job_name: 'cadvisor'
    static_configs:
      - targets: ['node1:8080', 'node2:8080', 'node3:8080']
  
  - job_name: 'app'
    static_configs:
      - targets: ['app1:8080', 'app2:8080']
```
**Deploy:**

```bash
sudo mkdir -p /opt/monitoring/prometheus /var/lib/prometheus /var/lib/grafana
sudo chown -R 65534:65534 /var/lib/prometheus
sudo chown -R 472:472 /var/lib/grafana

sudo podman play kube prometheus-pod.yaml

# Access
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin123)
```
**Node Exporter:**

```bash
# Her node'da
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name node-exporter \
  --network=host \
  --pid=host \
  -v /:/host:ro,rslave \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host

# Systemd service
sudo podman generate systemd --new --files --name node-exporter
sudo mv container-node-exporter.service /etc/systemd/system/
sudo systemctl enable --now container-node-exporter.service
```
**cAdvisor (Container Metrics):**

```bash
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name cadvisor \
  --network=host \
  --privileged \
  -v /:/rootfs:ro \
  -v /var/run:/var/run:ro \
  -v /sys:/sys:ro \
  -v /var/lib/containers:/var/lib/containers:ro \
  gcr.io/cadvisor/cadvisor:latest
```
**Grafana Dashboards:**

```bash
# Grafana'ya login: admin/admin123
# Add data source: Prometheus (http://localhost:9090)
# Import dashboards:
# - Node Exporter Full (ID: 1860)
# - Docker and System Monitoring (ID: 893)
# - Container Metrics (custom)
```
### 12.2 Logging with Loki

**Loki Stack:**

```bash
# Loki deployment
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name loki \
  -p 3100:3100 \
  -v loki-config:/etc/loki \
  -v loki-data:/loki \
  grafana/loki:latest

# Promtail deployment (log shipper)
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name promtail \
  -v /var/log:/var/log:ro \
  -v /var/lib/containers:/var/lib/containers:ro \
  -v promtail-config:/etc/promtail \
  grafana/promtail:latest
```
**Loki Config:**

```yaml
# /var/lib/containers/storage/volumes/loki-config/_data/loki-config.yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2020-05-15
      store: boltdb
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 168h

storage_config:
  boltdb:
    directory: /loki/index
  filesystem:
    directory: /loki/chunks

limits_config:
  enforce_metric_name: false
  reject_old_samples: true
  reject_old_samples_max_age: 168h

chunk_store_config:
  max_look_back_period: 0s

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h
```
**Promtail Config:**

```yaml
# /var/lib/containers/storage/volumes/promtail-config/_data/promtail-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
    - targets:
        - localhost
      labels:
        job: varlogs
        __path__: /var/log/*log

  - job_name: containers
    static_configs:
    - targets:
        - localhost
      labels:
        job: container-logs
        __path__: /var/lib/containers/storage/overlay-containers/*/userdata/ctr.log
```
**LogQL Queries:**

```
# Tüm loglar
{job="container-logs"}

# Specific container
{job="container-logs",container_name="myapp"}

# Error logs
{job="container-logs"} |= "error"
{job="container-logs"} |~ "error|exception"

# Systemd journal
{job="systemd-journal", unit="app.service"}

# Rate
rate({job="container-logs"}[5m])

# Stats
sum(rate({job="container-logs"} |= "error" [5m])) by (container_name)
```
**Grafana Loki Integration:**

```bash
# Grafana'da Loki data source ekle
# URL: http://localhost:3100
# Explore -> Loki -> Query
```
### 12.3 ELK Stack (Alternative)

**Elasticsearch + Logstash + Kibana:**

```bash
# Elasticsearch
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name elasticsearch \
  -p 9200:9200 \
  -p 9300:9300 \
  -e "discovery.type=single-node" \
  -e "ES_JAVA_OPTS=-Xms512m -Xmx512m" \
  -v es-data:/usr/share/elasticsearch/data \
  docker.elastic.co/elasticsearch/elasticsearch:8.11.0

# Logstash
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name logstash \
  -p 5044:5044 \
  -v logstash-config:/usr/share/logstash/pipeline \
  docker.elastic.co/logstash/logstash:8.11.0

# Kibana
sudo podman run -d \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
  --name kibana \
  -p 5601:5601 \
  -e "ELASTICSEARCH_HOSTS=http://localhost:9200" \
  docker.elastic.co/kibana/kibana:8.11.0
```
### 12.4 Metrics Collection

**Container Stats:**

```bash
# Real-time stats
podman stats

# JSON output
podman stats --no-stream --format json

# Specific container
podman stats myapp

# Script for collection
while true; do
  podman stats --no-stream --format "{{.Container}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" >> /var/log/container-stats.log
  sleep 60
done
```
**Custom Metrics Exporter:**

```python
# metrics-exporter.py
from prometheus_client import start_http_server, Gauge
import subprocess
import json
import time

container_cpu = Gauge('container_cpu_usage', 'Container CPU usage', ['container'])
container_memory = Gauge('container_memory_usage_bytes', 'Container memory usage', ['container'])

def collect_metrics():
    result = subprocess.run(['podman', 'stats', '--no-stream', '--format', 'json'], 
                          capture_output=True, text=True)
    stats = json.loads(result.stdout)
    
    for stat in stats:
        name = stat['name']
        cpu = float(stat['cpu_percent'].strip('%'))
        memory = stat['mem_usage_bytes']
        
        container_cpu.labels(container=name).set(cpu)
        container_memory.labels(container=name).set(memory)

if __name__ == '__main__':
    start_http_server(8000)
    while True:
        collect_metrics()
        time.sleep(15)
```
- - -

## 13\) Backup ve Disaster Recovery

### 13.1 Container Backup

**Image Backup:**

```bash
# Image export
podman save -o myapp-backup.tar myapp:v1.0
gzip myapp-backup.tar

# Multiple images
podman save -o images-backup.tar myapp:v1.0 nginx:latest postgres:15
gzip images-backup.tar

# Restore
gunzip images-backup.tar.gz
podman load -i images-backup.tar

# Registry'ye push (backup)
podman tag myapp:v1.0 backup-registry.local/myapp:v1.0-backup-$(date +%Y%m%d)
podman push backup-registry.local/myapp:v1.0-backup-$(date +%Y%m%d)
```
**Container Checkpoint/Restore (CRIU):**

```bash
# CRIU kurulum
sudo dnf install -y criu

# Checkpoint (container state kaydet)
podman container checkpoint myapp --export=/backup/myapp-checkpoint.tar.gz

# Container listesi
podman ps -a

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı

# Restore
podman container restore --import=/backup/myapp-checkpoint.tar.gz

# Live migration
# Node1:
podman container checkpoint myapp --export=/shared/myapp-checkpoint.tar.gz
# Node2:
podman container restore --import=/shared/myapp-checkpoint.tar.gz
```
**Volume Backup:**

```bash
# Named volume backup
podman volume create mydata

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Persistent storage için named volume oluşturur
- **Fark:** Bind mount vs volume - volume'lar Podman yönetir
- **Avantaj:** Volume'lar taşınabilir, backup'lanabilir
- **Senaryo:** Database verisi container silinse bile kalmalı
podman run --rm -v mydata:/source -v /backup:/backup alpine tar czf /backup/mydata-$(date +%F).tar.gz -C /source .

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Volume restore
podman volume create mydata-restored

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Persistent storage için named volume oluşturur
- **Fark:** Bind mount vs volume - volume'lar Podman yönetir
- **Avantaj:** Volume'lar taşınabilir, backup'lanabilir
- **Senaryo:** Database verisi container silinse bile kalmalı
podman run --rm -v mydata-restored:/target -v /backup:/backup alpine tar xzf /backup/mydata-2025-10-20.tar.gz -C /target

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Bind mount backup
tar czf /backup/app-data-$(date +%F).tar.gz -C /opt/app/data .

# Database backup (PostgreSQL)
podman exec postgres pg_dumpall -U postgres | gzip > /backup/postgres-$(date +%F).sql.gz

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container içinde komut çalıştırır
- **Debug İçin:** -it /bin/bash ile container'a shell erişimi
- **Güvenlik:** Root access gerektirmez (rootless podman)
- **Senaryo:** Database container'ında psql çalıştırma
```
### 13.2 System Backup

**Full System Backup Script:**

```bash
#!/bin/bash
# container-backup.sh

BACKUP_DIR=/backup/containers
DATE=$(date +%F)
CONTAINERS=$(podman ps --format "{{.Names}}")

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Çalışan container'ları listeler
- **Ek Bilgi:** -a ile durmuş container'ları da gösterir
- **JSON Çıktı:** --format json ile programatik işleme
- **Senaryo:** Hangi container'lar çalışıyor, resource kullanımı

mkdir -p $BACKUP_DIR/$DATE

# Container metadata
for CONTAINER in $CONTAINERS; do
  echo "Backing up $CONTAINER..."
  
  # Export container
  podman export $CONTAINER > $BACKUP_DIR/$DATE/$CONTAINER.tar
  
  # Save inspect data
  podman inspect $CONTAINER > $BACKUP_DIR/$DATE/$CONTAINER-inspect.json

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
  
  # Save logs
  podman logs $CONTAINER > $BACKUP_DIR/$DATE/$CONTAINER-logs.txt

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
done

# Images
podman images --format "{{.Repository}}:{{.Tag}}" > $BACKUP_DIR/$DATE/images.list
while read IMAGE; do
  FILENAME=$(echo $IMAGE | tr '/:' '_')
  podman save -o $BACKUP_DIR/$DATE/$FILENAME.tar $IMAGE
done < $BACKUP_DIR/$DATE/images.list

# Volumes
podman volume ls --format "{{.Name}}" > $BACKUP_DIR/$DATE/volumes.list
while read VOLUME; do
  podman run --rm -v $VOLUME:/source -v $BACKUP_DIR/$DATE:/backup alpine \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
    tar czf /backup/$VOLUME.tar.gz -C /source .
done < $BACKUP_DIR/$DATE/volumes.list

# Compress all
tar czf $BACKUP_DIR/backup-$DATE.tar.gz -C $BACKUP_DIR $DATE
rm -rf $BACKUP_DIR/$DATE

echo "Backup complete: $BACKUP_DIR/backup-$DATE.tar.gz"
```
### 13.3 Disaster Recovery Plan

**Recovery Runbook:**

```bash
#!/bin/bash
# disaster-recovery.sh

BACKUP_FILE=$1

# 1. System preparation
sudo dnf install -y podman buildah skopeo

# 2. Extract backup
mkdir /tmp/recovery
tar xzf $BACKUP_FILE -C /tmp/recovery

# 3. Restore images
for IMAGE_TAR in /tmp/recovery/*/images/*.tar; do
  podman load -i $IMAGE_TAR
done

# 4. Restore volumes
for VOLUME_TAR in /tmp/recovery/*/volumes/*.tar.gz; do
  VOLUME_NAME=$(basename $VOLUME_TAR .tar.gz)
  podman volume create $VOLUME_NAME

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Persistent storage için named volume oluşturur
- **Fark:** Bind mount vs volume - volume'lar Podman yönetir
- **Avantaj:** Volume'lar taşınabilir, backup'lanabilir
- **Senaryo:** Database verisi container silinse bile kalmalı
  podman run --rm -v $VOLUME_NAME:/target -v /tmp/recovery:/backup alpine \

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
    tar xzf /backup/$VOLUME_TAR -C /target
done

# 5. Recreate containers
for INSPECT_JSON in /tmp/recovery/*/inspect/*.json; do
  CONTAINER_NAME=$(jq -r '.[0].Name' $INSPECT_JSON | sed 's/\///')
  IMAGE=$(jq -r '.[0].Config.Image' $INSPECT_JSON)
  
  # Reconstruct run command from inspect
  # This is simplified, production needs full recreation logic
  podman create --name $CONTAINER_NAME $IMAGE
done

# 6. Start services
systemctl restart podman-*
```
**Automated Backup with systemd Timer:**

```ini
# /etc/systemd/system/container-backup.service
[Unit]
Description=Container Backup Service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/container-backup.sh
User=root

# /etc/systemd/system/container-backup.timer
[Unit]
Description=Daily Container Backup

[Timer]
OnCalendar=daily
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
sudo systemctl enable --now container-backup.timer
sudo systemctl list-timers
```
- - -

## 14\) İleri Seviye Konular

### 14.1 Multi-Architecture Images

**Buildx (Docker) Alternative - Podman:**

```bash
# Qemu setup
sudo dnf install -y qemu-user-static

# Multi-arch build
podman build --platform linux/amd64,linux/arm64 -t myapp:latest .

# Manifest oluştur
podman manifest create myapp:latest

# Architecture-specific builds
podman build --platform linux/amd64 -t myapp:amd64 .
podman build --platform linux/arm64 -t myapp:arm64 .

# Manifest'e ekle
podman manifest add myapp:latest myapp:amd64
podman manifest add myapp:latest myapp:arm64

# Inspect
podman manifest inspect myapp:latest

# Push (tüm architectures)
podman manifest push myapp:latest docker://quay.io/myorg/myapp:latest
```
### 14.2 Podman in Podman (Nested Containers)

**Rootless Podman in Container:**

```dockerfile
# Dockerfile
FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf install -y podman fuse-overlayfs --exclude container-selinux && \
    dnf clean all

# Rootless user
RUN useradd -m podman && \
    echo "podman:100000:65536" > /etc/subuid && \
    echo "podman:100000:65536" > /etc/subgid

USER podman
WORKDIR /home/podman

CMD ["/bin/bash"]
# Build
podman build -t podman-in-podman .

# Run
podman run -it --privileged podman-in-podman

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Inside container
podman run hello-world

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```
### 14.3 GPU Support (NVIDIA)

**NVIDIA Container Toolkit:**

```bash
# NVIDIA driver kurulum
sudo dnf install -y nvidia-driver

# NVIDIA Container Toolkit
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

sudo dnf install -y nvidia-container-toolkit

# CDI (Container Device Interface) config
sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# GPU container
podman run --rm --device nvidia.com/gpu=all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```
### 14.4 Podman Desktop

**Podman Desktop GUI:**

```bash
# Podman Desktop (Electron app)
# Download from: https://podman-desktop.io/

# Features:
# - Container management GUI
# - Pod visualization
# - Image build interface
# - Registry management
# - Compose support
```
### 14.5 Performance Tuning

**Container Performance:**

```bash
# CPU pinning
podman run --cpuset-cpus 0,1 myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# CPU shares (relative weight)
podman run --cpu-shares 1024 myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# CPU period and quota
podman run --cpu-period=100000 --cpu-quota=50000 myapp  # 50% of 1 CPU

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Memory limits
podman run --memory=512m --memory-swap=1g myapp

**💡 MEMORY LİMİT - OOM PREVENTİON**
- **Amaç:** Container'ın maximum memory kullanımını sınırlar
- **Neden Kritik:** Memory leak olan container host'u çökertebilir
- **--memory-swap:** Total memory+swap limiti
- **Production:** TÜM container'lara memory limit koyun


**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run --memory=512m --memory-reservation=256m myapp

**💡 MEMORY LİMİT - OOM PREVENTİON**
- **Amaç:** Container'ın maximum memory kullanımını sınırlar
- **Neden Kritik:** Memory leak olan container host'u çökertebilir
- **--memory-swap:** Total memory+swap limiti
- **Production:** TÜM container'lara memory limit koyun


**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Memory swappiness
podman run --memory-swappiness=0 myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Block I/O
podman run --blkio-weight=500 myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run --device-read-bps /dev/sda:1mb myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run --device-write-bps /dev/sda:1mb myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Network optimization
podman run --network=host myapp  # Fastest

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
podman run --network=slirp4netns:enable_ipv6=true myapp

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```
**Storage Driver Optimization:**

```bash
# overlay2 (default, fastest)
cat /etc/containers/storage.conf

[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
mountopt = "nodev,metacopy=on"

# VFS (slowest, most compatible)
# driver = "vfs"
```
### 14.6 Podman API

**Podman REST API:**

```bash
# Enable API service (rootless)
systemctl --user enable --now podman.socket

# Check socket
systemctl --user status podman.socket
ls -l /run/user/$(id -u)/podman/podman.sock

# API call
curl --unix-socket /run/user/$(id -u)/podman/podman.sock http://localhost/v4.0.0/libpod/info | jq

# List containers
curl --unix-socket /run/user/$(id -u)/podman/podman.sock http://localhost/v4.0.0/libpod/containers/json | jq

# Root API
sudo systemctl enable --now podman.socket
curl --unix-socket /run/podman/podman.sock http://localhost/v4.0.0/libpod/info | jq
```
**Podman API Python Client:**

```python
# pip install podman
import podman

# Connect
client = podman.PodmanClient(base_url="unix:///run/user/1000/podman/podman.sock")

# List containers
for container in client.containers.list():
    print(container.name, container.status)

# Run container
container = client.containers.run("nginx", detach=True, ports={'80/tcp': 8080})
print(container.id)

# Stop container
container.stop()
container.remove()
```
### 14.7 Troubleshooting Techniques

**Debug Mode:**

```bash
# Podman debug logging
podman --log-level=debug run nginx

# Container debug
podman run -it --entrypoint /bin/sh nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Network debug
podman run --rm --network=host nicolaka/netshoot

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Inside netshoot container
nslookup google.com
traceroute google.com
tcpdump -i eth0
```
**Common Issues:**

```bash
# Issue 1: Permission denied (volume mount)
# Solution: SELinux context
podman run -v /data:/data:Z nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# Issue 2: Port already in use
# Solution: Find and kill process
ss -tulpn | grep :8080
sudo kill <PID>

# Issue 3: Image pull fails
# Solution: Check registry config
cat /etc/containers/registries.conf
podman login registry.local

# Issue 4: Container crashes immediately
# Solution: Check logs
podman logs container-name

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
podman inspect container-name

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme

# Issue 5: Rootless networking issues
# Solution: Check slirp4netns
ps aux | grep slirp4netns

# Issue 6: Storage full
# Solution: Prune
podman system prune -a --volumes
podman volume prune
podman image prune -a
```
- - -
## Sonuç ve Best Practices

### Production Checklist

**Güvenlik:**

- ✅ Rootless Podman kullan (mümkünse)
- ✅ SELinux Enforcing modda çalıştır
- ✅ Image vulnerability scanning (Trivy)
- ✅ Image signing (Cosign)
- ✅ Minimal base images kullan (UBI, Alpine)
- ✅ Non-root user ile container çalıştır
- ✅ Read-only filesystem
- ✅ Capabilities drop
- ✅ Seccomp profilleri
- ✅ Network segmentation

**Monitoring ve Logging:**

- ✅ Prometheus + Grafana
- ✅ Loki veya ELK stack
- ✅ Health checks
- ✅ Alerting rules
- ✅ Log retention policy

**High Availability:**

- ✅ Multi-node deployment
- ✅ Load balancer
- ✅ Shared storage (NFS/GlusterFS)
- ✅ Automated failover
- ✅ Blue-green/canary deployment

**Backup ve Recovery:**

- ✅ Automated backup (daily)
- ✅ Volume backups
- ✅ Image backups
- ✅ Disaster recovery plan
- ✅ Test recovery procedure

**Performance:**

- ✅ Resource limits (CPU, memory)
- ✅ Storage driver optimization
- ✅ Network mode selection
- ✅ Cgroup v2 kullanımı

### Kaynaklar ve Referanslar

**Resmi Dokümantasyon:**

- Red Hat Documentation: <https://access.redhat.com/documentation/>
- Podman Documentation: <https://docs.podman.io/>
- Podman GitHub: <https://github.com/containers/podman>
- Buildah Documentation: <https://buildah.io/>
- Skopeo Documentation: <https://github.com/containers/skopeo>

**OCI ve Standardlar:**

- OCI Specification: <https://opencontainers.org/>
- CRI-O: <https://cri-o.io/>
- Container Network Interface (CNI): 
  <https://github.com/containernetworking/cni>

**Güvenlik:**

- NIST Container Security Guide: 
  <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf>
- CIS Docker Benchmark: <https://www.cisecurity.org/benchmark/docker>
- SELinux Project: <https://github.com/SELinuxProject>

**Community:**

- Podman Blog: <https://podman.io/blogs/>
- Red Hat Developer: <https://developers.redhat.com/>
- Container Stack on Reddit: r/podman, r/containers

### Sürüm Notları

**v0.91 (2025-10-20):**

- RHEL 9.x güncellemeleri
- Podman 5.x özellikleri
- Quadlet detaylı anlatım

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

- Multi-architecture support
- GPU support eklendi
- Genişletilmiş troubleshooting
- CI/CD pipeline örnekleri
- Advanced networking scenarios

**v0.9 (İlk sürüm):**

- Temel Podman komutları
- systemd entegrasyonu
- Basit deployment patterns

- - -
## Lisans ve Katkı

**Lisans:** Creative Commons BY-SA 4.0

**Katkıda Bulunma:** Bu döküman açık kaynaklıdır. Katkılarınızı bekliyoruz:

- Hata düzeltmeleri
- Yeni örnekler
- Best practice önerileri
- Çeviri

**İletişim:**

- Email: remzi@akyuz.tech

- - -
**Not:** Bu el kitabı production ortamları için hazırlanmıştır. Bununla birlikte test ortamında denedikten sonra production'a geçiniz. 

Her ortam farklıdır, konfigürasyonları kendi ihtiyaçlarınıza göre uyarlayınız.

**Güncelleme:** Düzenli olarak güncellenmektedir. Son sürüm için resmi
repository'yi kontrol ediniz.



---

## Sonuç ve Best Practices

### Production Checklist

**Güvenlik:**

- ✅ Rootless Podman kullan (mümkünse)
- ✅ SELinux Enforcing modda çalıştır
- ✅ Image vulnerability scanning (Trivy)
- ✅ Image signing (Cosign)
- ✅ Minimal base images kullan (UBI, Alpine)
- ✅ Non-root user ile container çalıştır
- ✅ Read-only filesystem
- ✅ Capabilities drop
- ✅ Seccomp profilleri
- ✅ Network segmentation

**Monitoring ve Logging:**

- ✅ Prometheus + Grafana
- ✅ Loki veya ELK stack
- ✅ Health checks
- ✅ Alerting rules
- ✅ Log retention policy

**High Availability:**

- ✅ Multi-node deployment
- ✅ Load balancer
- ✅ Shared storage (NFS/GlusterFS)
- ✅ Automated failover
- ✅ Blue-green/canary deployment

**Backup ve Recovery:**

- ✅ Automated backup (daily)
- ✅ Volume backups
- ✅ Image backups
- ✅ Disaster recovery plan
- ✅ Test recovery procedure

**Performance:**

- ✅ Resource limits (CPU, memory)
- ✅ Storage driver optimization
- ✅ Network mode selection
- ✅ Cgroup v2 kullanımı

---

## 15) Teknik Terimler ve En İyi Uygulamalar

### 15.1 TR / EN Teknik Terim Karşılıkları

| Türkçe Terim | İngilizce Karşılığı |
|--------------|---------------------|
| Kapsayıcı | Container |
| Hacim | Volume |
| Görüntü | Image |
| Depo | Registry |
| Ağ Köprüsü | Network Bridge |
| Hizmet Birimi | Service Unit |
| Kalıcılık | Persistence |
| Güvenlik Duvarı | Firewall |
| Yük Dengeleyici | Load Balancer |
| Sistem Yöneticisi | System Administrator |

### 15.2 En İyi Uygulama Önerileri

**CI/CD Pipeline Güvenliği:**

- CI/CD pipeline'larında gizli anahtarları **environment variable** olarak saklayın, repo içinde düz metin kullanmayın.
- Her build'de **secret scanning** yapın (GitGuardian, TruffleHog).
- Container secrets için HashiCorp Vault veya Podman secrets kullanın.

**Image Güvenliği:**

- Her container imajı için **Trivy veya Clair** ile güvenlik taraması yapın.
- Base image'leri düzenli olarak güncelleyin (monthly).
- **Multi-stage build** kullanarak final image'i minimal tutun.
- Image'leri imzalayın ve doğrulayın (Cosign/Sigstore).

**SELinux Yönetimi:**

- **SELinux**'u devre dışı bırakmak yerine policy modülleriyle izin genişletin.
- `audit2allow` ile custom policy oluşturun.
- Container context'leri için `:Z` ve `:z` volume flags'lerini doğru kullanın.

**Systemd Quadlet:**

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


- **Systemd Quadlet** yapılarını versiyon kontrolüne alın (`.container` dosyaları git'te tutulsun).

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

- Quadlet dosyalarını `/etc/containers/systemd/` dizininde organize edin.

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

- `podman generate systemd` yerine doğrudan Quadlet dosyası yazın (daha temiz).

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik


**Monitoring Best Practices:**

- Prometheus + Grafana metriklerini **15 saniye** aralıklarla alın (5 saniye çok sık, veri hacmini artırır).
- Log aggregation için Loki kullanın (Elasticsearch'ten daha hafif).
- Critical service'ler için health check endpoint'leri ekleyin (`/health`, `/ready`).
- Alerting threshold'larını gerçekçi belirleyin (çok fazla false positive olmasın).

**Network Güvenliği:**

- Production'da container network'leri izole edin (custom networks).
- Gereksiz port expose etmeyin.
- Firewall kurallarını container IP'leri için özelleştirin.
- Internal service'ler için sadece `localhost` bind yapın.

**Resource Management:**

- Tüm production container'lara CPU ve memory limiti koyun.
- OOM killer yerine controlled restart için `MemoryHigh` kullanın.
- IO-intensive container'lar için `IOWeight` ayarlayın.
- `--cpuset-cpus` ile CPU affinity belirleyin (NUMA sistemlerde).

**Backup Stratejisi:**

- Volume backup'larını encrypted olarak saklayın.
- Backup retention policy belirleyin (örn: 7 günlük daily, 4 haftalık weekly).
- Disaster recovery prosedürünü düzenli test edin (quarterly).
- Off-site backup lokasyonu kullanın.

**Development Best Practices:**

- Development ve production environment'ları mümkün olduğunca benzer tutun.
- `.containerignore` dosyası kullanarak gereksiz dosyaları image'e eklemeyin.
- Layer caching'den faydalanmak için Dockerfile'da dependency install'ları önce yapın.
- Health check komutları basit ve hızlı olsun (< 1 saniye).

### 15.3 Sık Yapılan Hatalar ve Çözümleri

**Hata 1: Permission Denied (Volume Mount)**

```bash
# ❌ Yanlış
podman run -v /data:/data nginx

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın

# ✅ Doğru (SELinux context)
podman run -v /data:/data:Z nginx
# veya
chcon -t container_file_t /data

**💡 CHCON - SELINUX CONTEXT DEĞİŞTİRME**
- **Amaç:** Dosya/dizine SELinux type etiketi atar
- **container_file_t:** Container'ların erişebileceği dosyalar
- **Neden Gerekli:** SELinux olmadan volume mount permission denied
- **Alternatif:** podman run -v /path:/path:Z (otomatik relabel)

```

**Hata 2: Container Hemen Çöküyor**

```bash
# Debug için:
podman logs container-name

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container'ın stdout/stderr çıktısını gösterir
- **Sınırlama:** JSON file driver kullanılıyorsa çalışır
- **Alternatif:** journalctl -u container-name (systemd ile)
- **Senaryo:** Container çöktü, son hata mesajlarını görme
podman inspect container-name

**💡 NEDEN VE NE ZAMAN?**
- **Amaç:** Container/Image hakkında detaylı JSON metadata
- **Ne Gösterir:** Network ayarları, volume mount'ları, environment variables
- **Kullanım:** Debug, automation scriptleri, config doğrulama
- **Senaryo:** Container neden network'e bağlanamıyor sorusunu çözme
podman run -it --entrypoint /bin/sh image-name

**💡 PODMAN RUN - TEMEL CONTAINER BAŞLATMA**
- **Ne Yapar:** Yeni bir container oluşturur ve başlatır (tek komutta)
- **Docker Karşılığı:** %100 uyumlu (`alias docker=podman`)
- **Rootless Avantajı:** Sudo gerektirmez, normal kullanıcı çalıştırabilir
- **Uyarı:** Manuel run geçicidir, production için systemd kullanın
```

**Hata 3: Network Connectivity Sorunları**

```bash
# Rootless networking için:
podman network ls

**💡 NETWORK LS - AĞ LİSTELEME**
- **Ne Gösterir:** Mevcut network'ler, driver tipi, subnet
- **Default Networks:** podman (bridge), host, none
- **Kullanım:** Container neden network'e erişemiyor debug'u

podman network inspect podman

**💡 NETWORK INSPECT - AĞ DETAYLARI**
- **Amaç:** Network config detaylarını JSON olarak gösterir
- **Bilgiler:** Subnet, gateway, DNS servers, connected containers
- **Debug:** Hangi container'lar bu network'e bağlı?


# DNS problemi varsa:
cat /etc/containers/containers.conf
# [containers]
# dns_servers = ["8.8.8.8", "1.1.1.1"]
```

**Hata 4: Image Pull Başarısız**

```bash
# Registry config kontrol:
cat /etc/containers/registries.conf

# Login gerekiyorsa:
podman login registry.example.com

# Insecure registry için:
# /etc/containers/registries.conf içinde:
# [[registry]]
# location = "registry.example.com"
# insecure = true
```

**Hata 5: Disk Doldu**

```bash
# Kullanılmayan kaynakları temizle:
podman system prune -a --volumes
podman image prune -a
podman volume prune
podman container prune

# Disk kullanımını kontrol:
podman system df
```

### 15.4 Performance Tuning Checklist

**Container Runtime:**

- [ ] Overlay storage driver kullanılıyor
- [ ] Rootless mode için `subuid`/`subgid` doğru ayarlanmış
- [ ] `fuse-overlayfs` kurulu ve aktif
- [ ] cgroup v2 kullanılıyor

**Network Performance:**

- [ ] Host network mode değerlendirildi (yüksek throughput için)
- [ ] MTU değeri optimize edildi
- [ ] Slirp4netns yerine pasta kullanımı değerlendirildi (rootless için)

**Storage Performance:**

- [ ] XFS filesystem kullanılıyor (overlay için optimal)
- [ ] SSD kullanımı tercih edildi
- [ ] Volume mount'ları `:z` yerine `:Z` ile yapılıyor (daha hızlı)

**System Resources:**

- [ ] Kernel parametreleri optimize edildi (`net.ipv4.ip_forward`, `vm.swappiness`)
- [ ] File descriptor limitleri artırıldı
- [ ] inotify watch limitleri ayarlandı

---

## Kaynaklar ve Referanslar

### Resmi Dokümantasyon

- **Red Hat Documentation:** https://access.redhat.com/documentation/
- **Podman Documentation:** https://docs.podman.io/
- **Podman GitHub:** https://github.com/containers/podman
- **Buildah Documentation:** https://buildah.io/
- **Skopeo Documentation:** https://github.com/containers/skopeo

### OCI ve Standardlar

- **OCI Specification:** https://opencontainers.org/
- **CRI-O:** https://cri-o.io/
- **Container Network Interface (CNI):** https://github.com/containernetworking/cni
- **Container Storage Interface (CSI):** https://github.com/container-storage-interface/spec

### Güvenlik

- **NIST Container Security Guide:** https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-190.pdf
- **CIS Docker Benchmark:** https://www.cisecurity.org/benchmark/docker
- **SELinux Project:** https://github.com/SELinuxProject
- **Trivy Scanner:** https://trivy.dev/
- **Clair Scanner:** https://github.com/quay/clair

### Community ve Bloglar

- **Podman Blog:** https://podman.io/blogs/
- **Red Hat Developer:** https://developers.redhat.com/
- **Container Stack on Reddit:** r/podman, r/containers
- **Podman Desktop:** https://podman-desktop.io/

### Eğitim ve Sertifikasyon

- **Red Hat Certified Specialist in Containers:** https://www.redhat.com/en/services/certification/red-hat-certified-specialist-in-containers
- **Kubernetes and Cloud Native Associate (KCNA):** https://www.cncf.io/certification/kcna/

---

## Sürüm Notları

### v1.0 (2025-10-23) - Birleştirilmiş ve Genişletilmiş Sürüm

- İki ayrı belgeden (v0.91 ve v1.1) tam birleştirme
- Tüm bölümler gözden geçirildi ve güncellendi
- Eksik bilgiler tamamlandı
- TR/EN terim karşılıkları eklendi
- Sık yapılan hatalar ve çözümleri bölümü eklendi
- Performance tuning checklist eklendi
- En iyi uygulama önerileri genişletildi

### v0.91 (2025-10-20)

- RHEL 9.x güncellemeleri
- Podman 5.x özellikleri
- Quadlet detaylı anlatım

**💡 QUADLET - MODERN SYSTEMD ENTEGRASYONU**
- **Neden Quadlet:** podman-generate-systemd'nin modern halefi
- **Avantaj:** Basit syntax, native systemd features
- **Lokasyon:** ~/.config/containers/systemd/ (rootless)
- **Otomatik:** .container → .service dönüşümü otomatik

- Multi-architecture support
- GPU support eklendi
- Genişletilmiş troubleshooting
- CI/CD pipeline örnekleri
- Advanced networking scenarios

### v0.9 (İlk sürüm)

- Temel Podman komutları
- systemd entegrasyonu
- Basit deployment patterns

---

## Lisans ve Katkı

**Lisans:** Creative Commons BY-SA 4.0

**Katkıda Bulunma:** Bu döküman açık kaynaklıdır. Katkılarınızı bekliyoruz:

- Hata düzeltmeleri
- Yeni örnekler ve senaryolar
- Best practice önerileri
- Çeviri ve yerelleştirme
- Performance tuning ipuçları

**İletişim:**

- Email: remzi@akyuz.tech

---

## Önemli Notlar

**Production Kullanımı:**

Bu el kitabı production ortamları için hazırlanmıştır. Bununla birlikte:

- Tüm komutları ve konfigürasyonları önce **test ortamında** deneyin
- Production'a geçmeden önce kapsamlı testler yapın
- Her ortam farklıdır, konfigürasyonları **kendi ihtiyaçlarınıza göre uyarlayın**
- Backup ve disaster recovery planınızı mutlaka hazırlayın
- Güvenlik en önemli önceliğiniz olsun

**Güncelleme:**

- Bu döküman düzenli olarak güncellenmektedir
- Son sürüm için resmi repository'yi kontrol ediniz
- Podman ve RHEL sürümlerini takip edin
- Security advisory'leri düzenli olarak kontrol edin

**Destek:**

- Resmi Red Hat desteği için: https://access.redhat.com/support
- Community support için: Podman mailing list ve GitHub discussions
- Enterprise support gerekiyorsa Red Hat subscription'ı değerlendirin

---

**Son güncelleme:** 2025-10-23

**Döküman sürümü:** 1.0 (Birleştirilmiş ve Kapsamlı Sürüm)

**Uyumluluk:** RHEL 9.x, AlmaLinux 9.x, Rocky Linux 9.x | Podman 4.x - 5.x





## Podman Build Komutları - Detaylı Açıklamalar

**💡 PODMAN BUILD - IMAGE OLUŞTURMA**
- **Amaç:** Dockerfile'dan container image build eder
- **-t flag:** Image'e tag/isim verir (myapp:v1.0)
- **Context:** Build context olarak mevcut dizin (.) verilir
- **--no-cache:** Cache kullanma, her layer yeniden build
- **--squash:** Tüm layer'ları tek layer'a birleştir (küçük image)

**💡 MULTI-STAGE BUILD - NEDEN ÖNEMLİ?**
- **Amaç:** Build dependencies'leri runtime'dan ayırır
- **Avantaj:** Final image küçük, sadece runtime gereksinimler
- **Pattern:** Stage 1=build (gcc, make), Stage 2=runtime (binary)
- **Security:** Build tools production'da bulunmaz
- **Örnek:** Go app build → 1GB builder, 10MB final image

**💡 BUILD ARGS - PARAMETERIZED BUILDS**
- **ARG vs ENV:** ARG sadece build-time, ENV runtime'da da
- **Usage:** podman build --build-arg VERSION=1.0
- **Use Case:** Base image version, API endpoints
- **Security:** Secret'leri ARG ile GÖNDERMEYIN





## Container Registry Komutları

**💡 PODMAN LOGIN - AUTHENTICATION**
- **Amaç:** Private registry'ye credential verir
- **Storage:** ~/.config/containers/auth.json (encrypted)
- **Use Case:** Private company registry, DockerHub private repos
- **Security:** CI/CD'de secret management kullanın

**💡 PODMAN PUSH - IMAGE PAYLAŞIMI**
- **Amaç:** Local image'i registry'ye yükler
- **Format:** podman push localhost/myapp:v1 registry.company.com/myapp:v1
- **Tagging:** Push öncesi tag'i registry URL ile başlatın
- **CI/CD:** Build pipeline'ın son adımı push

**💡 PODMAN PULL - IMAGE İNDİRME**
- **Amaç:** Registry'den image indirir
- **Default:** docker.io (DockerHub)
- **registries.conf:** Birden fazla registry tanımlanabilir
- **Security:** TLS doğrulama, insecure registry'den çekmeyin

**💡 SKOPEO - ADVANCED REGISTRY TOOL**
- **Amaç:** Image'leri inspect, copy, delete (daemon gerektirmeden)
- **Avantaj:** Local storage kullanmadan image transfer
- **Use Case:** Registry'ler arası migration
- **Command:** skopeo copy docker://source oci://dest





## Monitoring ve Logging - Production Essentials

**💡 PODMAN STATS - REAL-TIME MONITORING**
- **Amaç:** Container resource kullanımını gerçek zamanlı gösterir
- **Metrikler:** CPU%, MEM usage, NET I/O, BLOCK I/O
- **Format:** --format json (prometheus integration için)
- **Use Case:** Container memory leak tespit, CPU spike analizi

**💡 PODMAN TOP - PROCESS MONITORING**
- **Amaç:** Container içinde çalışan processleri gösterir
- **Host View:** ps aux | grep container-name (host perspektifi)
- **Use Case:** Zombie process, unexpected process tespit

**💡 PODMAN SYSTEM DF - DISK USAGE**
- **Amaç:** Image, container, volume disk kullanımını gösterir
- **Warning:** Disk dolarsa container başlamaz
- **Cleanup:** podman system prune -a --volumes
- **Monitoring:** Script ile otomatik cleanup threshold

**💡 PROMETHEUS + GRAFANA - PRODUCTION MONITORING**
- **Podman Exporter:** systemd metrics ve container stats
- **Alerting:** Memory limit yaklaşınca alert
- **Dashboards:** Pre-built Grafana dashboard'ları
- **Best Practice:** Tüm production sistem'ler için zorunlu





## Troubleshooting - Systematic Debug Approach

**💡 DEBUG METODOLOJİSİ - ADIM ADIM**
1. **Container Logs:** podman logs container-name --tail 100
2. **Inspect:** podman inspect container-name | jq .State
3. **Events:** podman events --filter container=name
4. **Exec:** podman exec -it name /bin/sh (container içi debug)
5. **Host Logs:** journalctl -xe | grep podman

**💡 NETWORK DEBUG - CONNECTIVITY ISSUES**
- **Ping Test:** podman exec name ping gateway
- **DNS Test:** podman exec name nslookup google.com
- **Port Check:** podman exec name netstat -tlnp
- **Firewall:** firewall-cmd --list-all
- **SELinux:** ausearch -m avc | grep podman

**💡 PERMISSION DENIED - COMMON CAUSES**
1. **SELinux:** chcon -t container_file_t /path
2. **File Owner:** chown -R user:user /path
3. **Rootless:** /etc/subuid and /etc/subgid configured?
4. **Namespace:** User namespace mapping correct?

**💡 CONTAINER WON'T START - CHECKLIST**
- [ ] Image pulled successfully?
- [ ] Port already in use? (ss -tlnp | grep port)
- [ ] Volume path exists?
- [ ] SELinux context correct?
- [ ] Resource limits too restrictive?
- [ ] Check: podman events --filter container=name



---

## BEST PRACTICES VE "NEDEN" - ÖZET KISIM

### Neden Rootless Podman Kullanmalı?

**GÜVENLIK RİSKİ:** Root container = container escape durumunda host'a tam erişim
**ÇÖZÜM:** Rootless Podman → container escape bile kullanıcı yetkisiyle sınırlı

**Rootless Avantajları:**
1. **Zero Trust:** Container breach olsa bile root erişimi yok
2. **Multi-Tenancy:** Farklı kullanıcılar izole container'lar çalıştırabilir
3. **Audit:** Hangi kullanıcı hangi container'ı çalıştırdı açık
4. **Compliance:** Security standardlarına uyum (SOC2, ISO 27001)

**Ne Zaman Root Gerekir:**
- Privileged operations (örn: network device access)
- Port 1024 altı bind (CAP_NET_BIND_SERVICE ile çözülebilir)
- Kernel module loading

---

### Neden Systemd Entegrasyonu Kritik?

**PROBLEM:** `podman run` ile başlatılan container geçicidir
- Sunucu reboot → container kaybolur
- Process crash → restart yok
- Log yönetimi → manuel

**ÇÖZÜM:** systemd + Quadlet entegrasyonu
- **Otomatik Başlatma:** Boot sırasında dependency order ile
- **Restart Policy:** on-failure, always, unless-stopped
- **Resource Limits:** cgroup v2 ile CPU, memory, I/O kontrolü
- **Logging:** journald entegrasyonu, merkezi log toplama
- **Dependency Management:** Database container önce başlasın

**Gerçek Senaryo:**
```
Web App → requires PostgreSQL → requires Network
systemd doğru sırayla başlatır, biri başarısız olursa zinciri durdurur
```

---

### Neden Volume Kullanmalı? (Bind Mount değil)

**BIND MOUNT SORUNLARI:**
- Host path'e bağımlılık (taşınabilirlik düşük)
- Permission karmaşası (user ID mapping)
- SELinux context manuel ayar gerekir
- Backup strategy karmaşık

**NAMED VOLUME AVANTAJLARI:**
- **Portable:** Host path'den bağımsız
- **Managed:** Podman volume lifecycle yönetir
- **Backup:** `podman volume export/import`
- **Performance:** Driver optimizasyonu
- **SELinux:** Otomatik context yönetimi

**Ne Zaman Bind Mount:**
- Config dosyaları (read-only)
- Development ortamı (kod değişikliklerini hemen görmek için)
- Log dosyaları (host'ta analiz için)

---

### Neden Her Container'a Resource Limit?

**PROBLEM: Resource Starvation**
- Memory leak olan container → host OOM killer → tüm containerlar ölür
- CPU-intensive process → diğer container'lar starve
- Disk full → yeni container başlamaz

**ÇÖZÜM: Resource Limits**
```bash
# WRONG
podman run myapp  # Limit yok, tehlikeli!

# RIGHT
podman run \
  --memory=2G --memory-swap=2G \  # OOM önleme
  --cpus=1.5 \                    # CPU cap
  --pids-limit=200 \              # Fork bomb önleme
  myapp
```

**Production Stratejisi:**
1. **Profiling:** Monitoring ile normal kullanımı ölçün
2. **Buffer:** %20-30 üstü limit koyun
3. **Alerting:** %80 kullanımda uyarı
4. **Testing:** Load test ile limitleri doğrulayın

---

### Neden Her Image Scan Edilmeli?

**REALİTE:** 2024'te container breach'lerinin %70'i bilinen CVE'lerden

**ÇÖZÜM: Multi-Layer Security**
```bash
# 1. Build-time scan
podman build -t myapp .
trivy image myapp  # FAIL on HIGH/CRITICAL

# 2. Registry'ye push öncesi scan
skopeo inspect docker://myapp | trivy image

# 3. Runtime scan
trivy image --severity HIGH,CRITICAL myapp
```

**CI/CD Pipeline'a Entegre:**
- Build → Scan → Fail on Critical CVE → Manual review
- Günlük scheduled scan (yeni CVE bulunabilir)
- Alert on new vulnerabilities

---

### Neden SELinux Enforcing Modunda Çalışmalı?

**PERMISSIVE MODE TEHLİKESİ:**
- SELinux policy violation'ları sadece log'lar, engellenmez
- False sense of security
- Gerçek production security yok

**ENFORCING MODE AVANTAJLARI:**
1. **Mandatory Access Control:** Discretionary (chmod) yetmez
2. **Process Isolation:** Container escape sınırlandırılır
3. **Defense in Depth:** Kernel + namespace + cgroup + SELinux
4. **Audit Trail:** Her violation loglanır

**Permissive Kullanım:**
- Sadece policy development/debug aşaması
- Production'da ASLA

**Troubleshooting:**
```bash
# SELinux denial bul
ausearch -m avc -ts recent | grep podman

# Policy modülü oluştur
audit2allow -a -M mypolicy
semodule -i mypolicy.pp
```

---

### Neden Health Check Şart?

**PROBLEM: Silent Failures**
- Process çalışıyor ama respond etmiyor (deadlock)
- Database connection pool tükendi
- Out of memory yakın ama henüz crash olmadı

**ÇÖZÜM: Proactive Health Monitoring**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1
```

**Health Check Levels:**
1. **Basic:** Process running? (podman ps)
2. **Liveness:** Port açık? (curl -f endpoint)
3. **Readiness:** Dependencies hazır? (DB connection test)
4. **Deep:** Business logic çalışıyor? (/health/deep)

**Orchestration Integration:**
- systemd: unhealthy → restart
- Kubernetes: liveness probe fail → restart
- Load balancer: readiness fail → remove from pool

---

### Neden Immutable Infrastructure?

**GELENEKSEL: Pet Model (BAD)**
- Server'lar manual configure edilir
- Güncellemeler manuel
- Configuration drift (her server farklı)
- Disaster recovery zor

**MODERN: Cattle Model + Immutable (GOOD)**
- Infrastructure as Code (IaC)
- Container image = immutable artifact
- Güncelleme = yeni image deploy
- Rollback = önceki image'e dön
- Disaster recovery = aynı image yeniden deploy

**Podman ile Immutable:**
```bash
# WRONG: Container içine girip değişiklik
podman exec app apt-get install vim  # Container ölünce kaybolur

# RIGHT: Dockerfile değiştir, yeniden build
FROM myapp:v1
RUN apt-get update && apt-get install -y vim
```

---

## KARAR AĞACI: Hangi Yöntemi Ne Zaman?

### Storage: Bind Mount vs Volume?

```
Kullanım amacı?
├─ Development (live code reload) → Bind Mount
├─ Production persistent data → Named Volume
├─ Config files (read-only) → Bind Mount (:ro)
├─ Logs (host'ta analiz) → Bind Mount
└─ Database data → Named Volume + Backup strategy
```

### Network: Bridge vs Host vs Custom?

```
Network ihtiyacı?
├─ Default izole network → Bridge (default)
├─ Maximum performance → Host (careful!)
├─ Multi-container orchestration → Custom Network
├─ Port conflict yok, basit → Bridge
└─ Service discovery gerekli → Custom Network + DNS
```

### Container: Rootless vs Root?

```
Yetki ihtiyacı?
├─ Standart web app → Rootless
├─ Port < 1024 → Rootless + CAP_NET_BIND_SERVICE
├─ Kernel module → Root (veya ayrı VM)
├─ Privileged hardware access → Root
└─ Güvenlik öncelik → ROOTLESS (always)
```

### Image: Alpine vs Debian/Ubuntu?

```
İhtiyaç?
├─ Minimal boyut (<10MB) → Alpine
├─ Geniş paket desteği → Debian/Ubuntu
├─ Compatibility issues yok → Alpine
├─ glibc required → Debian/Ubuntu
└─ Production (kararlılık) → Debian Slim / Ubuntu
```

---

## HATA ÖNLEME CHECKLİSTİ

### Container Başlatmadan Önce

- [ ] Image scan edildi? (trivy/grype)
- [ ] Base image güncel? (latest değil, tagged version)
- [ ] Health check tanımlı?
- [ ] Resource limits set? (memory, cpu)
- [ ] Non-root user? (USER directive)
- [ ] SELinux context doğru?
- [ ] Volume path exists?
- [ ] Network configured?
- [ ] Environment variables set?
- [ ] Secrets volume/file ile inject edildi? (ENV'de yok)

### Production Deploy Öncesi

- [ ] Systemd service file hazır?
- [ ] Restart policy configured?
- [ ] Logging centralized?
- [ ] Monitoring/alerting ready?
- [ ] Backup strategy defined?
- [ ] Rollback plan tested?
- [ ] Load testing yapıldı?
- [ ] Security audit passed?
- [ ] Documentation updated?
- [ ] Team trained?

### Troubleshooting İlk Adımlar

```bash
# 1. Container çalışıyor mu?
podman ps -a | grep myapp

# 2. Loglar ne diyor?
podman logs myapp --tail 50

# 3. Resource problemi var mı?
podman stats myapp --no-stream

# 4. Network ok?
podman exec myapp ping -c 3 8.8.8.8

# 5. SELinux engelliyor mu?
ausearch -m avc -ts recent | grep myapp

# 6. Firewall açık mı?
firewall-cmd --list-ports

# 7. Process çalışıyor mu?
podman top myapp

# 8. Health check?
podman inspect myapp | jq .State.Health
```

---



---

## 📚 BU DÖKÜMANDA YAPILAN İYİLEŞTİRMELER

### ✅ Eklenen İçerikler

1. **"Neden" ve "Niçin" Açıklamaları**
   - Her komutun kullanım amacı
   - Gerçek dünya senaryoları
   - Alternatif yöntemlerle karşılaştırma

2. **Bölüm Giriş Açıklamaları**
   - Bölümün önemi
   - Kullanım senaryoları
   - Gerçek problem örnekleri

3. **Komut Detayları**
   - 💡 işaretli inline açıklamalar
   - Flag'lerin anlamı ve kullanımı
   - Ne zaman kullanılacağı bilgisi

4. **Best Practices Justification**
   - Neden bu yöntem öneriliyor
   - Alternatiflerinin dezavantajları
   - Production senaryoları

5. **Karar Ağaçları**
   - Hangi teknolojiyi ne zaman kullanmalı
   - Sistemat ik karar verme rehberi

6. **Troubleshooting Metodolojisi**
   - Adım adım debug yaklaşımı
   - Common pitfalls ve çözümleri

### 🎯 Hedef Kitle İçin Değer

**Sistem Yöneticileri:**
- Komutların altında yatan mantık
- Production deployment stratejileri
- Risk azaltma teknikleri

**DevOps Mühendisleri:**
- CI/CD pipeline entegrasyonu
- Automation best practices
- Monitoring ve alerting

**Yeni Başlayanlar:**
- Temel kavramların neden önemli olduğu
- Hangi komutu ne zaman kullanacağı
- Sık yapılan hatalardan kaçınma

---

## 📖 KULLANIM ÖNERİLERİ

1. **İlk Okuma:** Tüm "💡" işaretli açıklamaları okuyun
2. **Pratik:** Her komutu test ortamında deneyin
3. **Derinlemesine:** "Neden" bölümlerini anlayın
4. **Referans:** Specific kullanım için arama yapın
5. **Güncel Kalma:** Düzenli olarak güncellemeleri kontrol edin

---

