# Linux Namespace ve Podman Secrets - Kapsamlı El Kitabı

## Giriş

Bu döküman, modern container teknolojilerinin temelini oluşturan iki kritik konuyu ele alır:

1. **Linux Namespaces:** Container izolasyonunun çekirdeği
2. **Podman Secrets:** Hassas bilgilerin güvenli yönetimi

Bu dökümanı okuduktan sonra, container teknolojilerinin nasıl çalıştığını derinlemesine anlayacak ve production ortamlarında güvenli şekilde hassas bilgileri yönetebileceksiniz.

---

## İçindekiler

1. [Linux Namespaces](#linux-namespaces)
   - [Namespace Nedir?](#namespace-nedir)
   - [PID Namespace](#pid-namespace)
   - [Network Namespace](#network-namespace)
   - [Mount Namespace](#mount-namespace)
   - [UTS Namespace](#uts-namespace)
   - [IPC Namespace](#ipc-namespace)
   - [User Namespace](#user-namespace)
   - [Cgroup Namespace](#cgroup-namespace)
   - [Time Namespace](#time-namespace)

2. [Podman Secrets](#podman-secrets)
   - [Secrets Nedir?](#secrets-nedir)
   - [Secret Oluşturma ve Yönetme](#secret-oluşturma-ve-yönetme)
   - [Container'da Secret Kullanımı](#containerda-secret-kullanımı)
   - [Gerçek Dünya Senaryoları](#gerçek-dünya-senaryoları)

---

## Linux Namespaces

### Namespace Nedir?

Linux namespace'leri, sistem kaynaklarını izole etmek için kullanılan **kernel seviyesinde** bir mekanizmadır. Container teknolojilerinin (Docker, Podman, LXC) temelini oluşturur.

#### Neden Namespace'ler Gerekli?

Geleneksel bir Linux sisteminde, tüm process'ler aynı global kaynakları paylaşır:
- Aynı process ID (PID) tablosu
- Aynı network interface'ler
- Aynı dosya sistemi mount'ları
- Aynı hostname

Bu durum ciddi sorunlara yol açar:

**Güvenlik Problemi:**
```
❌ Web uygulamanız hack'lendi ve saldırgan sistemdeki 
   TÜM process'leri görebilir, network trafiğini izleyebilir.
```

**İzolasyon Problemi:**
```
❌ İki farklı uygulama aynı port'u (8080) kullanmaya çalışıyor.
❌ Bir uygulama kritik sistem dosyalarını değiştirebilir.
```

**Namespace'ler bu sorunları çözer:**

```
✅ Her container kendi izole ortamında çalışır
✅ Container içinden sadece kendi process'lerini görürsünüz
✅ Her container kendi network stack'ine sahiptir
✅ Dosya sistemi değişiklikleri container'a özeldir
```

#### Namespace'ler Nasıl Çalışır?

```
                   HOST SYSTEM
    ┌─────────────────────────────────────┐
    │  Global Namespace (Host)            │
    │  - PID: 1-65535                     │
    │  - Network: eth0, lo                │
    │  - Mounts: /, /home, /var           │
    │                                     │
    │  ┌────────────────┐ ┌─────────────┐│
    │  │ Container 1    │ │ Container 2 ││
    │  │ PID NS: 1-10   │ │ PID NS: 1-5 ││
    │  │ NET NS: eth0   │ │ NET NS: eth0││
    │  │ MNT NS: /app   │ │ MNT NS: /web││
    │  └────────────────┘ └─────────────┘│
    └─────────────────────────────────────┘
```

#### Tarihçe ve Evrim

Linux namespace'leri 20+ yılı aşkın bir gelişim sürecinin ürünüdür:

| Yıl | Kernel | Namespace | Açıklama |
|-----|--------|-----------|----------|
| 2002 | 2.4.19 | Mount (MNT) | İlk namespace türü - dosya sistemi izolasyonu |
| 2006 | 2.6.19 | UTS, IPC | Hostname ve process arası iletişim izolasyonu |
| 2008 | 2.6.24 | PID | Process ID izolasyonu - container'ların kilit taşı |
| 2009 | 2.6.29 | Network (NET) | Network stack izolasyonu - bağımsız network'ler |
| 2013 | 3.8 | User | User ID mapping - rootless container'lar mümkün oldu |
| 2016 | 4.6 | Cgroup | Cgroup görünümü izolasyonu |
| 2020 | 5.6 | Time | Sistem saati izolasyonu - en yeni eklenti |

#### Namespace Türleri ve İzolasyon

| Namespace | Flag | İzole Ettiği Kaynak | Kullanım Alanı |
|-----------|------|---------------------|----------------|
| PID | CLONE_NEWPID | Process ID'ler ve process tree | Her container'ın kendi init process'i (PID 1) |
| NET | CLONE_NEWNET | Network stack (interface, routing, firewall) | Her container'ın kendi IP adresi ve port'ları |
| MNT | CLONE_NEWNS | Mount noktaları ve dosya sistemi | Her container'ın kendi dosya sistemi görünümü |
| UTS | CLONE_NEWUTS | Hostname ve domain name | Her container'ın kendi hostname'i |
| IPC | CLONE_NEWIPC | System V IPC, POSIX message queues | Process'ler arası iletişim izolasyonu |
| USER | CLONE_NEWUSER | User ve Group ID mapping | Rootless container'lar (güvenlik) |
| CGROUP | CLONE_NEWCGROUP | Cgroup root directory görünümü | Cgroup yapısının izolasyonu |
| TIME | CLONE_NEWTIME | System clock (monotonic, boottime) | Test ortamları için zaman manipülasyonu |

#### Namespace'lerin Sistem Üzerindeki Temsili

Linux'ta her process bir veya daha fazla namespace'e aittir. Bu ilişki `/proc/[pid]/ns/` dizininde görülebilir:

```bash
# Kendi process'inizin namespace'lerini görüntüleyin
$ ls -l /proc/$$/ns/
total 0
lrwxrwxrwx 1 user user 0 cgroup -> 'cgroup:[4026531835]'
lrwxrwxrwx 1 user user 0 ipc -> 'ipc:[4026531839]'
lrwxrwxrwx 1 user user 0 mnt -> 'mnt:[4026531840]'
lrwxrwxrwx 1 user user 0 net -> 'net:[4026531992]'
lrwxrwxrwx 1 user user 0 pid -> 'pid:[4026531836]'
lrwxrwxrwx 1 user user 0 time -> 'time:[4026531834]'
lrwxrwxrwx 1 user user 0 user -> 'user:[4026531837]'
lrwxrwxrwx 1 user user 0 uts -> 'uts:[4026531838]'
```

Her satır bir symbolic link'tir ve namespace türü ile benzersiz inode numarasını gösterir. Aynı inode numarasına sahip process'ler aynı namespace'i paylaşır.

#### Namespace Yönetim Komutları

| Komut | Açıklama | Örnek |
|-------|----------|-------|
| `unshare` | Yeni namespace'de process başlatır | `unshare --pid --fork bash` |
| `nsenter` | Varolan namespace'e girer | `nsenter --target 1234 --pid --mount` |
| `ip netns` | Network namespace'leri yönetir | `ip netns add mynet` |
| `lsns` | Tüm namespace'leri listeler | `lsns -t net` |

---

### PID Namespace

#### Neden PID Namespace?

Geleneksel Linux sisteminde tüm process'ler tek bir global PID tablosunu paylaşır. Bu ciddi güvenlik ve yönetim sorunları yaratır:

**Güvenlik Riski:**
```bash
# Container içinde çalışan bir process
$ ps aux
# ❌ Host sistemdeki TÜM process'leri görebilir
# ❌ Sistemdeki kritik process'leri (systemd, sshd) görebilir
# ❌ Diğer kullanıcıların process'lerini görebilir
```

**Kaynak Yönetimi:**
```bash
# ❌ PID collision riski
# ❌ Process sayısı limitleri global
# ❌ Init system (PID 1) tek ve değiştirilemez
```

**PID Namespace'in Çözümü:**

```
Host System                Container 1           Container 2
PID 1 (init/systemd)       
PID 1234                   PID 1 (container init) 
PID 1235                   PID 2 (app)
PID 1236                                         PID 1 (init)
PID 1237                                         PID 2 (db)
```

#### PID Namespace Özellikleri

1. **Her namespace kendi PID 1'inden başlar**
   - Container içindeki ilk process PID 1 olur
   - Host'ta bu process farklı bir PID'ye sahiptir
   - PID 1 özel sorumlulukları olan "init" process'tir

2. **Hiyerarşik yapı**
   - Parent namespace, child namespace'deki process'leri görebilir
   - Child namespace, parent'ı göremez (güvenlik)
   - Nested namespace'ler mümkündür

3. **PID 1'in özel rolü**
   - Orphan process'leri adopt eder
   - Zombie process'leri reap eder (temizler)
   - Namespace sonlandığında tüm process'ler öldürülür

#### Görselleştirme: PID Namespace Hiyerarşisi

```
Host (Global Namespace)
PID: 1, 2, 3, ... 1234, 1235, 1236 ...
│
├─ Container A (PID NS A)
│  PID: 1, 2, 3, 4
│  (Host'ta: 1234, 1235, 1236, 1237)
│  │
│  └─ Container A-1 (Nested PID NS)
│     PID: 1, 2
│     (Host'ta: 1238, 1239)
│
└─ Container B (PID NS B)
   PID: 1, 2, 3
   (Host'ta: 1240, 1241, 1242)
```

#### Temel Kullanım

```bash
# Yeni PID namespace'de shell başlat
$ sudo unshare --pid --fork --mount-proc bash

# Process listesini görüntüle (sadece bu namespace'deki processler)
$ ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  12345  1234 pts/0    S    10:00   0:00 bash
root        10  0.0  0.0  23456  2345 pts/0    R+   10:01   0:00 ps aux

# Host sistemde bu process'ler farklı PID'lere sahip
```

**Komut Açıklaması:**
- `--pid`: Yeni PID namespace oluştur
- `--fork`: Child process oluştur (gerekli çünkü PID namespace sadece child process'lerde aktiftir)
- `--mount-proc`: /proc dosya sistemini yeniden mount et (namespace'e özgü process listesi için gerekli)

#### PID Namespace'in Kritik Detayları

**1. /proc Dosya Sistemi:**

PID namespace izolasyonu için `/proc`'un doğru şekilde mount edilmesi kritiktir:

```bash
# ❌ Yanlış: /proc mount edilmemiş
$ sudo unshare --pid --fork bash
$ ps aux
# Host sistemdeki tüm process'leri gösterir!

# ✅ Doğru: /proc yeniden mount edilmiş
$ sudo unshare --pid --fork --mount-proc bash
$ ps aux
# Sadece namespace içindeki process'ler görünür
```

**2. PID 1'in Zombie Reaping Sorumluluğu:**

PID 1, özel bir sorumluluk taşır: ölen child process'leri temizlemek (reap etmek).

```bash
# Kötü PID 1 örneği - zombie process'leri temizlemiyor
$ cat > bad_init.sh << 'EOF'
#!/bin/bash
while true; do sleep 1; done
EOF

# ❌ Bu bash script'i zombie process'leri temizleyemez
$ sudo unshare --pid --fork bash bad_init.sh &

# ✅ Düzgün init process kullanımı (tini, dumb-init)
$ sudo unshare --pid --fork tini -- your-application
```

**3. Signal Handling:**

PID 1, SIGKILL ve SIGSTOP dışındaki sinyalleri yok sayabilir (özel kernel koruması):

```bash
# PID 1'e SIGTERM gönderme
$ sudo unshare --pid --fork bash
# [Namespace içinde]
$ kill -TERM 1  # İşlem görmeyebilir!

# PID 1'i sonlandırmak için namespace'ten çıkın veya
# SIGKILL kullanın (son çare)
```

#### C Programı ile PID Namespace

```c
#define _GNU_SOURCE
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
#include <sys/mount.h>

#define STACK_SIZE (1024 * 1024)

static char child_stack[STACK_SIZE];

int child_func(void *arg) {
    printf("Child process başladı\n");
    printf("Child PID (namespace içinde): %d\n", getpid());
    printf("Child Parent PID: %d\n", getppid());
    
    // /proc'u yeniden mount et (namespace-aware)
    // MS_REC | MS_PRIVATE: Mount propagation'ı engeller
    mount(NULL, "/", NULL, MS_REC | MS_PRIVATE, NULL);
    
    // /proc'u namespace'e özgü olarak mount et
    mount("proc", "/proc", "proc", 0, NULL);
    
    // Bu namespace'de bu process PID 1'dir
    printf("\nNamespace içindeki process listesi:\n");
    system("ps aux");
    
    printf("\nShell başlatılıyor...\n");
    execl("/bin/bash", "bash", NULL);
    
    perror("execl failed");
    return 1;
}

int main() {
    printf("Parent PID (host namespace'de): %d\n\n", getpid());
    
    // Yeni PID namespace ile child process oluştur
    // SIGCHLD: Parent, child sonlandığında bildirim alır
    pid_t pid = clone(child_func, 
                     child_stack + STACK_SIZE,  // Stack'in üst adresini ver
                     CLONE_NEWPID | CLONE_NEWNS | SIGCHLD,
                     NULL);
    
    if (pid == -1) {
        perror("clone failed");
        exit(EXIT_FAILURE);
    }
    
    printf("Parent: Child process oluşturuldu, PID (host namespace'de): %d\n", pid);
    
    // Child process'in bitmesini bekle
    int status;
    waitpid(pid, &status, 0);
    
    if (WIFEXITED(status)) {
        printf("Child process exit code: %d\n", WEXITSTATUS(status));
    }
    
    return EXIT_SUCCESS;
}
```

**Derleme ve Çalıştırma:**

```bash
$ gcc -o pid_ns pid_namespace.c
$ sudo ./pid_ns
Parent PID (host namespace'de): 12345

Child process başladı
Child PID (namespace içinde): 1
Child Parent PID: 0

Namespace içindeki process listesi:
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  12000  3000 ?        S    10:30   0:00 ./pid_ns

Shell başlatılıyor...
root@hostname:~# ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  12000  3000 ?        S    10:30   0:00 ./pid_ns
root         2  0.0  0.0  21000  4000 ?        S    10:30   0:00 bash
root         3  0.0  0.0  16000  3000 ?        R+   10:30   0:00 ps aux
```

**Kod Açıklaması:**
- `clone()`: Yeni process oluştururken namespace'leri belirtir
- `CLONE_NEWPID`: Yeni PID namespace
- `CLONE_NEWNS`: Mount namespace (proc mount için gerekli)
- `MS_REC | MS_PRIVATE`: Mount propagation kontrolü
- Child function içinde `/proc` yeniden mount ediliyor

#### Pratik Örnek: İzole Test Ortamı

```bash
#!/bin/bash
# test_environment.sh - İzole test ortamı oluştur

set -e  # Hata durumunda dur

echo "=== İzole Test Ortamı ==="
echo "Test başlatılıyor..."

# Yeni PID namespace'de process çalıştır
sudo unshare --pid --fork --mount-proc bash -c '
    echo "Test ortamı başlatıldı"
    echo "PID: $$"
    echo "Namespace içindeki process sayısı: $(ps aux | wc -l)"
    echo ""
    
    # Test uygulaması başlat (örnek: web server)
    echo "Web server başlatılıyor..."
    python3 -m http.server 8080 > /dev/null 2>&1 &
    APP_PID=$!
    
    echo "Uygulama PID (namespace içinde): $APP_PID"
    
    # Health check
    sleep 2
    if kill -0 $APP_PID 2>/dev/null; then
        echo "✓ Uygulama başarıyla başlatıldı"
        echo "✓ Erişim URL: http://localhost:8080"
    else
        echo "✗ Uygulama başlatılamadı"
        exit 1
    fi
    
    echo ""
    echo "Process listesi:"
    ps aux
    
    echo ""
    echo "Test için CTRL+C ile çıkın..."
    
    # Process izle
    while kill -0 $APP_PID 2>/dev/null; do
        sleep 2
    done
    
    echo "Uygulama sonlandı"
'

echo "Test ortamı temizlendi"
```

**Kullanım:**

```bash
$ chmod +x test_environment.sh
$ ./test_environment.sh
=== İzole Test Ortamı ===
Test başlatılıyor...
Test ortamı başlatıldı
PID: 1
Namespace içindeki process sayısı: 2

Web server başlatılıyor...
Uygulama PID (namespace içinde): 2
✓ Uygulama başarıyla başlatıldı
✓ Erişim URL: http://localhost:8080

Process listesi:
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  11000  2000 pts/0    S    11:00   0:00 bash -c ...
root         2  0.1  0.5  50000 12000 pts/0    S    11:00   0:00 python3 -m http.server
root         3  0.0  0.0  16000  3000 pts/0    R+   11:00   0:00 ps aux
```

#### Nested PID Namespace (İç İçe Namespace'ler)

PID namespace'leri iç içe (nested) oluşturulabilir. Her seviye bir öncekinin child'ı olur:

```bash
# Level 0 (Host System)
$ echo "Host PID: $$ (Level 0)"
Host PID: 1234 (Level 0)

$ ps aux | wc -l
245  # Host'ta 245 process çalışıyor

# Level 1 Namespace
$ sudo unshare --pid --fork --mount-proc bash
# echo "Level 1 PID: $$ (Container)"
Level 1 PID: 1 (Container)

# ps aux | wc -l
4  # Level 1'de sadece 4 process

# Level 2 Namespace (Nested Container)
# unshare --pid --fork --mount-proc bash
# echo "Level 2 PID: $$ (Nested Container)"
Level 2 PID: 1 (Nested Container)

# ps aux | wc -l
3  # Level 2'de sadece 3 process

# Her seviyede PID 1, ancak host'tan bakıldığında farklı PID'ler
```

**Görselleştirme:**

```
Level 0 (Host)        Level 1 (Container)    Level 2 (Nested)
─────────────────────────────────────────────────────────────
PID: 1-9999          
     1234 ──────────► PID: 1
     1235            PID: 2
     1236            PID: 3 ──────────────► PID: 1
     1237            PID: 4                 PID: 2
```

**Nested Namespace Kullanım Senaryoları:**

1. **Container içinde Container (Docker-in-Docker benzeri)**
   ```bash
   # Ana container
   $ podman run -it --privileged alpine sh
   
   # Container içinde başka container
   # unshare --pid --fork --mount-proc sh
   ```

2. **Multi-tenant izolasyon**
   - Her tenant kendi namespace'inde
   - Her tenant'ın altında farklı uygulamalar

3. **Test senaryoları**
   - Karmaşık izolasyon testleri
   - Container davranışı simülasyonu

#### PID Namespace Troubleshooting

**Problem 1: Process'ler görünmüyor**

```bash
# Semptom
$ sudo unshare --pid --fork bash
$ ps aux
# Host sistemdeki tüm process'ler görünüyor!

# Çözüm: /proc'u mount etmeyi unutmuşsunuz
$ sudo unshare --pid --fork --mount-proc bash
$ ps aux  # Artık sadece namespace process'leri
```

**Problem 2: Zombie process'ler birikmesi**

```bash
# Semptom: Defunc (zombie) process'ler
$ ps aux
root  1  bash
root  5  [app] <defunct>
root  6  [app] <defunct>

# Sebep: PID 1 zombie reaping yapmıyor
# Çözüm: Düzgün init process kullanın (tini, dumb-init)
```

**Problem 3: Container kapanmıyor**

```bash
# Semptom: Container sonlandırılamıyor
$ podman stop mycontainer
# Timeout, sonra force kill

# Sebep: PID 1, SIGTERM sinyalini handle etmiyor
# Çözüm: Uygulamanızın SIGTERM'i yakalamasını sağlayın
```

#### PID Namespace Best Practices

1. **Her zaman --mount-proc kullanın**
   ```bash
   # ✓ Doğru
   $ unshare --pid --fork --mount-proc bash
   
   # ✗ Yanlış (proc mount edilmemiş)
   $ unshare --pid --fork bash
   ```

2. **Düzgün init process kullanın**
   ```bash
   # Container için tini kullanımı
   FROM alpine
   RUN apk add --no-cache tini
   ENTRYPOINT ["/sbin/tini", "--"]
   CMD ["your-app"]
   ```

3. **Signal handling'i düzgün yapın**
   ```python
   # Python örneği
   import signal
   import sys
   
   def signal_handler(sig, frame):
       print('SIGTERM alındı, temiz kapanış...')
       # Cleanup işlemleri
       sys.exit(0)
   
   signal.signal(signal.SIGTERM, signal_handler)
   ```

4. **PID 1 için resource cleanup**
   ```bash
   # PID 1 sonlandığında tüm child process'ler öldürülür
   # Bu yüzden PID 1'de kritik cleanup işlemlerini yapmayın
   ```

---

### Network Namespace

#### Neden Network Namespace?

Geleneksel Linux sisteminde tek bir global network stack vardır. Bu ciddi kısıtlamalar getirir:

**Port Conflict:**
```bash
# ❌ İki uygulama aynı portu kullanamaz
App1: 0.0.0.0:8080
App2: 0.0.0.0:8080  # ERROR: Address already in use
```

**Güvenlik Riski:**
```bash
# ❌ Tüm uygulamalar aynı network'ü paylaşır
# ❌ Bir uygulama tüm network trafiğini sniff edebilir
# ❌ Firewall kuralları global
```

**Network Namespace'in Çözümü:**

```
Host Network                Container Network
─────────────────────────────────────────────
eth0: 192.168.1.100        eth0: 10.0.0.2/24
Port 80: Apache            Port 80: Nginx
Port 443: Apache           Port 443: Nginx
Firewall: Global Rules     Firewall: Container Rules
```

Her container kendi network stack'ine sahiptir:
- ✅ Kendi IP adresi
- ✅ Kendi port'ları (10 container, hepsi port 80 kullanabilir)
- ✅ Kendi routing table
- ✅ Kendi firewall kuralları

#### Network Namespace Özellikleri

1. **Tam izolasyon**
   - Her namespace, tamamen ayrı bir network stack'tir
   - Kendi network interface'leri (eth0, eth1, lo)
   - Kendi routing table
   - Kendi ARP table
   - Kendi firewall (iptables/nftables) kuralları

2. **Loopback interface varsayılan olarak DOWN**
   - Yeni namespace'de `lo` interface kapalı gelir
   - Manuel olarak aktifleştirmelisiniz

3. **Virtual interface'ler ile bağlantı**
   - veth (Virtual Ethernet) pair: İki namespace'i bağlar
   - bridge: Çoklu namespace'i birbirine bağlar
   - macvlan/ipvlan: Fiziksel interface paylaşımı

#### Görselleştirme: Network Namespace Yapısı

```
┌─────────────────────────────────────────────────────────────┐
│                        Host System                          │
│                                                             │
│  ┌──────────────────┐    ┌──────────────────┐              │
│  │   eth0           │    │   docker0/br0    │              │
│  │ 192.168.1.100    │    │   172.17.0.1     │              │
│  └────────┬─────────┘    └────────┬─────────┘              │
│           │                       │                         │
│           │              ┌────────┴──────────┐              │
│           │              │                   │              │
│    ┌──────┴──────┐  ┌───┴────┐         ┌────┴────┐         │
│    │ Routing     │  │ veth0  │         │ veth1   │         │
│    │ Table       │  │ (host) │         │ (host)  │         │
│    └─────────────┘  └───┬────┘         └────┬────┘         │
│                         │                   │               │
│  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ ─ ─  │
│                         │                   │               │
│  ┌─────────────────────┴──┐    ┌───────────┴──────────┐    │
│  │  Container Namespace 1 │    │ Container Namespace 2│    │
│  │                        │    │                      │    │
│  │  ┌──────────────┐      │    │  ┌────────────────┐ │    │
│  │  │ eth0         │      │    │  │ eth0           │ │    │
│  │  │ 172.17.0.2   │      │    │  │ 172.17.0.3     │ │    │
│  │  └──────────────┘      │    │  └────────────────┘ │    │
│  │  ┌──────────────┐      │    │  ┌────────────────┐ │    │
│  │  │ lo           │      │    │  │ lo             │ │    │
│  │  │ 127.0.0.1    │      │    │  │ 127.0.0.1      │ │    │
│  │  └──────────────┘      │    │  └────────────────┘ │    │
│  │  Routing Table         │    │  Routing Table       │    │
│  │  Firewall Rules        │    │  Firewall Rules      │    │
│  └────────────────────────┘    └──────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

#### Temel Kullanım

```bash
# 1. Mevcut network namespace'leri listele
$ ip netns list
# (Boş çıktı - henüz namespace yok)

# 2. Yeni network namespace oluştur
$ sudo ip netns add blue
$ sudo ip netns add red

# 3. Oluşturulan namespace'leri listele
$ ip netns list
red
blue

# 4. Namespace bilgilerini görüntüle
$ ip netns identify $$
# (Boş - şu an global namespace'deyiz)

# 5. Network namespace'de komut çalıştır
$ sudo ip netns exec blue ip addr
1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
# Dikkat: Sadece lo interface var ve DOWN durumda!

# 6. Loopback interface'i aktifleştir
$ sudo ip netns exec blue ip link set lo up

# 7. Loopback test
$ sudo ip netns exec blue ping -c 1 127.0.0.1
PING 127.0.0.1 (127.0.0.1) 56(84) bytes of data.
64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.025 ms

--- 127.0.0.1 ping statistics ---
1 packets transmitted, 1 received, 0% packet loss

# 8. Namespace'i silme
$ sudo ip netns delete blue
$ sudo ip netns delete red
```

**Namespace Dosya Sistemi:**

Network namespace'ler `/var/run/netns/` dizininde saklanır:

```bash
$ ls -l /var/run/netns/
total 0
-r--r--r-- 1 root root 0 Oct 24 10:00 blue
-r--r--r-- 1 root root 0 Oct 24 10:01 red

# Bu dosyalar aslında /proc/[pid]/ns/net'e bind mount'tur
```

#### Virtual Ethernet (veth) Çiftleri

veth pair, iki namespace'i birbirine bağlayan sanal bir ethernet kablosudur. Bir ucundan gönderilen paket diğer uçtan çıkar.

**Konsept:**

```
Namespace A          Namespace B
    [veth-a]═══════════[veth-b]
       ↓                  ↓
    10.0.0.1          10.0.0.2
```

**Pratik Örnek:**

```bash
# 1. İki namespace oluştur
$ sudo ip netns add blue
$ sudo ip netns add red

# 2. veth çifti oluştur (iki uç: veth-blue ve veth-red)
$ sudo ip link add veth-blue type veth peer name veth-red

# 3. Oluşturulan interface'leri kontrol et
$ ip link show type veth
6: veth-red@veth-blue: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 state DOWN mode DEFAULT
7: veth-blue@veth-red: <BROADCAST,MULTICAST,M-DOWN> mtu 1500 state DOWN mode DEFAULT

# 4. Her bir ucu farklı namespace'e ata
$ sudo ip link set veth-blue netns blue
$ sudo ip link set veth-red netns red

# 5. Artık host'ta veth interface'leri görünmez
$ ip link show type veth
# (Boş - namespace'lere taşındı)

# 6. Blue namespace'i yapılandır
$ sudo ip netns exec blue ip addr add 10.0.0.1/24 dev veth-blue
$ sudo ip netns exec blue ip link set veth-blue up
$ sudo ip netns exec blue ip link set lo up

# 7. Red namespace'i yapılandır
$ sudo ip netns exec red ip addr add 10.0.0.2/24 dev veth-red
$ sudo ip netns exec red ip link set veth-red up
$ sudo ip netns exec red ip link set lo up

# 8. Bağlantıyı test et: Blue'dan Red'e ping
$ sudo ip netns exec blue ping -c 3 10.0.0.2
PING 10.0.0.2 (10.0.0.2) 56(84) bytes of data.
64 bytes from 10.0.0.2: icmp_seq=1 ttl=64 time=0.045 ms
64 bytes from 10.0.0.2: icmp_seq=2 ttl=64 time=0.038 ms
64 bytes from 10.0.0.2: icmp_seq=3 ttl=64 time=0.041 ms

# 9. Red'den Blue'ya ping
$ sudo ip netns exec red ping -c 3 10.0.0.1
PING 10.0.0.1 (10.0.0.1) 56(84) bytes of data.
64 bytes from 10.0.0.1: icmp_seq=1 ttl=64 time=0.032 ms
...

# 10. Routing table'ları kontrol et
$ sudo ip netns exec blue ip route
10.0.0.0/24 dev veth-blue proto kernel scope link src 10.0.0.1

$ sudo ip netns exec red ip route
10.0.0.0/24 dev veth-red proto kernel scope link src 10.0.0.2
```

**veth Çifti Özellikleri:**

- **Çift yönlü:** Her iki yönde de traffic akabilir
- **MTU:** Varsayılan 1500, her iki uçta aynı olmalı
- **MAC address:** Her interface otomatik MAC alır
- **State:** Her iki uç UP olmalı, biri DOWN ise bağlantı çalışmaz

#### Bridge ile Çoklu Namespace Bağlantısı

Bridge, birden fazla network interface'i birbirine bağlayan Layer 2 switch gibi çalışır. Birden fazla container'ı birbirine bağlamak için kullanılır.

**Konsept:**

```
                    ┌─────────┐
                    │ Bridge  │
                    │ br0     │
                    │10.0.1.1 │
                    └────┬────┘
             ┌───────────┼───────────┐
             │           │           │
         ┌───┴───┐   ┌───┴───┐   ┌───┴───┐
         │ veth0 │   │ veth1 │   │ veth2 │
         └───┬───┘   └───┬───┘   └───┬───┘
             │           │           │
        ┌────┴────┐ ┌────┴────┐ ┌────┴────┐
        │ NS1     │ │ NS2     │ │ NS3     │
        │10.0.1.11│ │10.0.1.12│ │10.0.1.13│
        └─────────┘ └─────────┘ └─────────┘
```

**Pratik Kurulum:**

```bash
# 1. Bridge oluştur
$ sudo ip link add br0 type bridge
$ sudo ip link set br0 up
$ sudo ip addr add 10.0.1.1/24 dev br0

# 2. Üç namespace oluştur
$ sudo ip netns add ns1
$ sudo ip netns add ns2
$ sudo ip netns add ns3

# 3. Her namespace için veth çifti oluştur ve bridge'e bağla
for i in 1 2 3; do
    echo "Configuring ns${i}..."
    
    # veth çifti oluştur (bir uç namespace'de, diğeri host'ta)
    sudo ip link add veth-ns${i} type veth peer name veth-br${i}
    
    # Namespace tarafını namespace'e ekle
    sudo ip link set veth-ns${i} netns ns${i}
    
    # Namespace içinde yapılandır
    sudo ip netns exec ns${i} ip addr add 10.0.1.1${i}/24 dev veth-ns${i}
    sudo ip netns exec ns${i} ip link set veth-ns${i} up
    sudo ip netns exec ns${i} ip link set lo up
    
    # Default gateway ekle (internet erişimi için)
    sudo ip netns exec ns${i} ip route add default via 10.0.1.1
    
    # Host tarafını bridge'e ekle
    sudo ip link set veth-br${i} master br0
    sudo ip link set veth-br${i} up
    
    echo "✓ ns${i} configured"
done

# 4. Bridge durumunu kontrol et
$ ip link show master br0
8: veth-br1@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master br0
10: veth-br2@if9: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master br0
12: veth-br3@if11: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 master br0

# 5. Connectivity test: ns1'den ns2'ye ping
$ sudo ip netns exec ns1 ping -c 3 10.0.1.12
PING 10.0.1.12 (10.0.1.12) 56(84) bytes of data.
64 bytes from 10.0.1.12: icmp_seq=1 ttl=64 time=0.052 ms
64 bytes from 10.0.1.12: icmp_seq=2 ttl=64 time=0.041 ms
64 bytes from 10.0.1.12: icmp_seq=3 ttl=64 time=0.039 ms

# 6. ns1'den ns3'e ping
$ sudo ip netns exec ns1 ping -c 2 10.0.1.13
PING 10.0.1.13 (10.0.1.13) 56(84) bytes of data.
64 bytes from 10.0.1.13: icmp_seq=1 ttl=64 time=0.048 ms
64 bytes from 10.0.1.13: icmp_seq=2 ttl=64 time=0.043 ms

# 7. Namespace'lerden bridge'e ping
$ sudo ip netns exec ns1 ping -c 1 10.0.1.1
64 bytes from 10.0.1.1: icmp_seq=1 ttl=64 time=0.031 ms
```

**İnternet Erişimi Eklemek (NAT):**

Namespace'ler bridge üzerinden birbirleriyle konuşabilir, ancak internet erişimi için NAT (Network Address Translation) gerekir:

```bash
# 1. IP forwarding'i aktifleştir
$ sudo sysctl -w net.ipv4.ip_forward=1

# 2. NAT kuralı ekle (masquerade)
# Masquerade: Source IP'yi host IP'sine çevirir
$ sudo iptables -t nat -A POSTROUTING -s 10.0.1.0/24 -j MASQUERADE

# 3. İnternet erişimini test et
$ sudo ip netns exec ns1 ping -c 2 8.8.8.8
PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
64 bytes from 8.8.8.8: icmp_seq=1 ttl=56 time=15.2 ms
64 bytes from 8.8.8.8: icmp_seq=2 ttl=56 time=14.8 ms

# 4. DNS test
$ sudo ip netns exec ns1 ping -c 1 google.com
# DNS resolve için /etc/resolv.conf namespace içinde yapılandırılmalı

# 5. resolv.conf yapılandırması
$ sudo mkdir -p /etc/netns/ns1
$ echo "nameserver 8.8.8.8" | sudo tee /etc/netns/ns1/resolv.conf

# 6. Tekrar DNS test
$ sudo ip netns exec ns1 ping -c 2 google.com
PING google.com (142.250.185.46) 56(84) bytes of data.
64 bytes from lhr25s34-in-f14.1e100.net (142.250.185.46): icmp_seq=1 ttl=56 time=16.3 ms
```

**NAT Kuralı Açıklaması:**
- `-t nat`: NAT table'ını kullan
- `-A POSTROUTING`: Routing sonrası chain'e ekle
- `-s 10.0.1.0/24`: Source IP aralığı
- `-j MASQUERADE`: Dinamik NAT (source IP'yi host IP'sine çevir)

#### Network Namespace'de Servis Çalıştırma

**Örnek: Web Server'ı Namespace'de Çalıştırma**

```bash
# 1. Web sunucusu namespace'i oluştur
$ sudo ip netns add webserver

# 2. veth çifti oluştur
$ sudo ip link add veth-web type veth peer name veth-host

# 3. Bir ucu namespace'e ata
$ sudo ip link set veth-web netns webserver

# 4. Host tarafı yapılandır
$ sudo ip addr add 10.0.2.1/24 dev veth-host
$ sudo ip link set veth-host up

# 5. Namespace tarafı yapılandır
$ sudo ip netns exec webserver ip addr add 10.0.2.2/24 dev veth-web
$ sudo ip netns exec webserver ip link set veth-web up
$ sudo ip netns exec webserver ip link set lo up

# 6. Web server başlat (Python HTTP server)
$ sudo ip netns exec webserver python3 -m http.server 80 &
[1] 12345
Serving HTTP on 0.0.0.0 port 80 (http://0.0.0.0:80/) ...

# 7. Host'tan web server'a erişim
$ curl http://10.0.2.2:80
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<title>Directory listing for /</title>
</head>
...

# 8. Port forward ile dış dünyaya açma
# Host'un 8080 portunu namespace'in 80 portuna yönlendir
$ sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.0.2.2:80
$ sudo iptables -A FORWARD -p tcp -d 10.0.2.2 --dport 80 -j ACCEPT

# 9. Dışarıdan erişim testi
$ curl http://192.168.1.100:8080  # Host IP'si
# Web server'dan yanıt alırsınız
```

**Port Forwarding Açıklaması:**

```
External Client                Host                Namespace
     │                         │                      │
     │ HTTP → :8080           │                      │
     ├────────────────────────►│                      │
     │                         │ DNAT (8080 → 80)    │
     │                         ├─────────────────────►│
     │                         │                  :80 │
     │                         │                      │
     │                         │◄─────────────────────┤
     │◄────────────────────────┤                      │
     │                         │                      │
```

#### Network Namespace İçin Monitoring ve Debug

**1. Namespace Bilgilerini Görüntüleme:**

```bash
# Tüm network namespace'leri listele
$ ip netns list

# Namespace ID'sini görüntüle
$ ip netns identify $$  # Kendi process'iniz
$ ip netns identify 1234  # Belirli bir PID

# Namespace'in ne zaman oluşturulduğunu görüntüle
$ stat /var/run/netns/webserver
```

**2. Network Interface Debug:**

```bash
# Namespace içindeki tüm interface'leri listele
$ sudo ip netns exec webserver ip link show

# Interface istatistikleri
$ sudo ip netns exec webserver ip -s link show

# Detaylı interface bilgisi
$ sudo ip netns exec webserver ethtool veth-web  # Eğer ethtool yüklüyse
```

**3. Routing Debug:**

```bash
# Routing table
$ sudo ip netns exec webserver ip route show

# Routing cache
$ sudo ip netns exec webserver ip route show cache

# Belirli bir IP'ye giden route
$ sudo ip netns exec webserver ip route get 8.8.8.8
```

**4. Connectivity Test:**

```bash
# Basic ping
$ sudo ip netns exec webserver ping -c 1 10.0.2.1

# Traceroute
$ sudo ip netns exec webserver traceroute 8.8.8.8

# Port açık mı test
$ sudo ip netns exec webserver nc -zv 10.0.2.1 80

# TCP dump (trafik yakalama)
$ sudo ip netns exec webserver tcpdump -i veth-web -n
```

**5. Firewall Debug:**

```bash
# iptables kurallarını listele
$ sudo ip netns exec webserver iptables -L -v -n

# NAT kuralları
$ sudo ip netns exec webserver iptables -t nat -L -v -n

# Connection tracking
$ sudo ip netns exec webserver conntrack -L
```

#### Network Namespace Troubleshooting

**Problem 1: "Cannot open network namespace" hatası**

```bash
# Hata
$ ip netns exec myns ip addr
Cannot open network namespace "myns": No such file or directory

# Neden: Namespace silinmiş veya hiç oluşturulmamış
# Çözüm 1: Namespace var mı kontrol et
$ ip netns list

# Çözüm 2: Yeniden oluştur
$ sudo ip netns add myns
```

**Problem 2: Namespace'ler arası ping çalışmıyor**

```bash
# Debug adımları:

# 1. Interface'ler UP mi?
$ sudo ip netns exec blue ip link show
# veth-blue interface DOWN olmamalı

# 2. IP adresleri doğru mu?
$ sudo ip netns exec blue ip addr show
$ sudo ip netns exec red ip addr show

# 3. Aynı subnet'te mi?
# 10.0.0.1/24 ve 10.0.0.2/24 aynı subnet
# 10.0.0.1/24 ve 10.0.1.1/24 farklı subnet (route gerekir)

# 4. ARP çözümlemesi çalışıyor mu?
$ sudo ip netns exec blue ip neigh show

# 5. Firewall kuralları engelliyor mu?
$ sudo ip netns exec blue iptables -L

# 6. MTU uyuşmazlığı?
$ sudo ip netns exec blue ip link show
$ sudo ip netns exec red ip link show
# Her iki tarafta MTU aynı olmalı
```

**Problem 3: İnternet erişimi çalışmıyor**

```bash
# 1. IP forwarding açık mı?
$ sysctl net.ipv4.ip_forward
net.ipv4.ip_forward = 1  # 1 olmalı

# Kapalıysa aç:
$ sudo sysctl -w net.ipv4.ip_forward=1

# 2. NAT kuralı var mı?
$ sudo iptables -t nat -L POSTROUTING -v -n
# MASQUERADE kuralı görünmeli

# 3. Default route var mı?
$ sudo ip netns exec myns ip route
default via 10.0.1.1 dev veth-ns  # Default route olmalı

# 4. DNS çözümlemesi çalışıyor mu?
$ sudo ip netns exec myns cat /etc/resolv.conf
# veya
$ cat /etc/netns/myns/resolv.conf

# 5. Ping test adım adım
# a) Gateway'e ping
$ sudo ip netns exec myns ping -c 1 10.0.1.1

# b) Host'tan dışarı ping
$ ping -c 1 8.8.8.8

# c) Namespace'ten dışarı ping
$ sudo ip netns exec myns ping -c 1 8.8.8.8
```

**Problem 4: veth pair bozuk**

```bash
# Semptom: Interface UP ama ping çalışmıyor

# 1. Peer interface'i bul
$ ip -n blue link show
7: veth-blue@if8: <BROADCAST,MULTICAST,UP,LOWER_UP>
# @if8 -> peer interface ID: 8

# 2. Peer interface namespace'ini bul
$ ip -n red link show
8: veth-red@if7: <BROADCAST,MULTICAST,UP,LOWER_UP>
# Eşleşiyor!

# 3. Her iki taraf UP mu?
$ sudo ip netns exec blue ip link set veth-blue up
$ sudo ip netns exec red ip link set veth-red up

# 4. Yeniden oluşturma gerekiyorsa
$ sudo ip netns exec blue ip link delete veth-blue
# Peer otomatik silinir
# Yeniden oluştur:
$ sudo ip link add veth-blue type veth peer name veth-red
```

#### Network Namespace Best Practices

**1. İsimlendirme Standardı:**

```bash
# ✓ İyi isimlendirme
$ sudo ip netns add app-web-production
$ sudo ip netns add app-database-staging
$ sudo ip netns add test-isolated-env-1

# ✗ Kötü isimlendirme
$ sudo ip netns add ns1
$ sudo ip netns add test
$ sudo ip netns add temp
```

**2. Cleanup Script'leri:**

```bash
#!/bin/bash
# cleanup_namespace.sh - Namespace temizleme

NAMESPACE=$1

if [ -z "$NAMESPACE" ]; then
    echo "Usage: $0 <namespace>"
    exit 1
fi

echo "Cleaning up namespace: $NAMESPACE"

# 1. Namespace içindeki process'leri öldür
sudo ip netns pids "$NAMESPACE" | while read pid; do
    echo "Killing PID: $pid"
    sudo kill -9 "$pid" 2>/dev/null
done

# 2. Namespace'i sil
sudo ip netns delete "$NAMESPACE"

echo "Cleanup complete"
```

**3. İzolasyon Seviyeleri:**

```bash
# Level 1: Minimal izolasyon (test)
$ sudo ip netns add test
$ sudo ip netns exec test bash

# Level 2: Network + PID izolasyon
$ sudo unshare --net --pid --fork --mount-proc \
    ip netns set $$  # Namespace'e isim ver

# Level 3: Tam izolasyon (container benzeri)
$ sudo unshare --net --pid --mount --uts --ipc --user --fork
```

**4. Resource Limits:**

```bash
# Namespace için bandwidth limit
$ sudo ip netns exec myns tc qdisc add dev veth-ns root tbf \
    rate 1mbit \
    burst 32kbit \
    latency 400ms

# Test
$ sudo ip netns exec myns wget http://example.com/largefile
# Download hızı ~1 Mbit/s ile sınırlı
```

**5. Security:**

```bash
# Namespace içinde firewall kuralları
$ sudo ip netns exec myns iptables -A INPUT -p tcp --dport 22 -j DROP
$ sudo ip netns exec myns iptables -A INPUT -p tcp --dport 80 -j ACCEPT
$ sudo ip netns exec myns iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
$ sudo ip netns exec myns iptables -A INPUT -j DROP
```

---

### Mount Namespace

#### Neden Mount Namespace?

Geleneksel Linux sisteminde, tüm process'ler aynı dosya sistemi mount yapısını görür. Bu ciddi sorunlar yaratır:

**Güvenlik ve İzolasyon:**
```bash
# ❌ Her process tüm dosya sistemini görebilir
/home/user1/private/
/home/user2/secrets/
/etc/shadow
/root/

# ❌ Bir process mount/umount yapınca tüm sistem etkilenir
```

**Flexibility:**
```bash
# ❌ İki uygulama farklı versiyonlarda aynı kütüphaneyi kullanamaz
App1: /lib/libssl.so.1.0
App2: /lib/libssl.so.1.1  # Conflict!

# ❌ Test ortamı host sistemini etkileyebilir
```

**Mount Namespace'in Çözümü:**

```
Host Mount Tree          Container Mount Tree
/                        /
├── bin/                 ├── bin/ (container-specific)
├── etc/                 ├── etc/ (container-specific)
├── home/                ├── app/
└── var/                 └── tmp/
```

Her container kendi dosya sistemi görünümüne sahiptir:
- ✅ Kendi root filesystem ("/")
- ✅ Bağımsız mount/umount işlemleri
- ✅ Host'u etkilemeden dosya sistemi değişiklikleri

#### Mount Namespace Özellikleri

1. **Mount point izolasyonu**
   - Her namespace kendi mount tree'sine sahiptir
   - Bir namespace'de yapılan mount, diğerlerini etkilemez

2. **Mount propagation**
   - Shared: Mount'lar otomatik olarak paylaşılır
   - Private: Mount'lar izoledir
   - Slave: Tek yönlü propagation
   - Unbindable: Mount bind edilemez

3. **Copy-on-write semantics**
   - Parent namespace'deki mount'lar child'a kopyalanır
   - Child'daki değişiklikler parent'ı etkilemez

#### Görselleştirme: Mount Namespace

```
Host System Mount Tree
/
├── bin → /usr/bin
├── etc/
│   ├── passwd
│   └── hosts
├── home/
│   ├── user1/
│   └── user2/
├── var/
└── tmp/

Container Mount Namespace
/  (overlay filesystem)
├── bin → /usr/bin (from image)
├── etc/
│   ├── passwd (container-specific)
│   ├── hosts (container-specific)
│   └── resolv.conf → /var/run/docker/resolv.conf
├── app/  (volume mount)
│   └── data/
└── tmp/ (tmpfs)

Volume Mounts:
Host: /data/myapp → Container: /app/data
Host: /var/log/app → Container: /var/log
```

#### Temel Kullanım

```bash
# 1. Mevcut mount namespace'deki mount'ları görüntüle
$ findmnt
TARGET                                SOURCE
/                                     /dev/sda1
├─/sys                                sysfs
├─/proc                               proc
├─/dev                                devtmpfs
│ └─/dev/pts                          devpts
├─/run                                tmpfs
├─/tmp                                tmpfs
└─/home                               /dev/sda2

# 2. Yeni mount namespace oluştur
$ sudo unshare --mount bash

# 3. Bu namespace'de mount yap (host'u etkilemez)
# mount -t tmpfs tmpfs /tmp

# 4. Mount'u kontrol et
# findmnt /tmp
TARGET SOURCE FSTYPE OPTIONS
/tmp   tmpfs  tmpfs  rw,relatime

# 5. Başka bir terminalde host'tan kontrol et
$ findmnt /tmp
TARGET SOURCE      FSTYPE OPTIONS
/tmp   /dev/sda1   ext4   rw,relatime
# Host'ta değişmedi!
```

**Mount Propagation:**

```bash
# 1. Shared mount (default çoğu sistemde)
$ sudo mount --make-shared /mnt/test

# 2. Private mount (izole)
$ sudo mount --make-private /mnt/test

# 3. Slave mount (tek yönlü)
$ sudo mount --make-slave /mnt/test

# 4. Unbindable
$ sudo mount --make-unbindable /mnt/test

# Kontrol et
$ cat /proc/self/mountinfo | grep /mnt/test
```

#### Pratik Örnek: Container Filesystem

Container'lar mount namespace kullanarak izole dosya sistemi oluşturur. İşte basit bir container filesystem simülasyonu:

```bash
#!/bin/bash
# container_rootfs.sh - Basit container filesystem oluştur

set -e

CONTAINER_NAME="mycontainer"
ROOTFS="/tmp/containers/$CONTAINER_NAME/rootfs"

echo "=== Container Filesystem Oluşturuluyor ==="

# 1. Rootfs dizini oluştur
mkdir -p "$ROOTFS"/{bin,etc,lib,lib64,proc,sys,dev,tmp,var,usr}

echo "✓ Dizin yapısı oluşturuldu"

# 2. Gerekli binary'leri kopyala
cp /bin/bash "$ROOTFS/bin/"
cp /bin/ls "$ROOTFS/bin/"
cp /bin/cat "$ROOTFS/bin/"
cp /bin/ps "$ROOTFS/bin/"

echo "✓ Binary'ler kopyalandı"

# 3. Shared library'leri bul ve kopyala
for binary in bash ls cat ps; do
    ldd "/bin/$binary" | grep -o '/lib[^ ]*' | while read lib; do
        mkdir -p "$ROOTFS$(dirname $lib)"
        cp -v "$lib" "$ROOTFS$lib" 2>/dev/null || true
    done
done

echo "✓ Library'ler kopyalandı"

# 4. Minimal etc dosyaları oluştur
cat > "$ROOTFS/etc/passwd" << EOF
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/:/bin/false
EOF

cat > "$ROOTFS/etc/group" << EOF
root:x:0:
nobody:x:65534:
EOF

cat > "$ROOTFS/etc/hostname" << EOF
$CONTAINER_NAME
EOF

echo "✓ Config dosyaları oluşturuldu"

# 5. Container'ı başlat (mount namespace ile)
echo ""
echo "=== Container Başlatılıyor ==="
echo "Root filesystem: $ROOTFS"
echo ""

sudo unshare --mount --pid --fork --mount-proc=$ROOTFS/proc bash -c "
    # Mount propagation'ı private yap
    mount --make-rprivate /
    
    # Rootfs'i pivot_root için hazırla
    cd '$ROOTFS'
    
    # proc, sys, dev mount et
    mount -t proc proc proc/
    mount -t sysfs sys sys/
    mount -t tmpfs tmpfs dev/
    
    # dev nodes oluştur
    mknod -m 666 dev/null c 1 3
    mknod -m 666 dev/zero c 1 5
    mknod -m 666 dev/random c 1 8
    mknod -m 666 dev/urandom c 1 9
    
    # chroot yaparak container içine gir
    chroot '$ROOTFS' /bin/bash
"

echo ""
echo "=== Container Sonlandırıldı ==="

# Cleanup
sudo umount "$ROOTFS/proc" 2>/dev/null || true
sudo umount "$ROOTFS/sys" 2>/dev/null || true
sudo umount "$ROOTFS/dev" 2>/dev/null || true
```

**Kullanım:**

```bash
$ chmod +x container_rootfs.sh
$ ./container_rootfs.sh

=== Container Filesystem Oluşturuluyor ===
✓ Dizin yapısı oluşturuldu
✓ Binary'ler kopyalandı
✓ Library'ler kopyalandı
✓ Config dosyaları oluşturuldu

=== Container Başlatılıyor ===
Root filesystem: /tmp/containers/mycontainer/rootfs

# Container içindesiniz!
bash-5.1# ls /
bin  dev  etc  lib  lib64  proc  sys  tmp  usr  var

bash-5.1# cat /etc/hostname
mycontainer

bash-5.1# ps aux
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0  12000  3000 ?        S    11:00   0:00 bash
root         5  0.0  0.0  16000  2500 ?        R+   11:00   0:00 ps aux

bash-5.1# exit
```

#### Overlay Filesystem (Modern Container Approach)

Modern container'lar (Docker, Podman) overlay filesystem kullanır. Bu, birden fazla layer'ı birleştirerek tek bir filesystem görünümü oluşturur.

**Overlay Konsepti:**

```
┌────────────────────────────────────┐
│         Merged View                │  ← Container görüşü
│  /bin, /etc, /app, /var           │
└─────────────┬──────────────────────┘
              │
    ┌─────────┴─────────┐
    │                   │
┌───▼──────────┐   ┌────▼────────┐
│ Upper Layer  │   │ Lower Layer │
│ (Writable)   │   │ (Read-only) │
│              │   │             │
│ /app/data/   │   │ /bin/       │
│ /etc/config  │   │ /etc/       │
│ /var/log/    │   │ /lib/       │
└──────────────┘   └─────────────┘
    Container          Base Image
    specific            (shared)
```

**Overlay Filesystem Kurulumu:**

```bash
# 1. Dizin yapısını oluştur
$ mkdir -p /tmp/overlay/{lower,upper,work,merged}

# 2. Lower layer (read-only base)
$ mkdir -p /tmp/overlay/lower/{bin,etc}
$ echo "Base image file" > /tmp/overlay/lower/etc/base.conf
$ echo "#!/bin/bash" > /tmp/overlay/lower/bin/app
$ echo 'echo "Base application"' >> /tmp/overlay/lower/bin/app
$ chmod +x /tmp/overlay/lower/bin/app

# 3. Upper layer (writable layer)
$ echo "Container specific config" > /tmp/overlay/upper/container.conf

# 4. Overlay mount
$ sudo mount -t overlay overlay \
    -o lowerdir=/tmp/overlay/lower,\
upperdir=/tmp/overlay/upper,\
workdir=/tmp/overlay/work \
    /tmp/overlay/merged

# 5. Merged view'i kontrol et
$ ls /tmp/overlay/merged/
bin  etc  container.conf

$ cat /tmp/overlay/merged/etc/base.conf
Base image file

$ cat /tmp/overlay/merged/container.conf
Container specific config

# 6. Upper layer'a yazma
$ echo "New file" > /tmp/overlay/merged/newfile.txt

# 7. Lower layer değişmemiş
$ ls /tmp/overlay/lower/
bin  etc

# 8. Upper layer'da yeni dosya var
$ ls /tmp/overlay/upper/
container.conf  newfile.txt

# 9. Temizlik
$ sudo umount /tmp/overlay/merged
```

**Overlay Avantajları:**

1. **Disk space efficiency**: Base image'lar paylaşılır
2. **Fast container startup**: Sadece writable layer oluşturulur
3. **Easy cleanup**: Container silince sadece upper layer silinir

#### Bind Mount

Bind mount, bir dizini başka bir yere "mount" eder. Container'lar için volume mounting'de kullanılır.

```bash
# 1. Kaynak ve hedef dizinler
$ mkdir -p /tmp/source /tmp/target

# 2. Source'a dosya oluştur
$ echo "Source file" > /tmp/source/file.txt

# 3. Bind mount
$ sudo mount --bind /tmp/source /tmp/target

# 4. Target'tan okuma
$ cat /tmp/target/file.txt
Source file

# 5. Target'a yazma (source'a da yazılır)
$ echo "Modified in target" > /tmp/target/file.txt
$ cat /tmp/source/file.txt
Modified in target

# 6. Read-only bind mount
$ sudo mount --bind -o ro /tmp/source /tmp/target
$ echo "test" > /tmp/target/file.txt
bash: /tmp/target/file.txt: Read-only file system

# 7. Cleanup
$ sudo umount /tmp/target
```

**Container Volume Simülasyonu:**

```bash
#!/bin/bash
# container_with_volume.sh

HOST_DATA="/home/user/myapp/data"
CONTAINER_ROOT="/tmp/container/root"
CONTAINER_VOLUME="/tmp/container/root/app/data"

# Host data dizini oluştur
mkdir -p "$HOST_DATA"
echo "Persistent data" > "$HOST_DATA/important.txt"

# Container root oluştur
mkdir -p "$CONTAINER_VOLUME"

# Bind mount
sudo mount --bind "$HOST_DATA" "$CONTAINER_VOLUME"

# Container namespace'de çalıştır
sudo unshare --mount --pid --fork bash -c "
    mount --make-rprivate /
    chroot '$CONTAINER_ROOT' bash
"

# Container içinde: /app/data host'taki /home/user/myapp/data'yı gösterir
# Container silinse bile data persist eder
```

#### Mount Namespace Propagation

Mount propagation, mount event'lerinin namespace'ler arası yayılmasını kontrol eder.

**Propagation Tipleri:**

| Tip | Açıklama | Kullanım |
|-----|----------|----------|
| shared | Mount'lar her iki yöne de yayılır | Default çoğu sistemde |
| private | Mount'lar izole | Container mount namespace |
| slave | Tek yönlü (master → slave) | Container'ın host mount'ları görmesi |
| unbindable | Bind mount yapılamaz | Güvenlik |

**Örnek:**

```bash
# 1. İki namespace oluştur
$ sudo unshare --mount bash  # Parent
# unshare --mount bash        # Child

# 2. Parent'ta shared mount
# mkdir /mnt/shared
# mount --make-shared tmpfs /mnt/shared -t tmpfs

# 3. Child'a propagate
# Child namespace'de:
# mount --make-slave /mnt/shared
# ls /mnt/shared  # Parent'taki dosyalar görünür

# 4. Parent'ta dosya oluştur
# echo "test" > /mnt/shared/test.txt

# 5. Child'dan kontrol et
# cat /mnt/shared/test.txt
test  # Propagate edildi!
```

#### Mount Namespace Troubleshooting

**Problem 1: "Operation not permitted" mount hatası**

```bash
# Hata
$ mount -t tmpfs tmpfs /tmp
mount: /tmp: permission denied.

# Neden: Mount işlemi root gerektiriyor veya
# mount namespace izolasyonu bozuk

# Çözüm 1: sudo kullan
$ sudo unshare --mount bash
# mount -t tmpfs tmpfs /tmp

# Çözüm 2: User namespace ile
$ unshare --user --map-root-user --mount bash
$ mount -t tmpfs tmpfs /tmp
```

**Problem 2: Bind mount çalışmıyor**

```bash
# Hata
$ sudo mount --bind /source /target
mount: /target: special device /source does not exist.

# Neden: Source dizin yok veya erişilemiyor

# Debug:
$ ls -ld /source
ls: cannot access '/source': No such file or directory

# Çözüm: Source dizini oluştur
$ mkdir -p /source
$ sudo mount --bind /source /target
```

**Problem 3: Overlay mount hatası**

```bash
# Hata
$ sudo mount -t overlay overlay \
    -o lowerdir=/lower,upperdir=/upper,workdir=/work \
    /merged
mount: /merged: wrong fs type, bad option, bad superblock...

# Neden: Overlay modülü yüklü değil veya
# dizinler aynı filesystem'de değil

# Çözüm 1: Modülü yükle
$ sudo modprobe overlay

# Çözüm 2: Dizinleri kontrol et
$ df -h /lower /upper /work
# Hepsi aynı filesystem'de olmalı
```

**Problem 4: Mount'u umount edememe**

```bash
# Hata
$ sudo umount /mnt/test
umount: /mnt/test: target is busy.

# Neden: Mount kullanımda (process, pwd, vb.)

# Debug: Hangi process kullanıyor?
$ sudo lsof +f -- /mnt/test
$ sudo fuser -mv /mnt/test

# Çözüm 1: Process'leri öldür
$ sudo fuser -kmv /mnt/test

# Çözüm 2: Lazy umount
$ sudo umount -l /mnt/test  # Kullanım bitince umount olur

# Çözüm 3: Force umount (son çare!)
$ sudo umount -f /mnt/test
```

#### Mount Namespace Best Practices

**1. Private propagation kullan:**

```bash
# Container başlatırken
$ sudo unshare --mount bash -c '
    mount --make-rprivate /
    # Şimdi mount'larınız izole
'
```

**2. Mount cleanup:**

```bash
#!/bin/bash
# cleanup_mounts.sh

MOUNT_POINT="$1"

echo "Cleaning up mounts under $MOUNT_POINT"

# Recursive umount
while mountpoint -q "$MOUNT_POINT"; do
    sudo umount -l "$MOUNT_POINT" 2>/dev/null || true
    sleep 0.1
done

echo "Cleanup complete"
```

**3. Read-only mounts güvenlik için:**

```bash
# Güvenlik-kritik dizinler için read-only
$ sudo mount --bind -o ro /etc /container/etc
$ sudo mount --bind -o ro /usr /container/usr
```

**4. Tmpfs kullanımı:**

```bash
# /tmp ve /var için tmpfs (RAM disk)
$ sudo mount -t tmpfs -o size=100M tmpfs /container/tmp
$ sudo mount -t tmpfs -o size=50M tmpfs /container/var/tmp
```

---

### UTS Namespace

#### Neden UTS Namespace?

UTS (UNIX Time-Sharing System) namespace, sistem hostname ve domain name'ini izole eder. Basit görünse de, çok önemli kullanım alanları vardır.

**Problemler:**

```bash
# ❌ Host sistem
$ hostname
production-server-01

# Tüm container'lar aynı hostname'i görür
# Container 1, 2, 3: production-server-01
# Loglar karışır, hangi container'dan geldiği belirsiz
```

**UTS Namespace Çözümü:**

```
Host: production-server-01

Container 1: web-app-container
Container 2: db-container
Container 3: cache-container

Her container kendi hostname'ine sahip!
```

#### UTS Namespace Özellikleri

1. **Hostname izolasyonu**: Her namespace kendi hostname'ine sahip
2. **Domain name izolasyonu**: NIS domain name izolasyonu
3. **Lightweight**: Çok az kaynak kullanır
4. **Process identification**: Loglar ve monitoring için kritik

#### Temel Kullanım

```bash
# 1. Host hostname
$ hostname
my-host-server

$ domainname
(none)

# 2. Yeni UTS namespace oluştur
$ sudo unshare --uts bash

# 3. Namespace içinde hostname değiştir
# hostname my-container

# 4. Kontrol et
# hostname
my-container

# 5. Domain name değiştir
# domainname my-domain.local

# domainname
my-domain.local

# 6. Host'tan kontrol et (başka terminalde)
$ hostname
my-host-server
# Değişmedi!
```

#### Pratik Örnek: Multi-Container Setup

```bash
#!/bin/bash
# multi_container_uts.sh - Her container farklı hostname

# Container 1: Web Server
sudo unshare --uts --net --pid --fork --mount-proc bash -c '
    hostname web-server
    echo "$(hostname) started" >> /tmp/container.log
    
    # Web server başlat
    python3 -m http.server 8080 &
    
    # Log monitoring
    tail -f /tmp/container.log
' &

# Container 2: Database
sudo unshare --uts --net --pid --fork --mount-proc bash -c '
    hostname database-server
    echo "$(hostname) started" >> /tmp/container.log
    
    # Database simülasyonu
    while true; do
        echo "[$(date)] $(hostname): Processing queries..." >> /tmp/container.log
        sleep 5
    done
' &

# Container 3: Cache
sudo unshare --uts --net --pid --fork --mount-proc bash -c '
    hostname cache-server
    echo "$(hostname) started" >> /tmp/container.log
    
    # Cache simülasyonu
    while true; do
        echo "[$(date)] $(hostname): Cache hit rate: 95%" >> /tmp/container.log
        sleep 10
    done
' &

wait
```

**Log çıktısı:**

```bash
$ tail -f /tmp/container.log
web-server started
database-server started
cache-server started
[2025-10-24 12:00:00] database-server: Processing queries...
[2025-10-24 12:00:05] cache-server: Cache hit rate: 95%
[2025-10-24 12:00:05] database-server: Processing queries...
```

Her container'ın logları hostname ile ayırt ediliyor!

#### Application Hostname Awareness

Bazı uygulamalar hostname'e göre davranış değiştirir:

```python
# app.py - Hostname-aware application
import socket
import os

hostname = socket.gethostname()

# Hostname'e göre configuration
if hostname.startswith('prod-'):
    DB_HOST = 'production-db.example.com'
    LOG_LEVEL = 'WARNING'
elif hostname.startswith('staging-'):
    DB_HOST = 'staging-db.example.com'
    LOG_LEVEL = 'INFO'
elif hostname.startswith('dev-'):
    DB_HOST = 'localhost'
    LOG_LEVEL = 'DEBUG'
else:
    DB_HOST = 'localhost'
    LOG_LEVEL = 'INFO'

print(f"Running on: {hostname}")
print(f"Database: {DB_HOST}")
print(f"Log Level: {LOG_LEVEL}")
```

**Container'da çalıştırma:**

```bash
# Production container
$ sudo unshare --uts bash -c '
    hostname prod-web-01
    python3 app.py
'
Running on: prod-web-01
Database: production-db.example.com
Log Level: WARNING

# Development container
$ sudo unshare --uts bash -c '
    hostname dev-web-01
    python3 app.py
'
Running on: dev-web-01
Database: localhost
Log Level: DEBUG
```

#### UTS Namespace Best Practices

**1. Anlamlı hostname'ler:**

```bash
# ✓ İyi
$ hostname web-app-prod-replica-1
$ hostname db-primary-east-1
$ hostname cache-redis-west-2

# ✗ Kötü
$ hostname container1
$ hostname temp
$ hostname test
```

**2. Hostname standardı:**

```
{service}-{environment}-{role}-{instance}

Örnek:
- api-prod-master-01
- web-staging-worker-03
- db-dev-primary-01
```

**3. /etc/hosts güncellemesi:**

```bash
# Container içinde
$ cat > /etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   $(hostname)
::1         localhost ip6-localhost ip6-loopback
EOF
```

---

### IPC Namespace

#### Neden IPC Namespace?

IPC (Inter-Process Communication), process'ler arası iletişim mekanizmalarını izole eder:

- System V IPC: Message queues, Semaphores, Shared memory
- POSIX Message queues

**Problem:**

```bash
# ❌ Global IPC kaynakları
$ ipcs
------ Message Queues --------
key        msqid      owner      perms      used-bytes   messages    
0x00000001 0          user1      666        4096         10          

# Herkes bu queue'yu görebilir ve kullanabilir!
# Güvenlik ve izolasyon problemi
```

**IPC Namespace Çözümü:**

Her container kendi IPC kaynaklarına sahiptir. Bir container'daki message queue, diğerleri tarafından görülemez.

#### Temel Kullanım

```bash
# 1. Host'ta IPC kaynakları
$ ipcs -q  # Message queues
$ ipcs -s  # Semaphores
$ ipcs -m  # Shared memory

# 2. Yeni IPC namespace
$ sudo unshare --ipc bash

# 3. Namespace içinde IPC kaynakları (boş)
# ipcs
------ Message Queues --------
# (boş)

------ Shared Memory Segments --------
# (boş)

------ Semaphore Arrays --------
# (boş)
```

#### Pratik Örnek: Shared Memory

```c
// shm_writer.c - Shared memory writer
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ipc.h>
#include <sys/shm.h>
#include <unistd.h>

#define SHM_KEY 1234
#define SHM_SIZE 1024

int main() {
    // Shared memory oluştur
    int shmid = shmget(SHM_KEY, SHM_SIZE, IPC_CREAT | 0666);
    if (shmid < 0) {
        perror("shmget");
        exit(1);
    }
    
    // Attach et
    char *data = shmat(shmid, NULL, 0);
    if (data == (char *) -1) {
        perror("shmat");
        exit(1);
    }
    
    // Veri yaz
    sprintf(data, "Hello from PID %d - Namespace: %s", 
            getpid(), getenv("NAMESPACE") ? getenv("NAMESPACE") : "host");
    
    printf("Data written to shared memory\n");
    printf("Content: %s\n", data);
    
    sleep(30);  // 30 saniye bekle
    
    // Detach ve cleanup
    shmdt(data);
    shmctl(shmid, IPC_RMID, NULL);
    
    return 0;
}
```

```c
// shm_reader.c - Shared memory reader
#include <stdio.h>
#include <stdlib.h>
#include <sys/ipc.h>
#include <sys/shm.h>

#define SHM_KEY 1234

int main() {
    // Mevcut shared memory'ye bağlan
    int shmid = shmget(SHM_KEY, 0, 0);
    if (shmid < 0) {
        perror("shmget - shared memory not found");
        printf("This is expected if running in different IPC namespace!\n");
        exit(1);
    }
    
    // Attach et
    char *data = shmat(shmid, NULL, SHM_RDONLY);
    if (data == (char *) -1) {
        perror("shmat");
        exit(1);
    }
    
    // Veriyi oku
    printf("Data read from shared memory:\n");
    printf("Content: %s\n", data);
    
    // Detach
    shmdt(data);
    
    return 0;
}
```

**Test:**

```bash
# Derle
$ gcc -o shm_writer shm_writer.c
$ gcc -o shm_reader shm_reader.c

# Test 1: Aynı namespace (çalışır)
$ ./shm_writer &
Data written to shared memory
Content: Hello from PID 12345 - Namespace: host

$ ./shm_reader
Data read from shared memory:
Content: Hello from PID 12345 - Namespace: host

# Test 2: Farklı IPC namespace (çalışmaz)
$ sudo unshare --ipc bash -c 'NAMESPACE=container1 ./shm_writer' &
Data written to shared memory
Content: Hello from PID 12346 - Namespace: container1

# Farklı namespace'den okuma denemesi
$ sudo unshare --ipc bash -c './shm_reader'
shmget - shared memory not found: No such file or directory
This is expected if running in different IPC namespace!
```

#### IPC Namespace Best Practices

1. **IPC kaynakları temizleme**:
```bash
# Container kapanmadan önce IPC cleanup
$ ipcrm -q <msqid>
$ ipcrm -m <shmid>
$ ipcrm -s <semid>
```

2. **IPC limitleri**:
```bash
# Kernel limitleri kontrol et
$ cat /proc/sys/kernel/msgmax    # Max message size
$ cat /proc/sys/kernel/msgmnb    # Max queue size
$ cat /proc/sys/kernel/shmmni    # Max shared memory segments
```

---

### User Namespace

#### Neden User Namespace?

User namespace, UID (User ID) ve GID (Group ID) mapping sağlar. Bu, **rootless container'ların** temelini oluşturur.

**Problem:**

```bash
# ❌ Container içinde root (UID 0)
# Container içindeki root = Host'taki root
# Güvenlik riski: Container escape edilirse sistem tamamen ele geçirilir
```

**User Namespace Çözümü:**

```
Host System              Container
UID 0 (root)            
UID 1000 (user)    →    UID 0 (root in container)
UID 1001           →    UID 1
UID 1002           →    UID 2
```

Container içinde root olsanız bile, host'ta normal user olursunuz!

#### User Namespace Özellikleri

1. **UID/GID mapping**: User ID'leri map edilir
2. **Capability isolation**: Root yetenekleri namespace ile sınırlı
3. **Rootless containers**: Root olmadan container çalıştırma
4. **Nested namespaces**: User namespace içinde user namespace

#### Temel Kullanım

```bash
# 1. Normal user olarak (root değilken)
$ id
uid=1000(user) gid=1000(user) groups=1000(user)

# 2. User namespace oluştur ve root olarak map et
$ unshare --user --map-root-user bash

# 3. Namespace içinde root!
$ id
uid=0(root) gid=0(root) groups=0(root)

# 4. Ancak host'ta hala normal user
# Başka terminalde:
$ ps aux | grep bash
user   12345  0.0  0.0  12000  3000 pts/0  S  12:00  0:00 bash
# UID hala 1000!
```

#### UID/GID Mapping

```bash
# Manuel mapping
$ unshare --user bash

# Mapping tanımla (namespace içinde)
# echo '0 1000 1' > /proc/$$/uid_map
# echo '0 1000 1' > /proc/$$/gid_map

# uid_map format: <container-uid> <host-uid> <range>
# Örnek: Container UID 0 → Host UID 1000 (1 kullanıcı)
```

**Kapsamlı Mapping Örneği:**

```bash
#!/bin/bash
# user_namespace_mapping.sh

# User namespace oluştur
unshare --user bash << 'EOF'
    # Kendi PID'miz
    MY_PID=$$
    
    # UID mapping: Container 0-999 → Host 1000-1999
    echo "0 1000 1000" > /proc/$MY_PID/uid_map
    
    # GID mapping benzer şekilde
    echo "0 1000 1000" > /proc/$MY_PID/gid_map
    
    # Şimdi container içinde UID 0-999 kullanabiliriz
    # Host'ta bunlar 1000-1999 olarak görünür
    
    echo "Container içinde:"
    id
    
    echo -e "\nDosya oluştur:"
    touch /tmp/test_file
    ls -l /tmp/test_file
EOF

# Host'tan kontrol et
echo -e "\nHost'tan görünüm:"
ls -l /tmp/test_file
```

#### Rootless Containers

Rootless container'lar, root ayrıcalıkları olmadan çalışan container'lardır. User namespace bu özelliği mümkün kılar.

**Rootless Podman Örneği:**

```bash
# Root olmadan container çalıştır
$ podman run --rm -it alpine sh

# Container içinde root gibi görünürsünüz
/ # id
uid=0(root) gid=0(root) groups=0(root)

# Ancak host'ta:
$ ps aux | grep alpine
user   12345  0.1  0.0  12000  3000 ?  Ss  12:00  0:00 alpine

# Process sahibi normal user!
```

**Rootless Container'ın Güvenlik Avantajları:**

1. **Container escape riski azalır**: Container içindeki root, host'ta normal user
2. **Kernel attack surface azalır**: Root capability'leri yok
3. **Multi-tenant güvenlik**: Her kullanıcı kendi container'larını çalıştırır

#### User Namespace Limitations

```bash
# Bazı işlemler hala gerektiriyor root:

# ❌ Privileged port (<1024)
$ podman run -p 80:80 nginx
Error: cannot listen on privileged port 80

# ✅ Çözüm: Unprivileged port
$ podman run -p 8080:80 nginx

# ❌ Device access
$ podman run --device /dev/sda alpine
Error: cannot access device

# ✅ Çözüm: Device'a önceden izin verin veya
# fuse filesystem kullanın
```

#### Troubleshooting

**Problem: "write /proc/self/uid_map: Operation not permitted"**

```bash
# Neden: /etc/subuid ve /etc/subgid eksik veya hatalı

# Çözüm: subuid/subgid yapılandır
$ sudo usermod --add-subuids 100000-165535 $USER
$ sudo usermod --add-subgids 100000-165535 $USER

# Kontrol et
$ cat /etc/subuid
user:100000:65536

$ cat /etc/subgid
user:100000:65536
```

---

### Cgroup Namespace

#### Neden Cgroup Namespace?

Cgroup (Control Group) namespace, container'ların cgroup hiyerarşisini izole eder. Container içinden cgroup yapısı "/sys/fs/cgroup/" olarak görünür.

**Özellikler:**

1. Cgroup root directory izolasyonu
2. Container içinden cgroup görünümü
3. Resource limit gizleme (security)

#### Temel Kullanım

```bash
# Host'ta cgroup tree
$ cat /proc/self/cgroup
0::/user.slice/user-1000.slice/session-1.scope

# Cgroup namespace ile
$ unshare --cgroup bash
$ cat /proc/self/cgroup
0::/

# Container kendi cgroup root'unda gibi görünür
```

---

### Time Namespace

#### Neden Time Namespace?

Time namespace, sistem saatini (CLOCK_MONOTONIC, CLOCK_BOOTTIME) izole eder. Test ve simülasyon senaryoları için kullanılır.

**Kullanım Alanları:**

1. **Zaman yolculuğu testleri**: Uygulamanızı gelecekte/geçmişte test edin
2. **Uptime testleri**: Sistem uptime simülasyonu
3. **Time-based logic testleri**: Cron job'lar, scheduler'lar

#### Temel Kullanım

```bash
# Host system time
$ date
Fri Oct 24 12:00:00 UTC 2025

# Time namespace oluştur ve offset ver
$ sudo unshare --time --fork bash

# Namespace içinde offset ayarla (nanosaniye cinsinden)
# echo "monotonic 3600 0" > /proc/$$/timens_offsets
# echo "boottime 7200 0" > /proc/$$/timens_offsets
# 3600 saniye = 1 saat ileri
# 7200 saniye = 2 saat ileri

# Kontrol et
# date
Fri Oct 24 13:00:00 UTC 2025  # 1 saat ileri!
```

**Pratik Örnek: Cron Job Testi**

```bash
#!/bin/bash
# test_cron_future.sh - Cron job'u gelecekte test et

# Bugünkü script
cat > /tmp/daily_job.sh << 'EOF'
#!/bin/bash
echo "[$(date)] Daily job executed" >> /tmp/job.log
EOF
chmod +x /tmp/daily_job.sh

# Time namespace ile 1 gün ileri git
sudo unshare --time --fork bash -c '
    # 1 gün = 86400 saniye
    echo "monotonic 86400 0" > /proc/$$/timens_offsets
    
    echo "Current time in namespace:"
    date
    
    echo "Running daily job..."
    /tmp/daily_job.sh
'

# Log kontrol et
cat /tmp/job.log
[Sat Oct 25 12:00:00 UTC 2025] Daily job executed
# Yarının tarihi!
```

#### Time Namespace Limitations

- Sadece CLOCK_MONOTONIC ve CLOCK_BOOTTIME etkilenir
- CLOCK_REALTIME (wall clock) etkilenmez
- NTP synchronization çalışmaya devam eder

---

## Namespace'leri Birlikte Kullanma

### Tam İzolasyonlu Container

Tüm namespace'leri birlikte kullanarak tam izolasyonlu bir container oluşturabiliriz:

```bash
#!/bin/bash
# full_container.sh - Tam izolasyonlu container

CONTAINER_NAME="full-isolated"
ROOTFS="/tmp/containers/$CONTAINER_NAME"

echo "=== Tam İzolasyonlu Container ==="

# Rootfs oluştur (basit)
mkdir -p "$ROOTFS"/{bin,proc,sys,dev,etc,tmp}

# Namespace'leri oluştur ve container başlat
sudo unshare \
    --pid \           # PID namespace
    --net \           # Network namespace
    --mount \         # Mount namespace
    --uts \           # UTS namespace
    --ipc \           # IPC namespace
    --user \          # User namespace
    --cgroup \        # Cgroup namespace
    --map-root-user \ # Root mapping
    --fork \          # Fork child process
    bash -c "
        # UTS: Hostname ayarla
        hostname $CONTAINER_NAME
        
        # Mount: proc, sys mount et
        mount -t proc proc $ROOTFS/proc
        mount -t sysfs sys $ROOTFS/sys
        
        # Network: Loopback aktifleştir
        ip link set lo up
        
        echo 'Container başlatıldı:'
        echo '  Hostname: \$(hostname)'
        echo '  PID: \$\$'
        echo '  UID: \$(id -u)'
        echo '  Network interfaces: \$(ip link show | grep -c '^[0-9]')'
        echo ''
        
        # Shell aç
        bash
    "

echo "=== Container Sonlandırıldı ==="
```

### Container Comparison

| Özellik | chroot | systemd-nspawn | Docker/Podman |
|---------|--------|----------------|---------------|
| PID NS | ✗ | ✓ | ✓ |
| NET NS | ✗ | ✓ | ✓ |
| MNT NS | ~ | ✓ | ✓ |
| UTS NS | ✗ | ✓ | ✓ |
| IPC NS | ✗ | ✓ | ✓ |
| USER NS | ✗ | ✓ | ✓ |
| CGROUP NS | ✗ | ✓ | ✓ |
| TIME NS | ✗ | ✗ | ✗ |
| Resource Limits | ✗ | ✓ | ✓ |
| Networking | ✗ | ✓ | ✓ |
| Image Management | ✗ | ~ | ✓ |
| Kullanım Kolaylığı | ★☆☆ | ★★☆ | ★★★ |

---

## Podman Secrets

### Secrets Nedir?

Podman secrets, hassas bilgilerin (passwords, API keys, certificates) güvenli şekilde saklanması ve container'lara iletilmesi için kullanılan bir mekanizmadır.

#### Neden Secrets Kullanmalıyız?

**❌ Environment Variable ile (Kötü Pratik):**

```bash
# Güvensiz: Environment variable
$ podman run -e DB_PASSWORD=supersecret123 myapp

# Sorunlar:
# 1. Process listesinde görünür
$ ps aux | grep podman
# supersecret123 görünür!

# 2. Container inspect'te görünür
$ podman inspect myapp
"Env": ["DB_PASSWORD=supersecret123"]

# 3. Log dosyalarına yazılabilir
# 4. Child process'lere otomatik geçer
# 5. Hata mesajlarında leak olabilir
```

**✅ Secret ile (İyi Pratik):**

```bash
# Güvenli: Secret kullanımı
$ echo "supersecret123" | podman secret create db_password -
$ podman run --secret db_password myapp

# Avantajlar:
# 1. Process listesinde görünmez
# 2. Inspect'te detaylı bilgi yok
# 3. Sadece container içinde /run/secrets/'de erişilebilir
# 4. Container dursa bile secret persist eder
# 5. Şifrelenerek saklanır (varsa)
```

#### Secret Storage

Podman secrets varsayılan olarak şu lokasyonda saklanır:

```bash
# Root kullanıcı
/var/lib/containers/storage/volumes/

# Rootless kullanıcı
~/.local/share/containers/storage/secrets/

# Secret dosyaları şifrelenir (eğer sistem destekliyorsa)
```

### Secret Oluşturma ve Yönetme

#### Temel Secret İşlemleri

```bash
# 1. Secret oluşturma - stdin'den
$ echo -n "my-secret-password" | podman secret create db_password -

# 2. Secret oluşturma - dosyadan
$ podman secret create api_key /path/to/api_key.txt

# 3. Secret oluşturma - komut çıktısından
$ openssl rand -base64 32 | podman secret create jwt_secret -

# 4. Secret'ları listeleme
$ podman secret ls
ID                        NAME              DRIVER      CREATED        UPDATED
a1b2c3d4e5f6789012345678  db_password       file        2 minutes ago  2 minutes ago
b2c3d4e5f678901234567890  api_key           file        1 minute ago   1 minute ago

# 5. Secret detaylarını görüntüleme
$ podman secret inspect db_password
[
    {
        "ID": "a1b2c3d4e5f6789012345678",
        "CreatedAt": "2025-10-24T12:00:00Z",
        "UpdatedAt": "2025-10-24T12:00:00Z",
        "Spec": {
            "Name": "db_password",
            "Driver": {
                "Name": "file"
            }
        }
    }
]

# 6. Secret silme
$ podman secret rm db_password

# 7. Tüm secret'ları silme
$ podman secret ls -q | xargs podman secret rm
```

#### Secret Naming Best Practices

```bash
# ✓ İyi İsimlendirme
podman secret create prod_db_password -
podman secret create prod_api_key_openai -
podman secret create staging_jwt_secret -
podman secret create cert_tls_example_com -

# Pattern: <environment>_<service>_<type>_<detail>

# ✗ Kötü İsimlendirme
podman secret create password -        # Belirsiz
podman secret create secret1 -         # Anlamsız
podman secret create temp -            # Geçici mi, kalıcı mı?
podman secret create key -             # Hangi key?
```

### Container'da Secret Kullanımı

#### Basit Kullanım

```bash
# 1. Secret oluştur
$ echo -n "mypassword123" | podman secret create db_pass -

# 2. Container başlat ve secret'ı mount et
$ podman run -d \
    --name myapp \
    --secret db_pass \
    alpine sleep 3600

# 3. Container içinde secret'a erişim
$ podman exec myapp cat /run/secrets/db_pass
mypassword123

# 4. Secret dosya izinleri
$ podman exec myapp ls -la /run/secrets/
total 0
drwxr-xr-x 2 root root  60 Oct 24 12:00 .
drwxr-xr-x 3 root root  60 Oct 24 12:00 ..
-r--r--r-- 1 root root  13 Oct 24 12:00 db_pass
# Read-only!
```

#### Custom Target Path

```bash
# Secret'ı farklı bir yola mount et
$ podman run -d \
    --name myapp \
    --secret source=db_pass,target=/app/config/db.password \
    alpine sleep 3600

$ podman exec myapp cat /app/config/db.password
mypassword123
```

#### Custom UID/GID ve Mode

```bash
# Secret'ın sahibi ve izinlerini ayarla
$ podman run -d \
    --name myapp \
    --secret source=db_pass,uid=1000,gid=1000,mode=0400 \
    alpine sleep 3600

$ podman exec myapp ls -la /run/secrets/db_pass
-r-------- 1 1000 1000 13 Oct 24 12:00 /run/secrets/db_pass
# Sadece UID 1000 okuyabilir
```

#### Multiple Secrets

```bash
# Birden fazla secret
$ echo -n "dbpass" | podman secret create db_password -
$ echo -n "apikey123" | podman secret create api_key -
$ echo -n "jwtsecret" | podman secret create jwt_secret -

$ podman run -d \
    --name webapp \
    --secret db_password \
    --secret api_key \
    --secret jwt_secret \
    mywebapp:latest

# Container içinde
$ podman exec webapp ls /run/secrets/
api_key  db_password  jwt_secret
```

### Gerçek Dünya Senaryoları

#### Senaryo 1: Web Application Stack

**Mimari:**

```
┌─────────────────┐
│   Web Frontend  │
│   (nginx)       │
└────────┬────────┘
         │
┌────────▼────────┐     ┌──────────────┐
│   API Backend   │────►│  Database    │
│   (Node.js)     │     │  (PostgreSQL)│
└─────────────────┘     └──────────────┘
         │
         ▼
┌─────────────────┐
│   Cache         │
│   (Redis)       │
└─────────────────┘
```

**Secret Yapılandırması:**

```bash
#!/bin/bash
# setup_web_stack_secrets.sh

echo "=== Web Stack Secrets Kurulumu ==="

# 1. Database secrets
echo "Generating database password..."
DB_PASSWORD=$(openssl rand -base64 32)
echo -n "$DB_PASSWORD" | podman secret create db_password -

echo -n "webapp_user" | podman secret create db_username -

# 2. Redis secret
echo "Generating Redis password..."
REDIS_PASSWORD=$(openssl rand -base64 24)
echo -n "$REDIS_PASSWORD" | podman secret create redis_password -

# 3. JWT secret (API authentication)
echo "Generating JWT secret..."
JWT_SECRET=$(openssl rand -base64 64)
echo -n "$JWT_SECRET" | podman secret create jwt_secret -

# 4. API keys (external services)
echo -n "sk-proj-abc123..." | podman secret create api_key_openai -
echo -n "SG.xyz789..." | podman secret create api_key_sendgrid -

# 5. TLS certificates
podman secret create tls_cert /path/to/server.crt
podman secret create tls_key /path/to/server.key

echo "✓ Secrets created successfully"
podman secret ls
```

**Container Başlatma:**

```bash
# 1. PostgreSQL Database
$ podman run -d \
    --name postgres \
    --secret source=db_password,target=/run/secrets/postgres_password \
    -e POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
    -e POSTGRES_USER=webapp_user \
    -e POSTGRES_DB=webapp \
    -v postgres_data:/var/lib/postgresql/data \
    postgres:15

# 2. Redis Cache
$ podman run -d \
    --name redis \
    --secret source=redis_password,target=/run/secrets/redis_password \
    redis:7 \
    redis-server --requirepass $(podman exec redis cat /run/secrets/redis_password)

# 3. API Backend
$ podman run -d \
    --name api \
    --secret db_password \
    --secret redis_password \
    --secret jwt_secret \
    --secret api_key_openai \
    --secret api_key_sendgrid \
    -e DB_HOST=postgres \
    -e DB_USER=webapp_user \
    -e DB_PASSWORD_FILE=/run/secrets/db_password \
    -e REDIS_HOST=redis \
    -e REDIS_PASSWORD_FILE=/run/secrets/redis_password \
    -e JWT_SECRET_FILE=/run/secrets/jwt_secret \
    -p 3000:3000 \
    myapi:latest

# 4. Nginx Frontend
$ podman run -d \
    --name nginx \
    --secret source=tls_cert,target=/etc/nginx/ssl/server.crt \
    --secret source=tls_key,target=/etc/nginx/ssl/server.key,mode=0400 \
    -p 443:443 \
    -p 80:80 \
    mynginx:latest
```

**Application Code (Node.js):**

```javascript
// app.js - Secret'ları dosyadan okuma
const fs = require('fs');
const path = require('path');

// Secret okuma helper
function readSecret(name) {
    const secretPath = path.join('/run/secrets', name);
    try {
        return fs.readFileSync(secretPath, 'utf8').trim();
    } catch (error) {
        console.error(`Error reading secret ${name}:`, error);
        process.exit(1);
    }
}

// Database configuration
const dbConfig = {
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'webapp_user',
    password: readSecret('db_password'),
    database: 'webapp'
};

// Redis configuration
const redisConfig = {
    host: process.env.REDIS_HOST || 'localhost',
    password: readSecret('redis_password')
};

// JWT configuration
const jwtSecret = readSecret('jwt_secret');

// External API keys
const openaiKey = readSecret('api_key_openai');
const sendgridKey = readSecret('api_key_sendgrid');

console.log('Configuration loaded successfully');
console.log('DB Host:', dbConfig.host);
console.log('Redis Host:', redisConfig.host);
// ❌ Şifreleri loglama!
```

#### Senaryo 2: Secret Rotation (Otomatik Şifre Değiştirme)

**Neden Secret Rotation?**

- Güvenlik best practice
- Compliance gereksinimleri (PCI-DSS, SOC 2)
- Breach durumunda zarar sınırlandırma
- Eski çalışanların erişimini sonlandırma

**Rotation Stratejisi:**

```
1. Yeni secret oluştur
2. Yeni container başlat (yeni secret ile)
3. Yeni container'ı test et
4. Trafiği yeni container'a yönlendir
5. Eski container'ı durdur
6. Eski secret'ı sil
```

**Rotation Script:**

```bash
#!/bin/bash
# rotate_secret.sh - Blue-Green deployment ile secret rotation

set -e

SECRET_NAME="$1"
NEW_SECRET_VALUE="$2"
CONTAINER_NAME="$3"

if [ -z "$SECRET_NAME" ] || [ -z "$NEW_SECRET_VALUE" ] || [ -z "$CONTAINER_NAME" ]; then
    echo "Usage: $0 <secret_name> <new_value> <container_name>"
    exit 1
fi

echo "=== Secret Rotation Başlatılıyor ==="
echo "Secret: $SECRET_NAME"
echo "Container: $CONTAINER_NAME"
echo ""

# 1. Geçici secret oluştur
TEMP_SECRET="${SECRET_NAME}_new_$(date +%s)"
echo "1. Creating temporary secret: $TEMP_SECRET"
echo -n "$NEW_SECRET_VALUE" | podman secret create "$TEMP_SECRET" -

# 2. Container bilgilerini al
echo "2. Gathering container information..."
IMAGE=$(podman inspect "$CONTAINER_NAME" --format '{{.ImageName}}')
PORTS=$(podman inspect "$CONTAINER_NAME" --format '{{range $port, $conf := .NetworkSettings.Ports}}{{$port}} {{end}}')
NETWORKS=$(podman inspect "$CONTAINER_NAME" --format '{{range $net, $conf := .NetworkSettings.Networks}}{{$net}} {{end}}')
ENV_VARS=$(podman inspect "$CONTAINER_NAME" --format '{{range .Config.Env}}{{println .}}{{end}}')

# 3. Yeni container başlat (blue-green pattern)
NEW_CONTAINER="${CONTAINER_NAME}-new"
echo "3. Starting new container: $NEW_CONTAINER"

RUN_CMD="podman run -d --name $NEW_CONTAINER"

# Old secret yerine yeni secret ekle
for secret in $(podman inspect "$CONTAINER_NAME" -f '{{range .Config.Secrets}}{{.Name}} {{end}}'); do
    if [ "$secret" == "$SECRET_NAME" ]; then
        RUN_CMD="$RUN_CMD --secret source=$TEMP_SECRET,target=$SECRET_NAME"
    else
        RUN_CMD="$RUN_CMD --secret $secret"
    fi
done

# Environment variables
while IFS= read -r env; do
    [ -n "$env" ] && RUN_CMD="$RUN_CMD -e '$env'"
done <<< "$ENV_VARS"

# Ports (geçici port kullan, sonra switch)
for port in $PORTS; do
    # Port format: 8080/tcp
    HOST_PORT=$(echo "$port" | cut -d'/' -f1)
    TEMP_PORT=$((HOST_PORT + 10000))
    RUN_CMD="$RUN_CMD -p $TEMP_PORT:$HOST_PORT"
done

# Image
RUN_CMD="$RUN_CMD $IMAGE"

# Container'ı başlat
eval "$RUN_CMD"

# 4. Health check
echo "4. Performing health check..."
sleep 5

if ! podman healthcheck run "$NEW_CONTAINER" 2>/dev/null; then
    echo "Warning: Healthcheck not configured, checking if container is running..."
    if ! podman ps -q -f name="$NEW_CONTAINER" | grep -q .; then
        echo "✗ New container failed to start"
        podman logs "$NEW_CONTAINER"
        podman rm -f "$NEW_CONTAINER"
        podman secret rm "$TEMP_SECRET"
        exit 1
    fi
fi

echo "✓ New container is healthy"

# 5. Traffic switch (eski container'ı durdur, yeni container'ı rename et)
echo "5. Switching traffic..."

# Eski container'ı durdur
podman stop "$CONTAINER_NAME"

# Yeni container için port mapping değiştir (gerçek port'a)
# Bu aslında yeni container'ı silip doğru portlarla tekrar başlatmayı gerektirir
# Veya load balancer kullanırsınız

# Basit yaklaşım: Eski container'ı sil, yeni container'ı rename et
podman rm "$CONTAINER_NAME"
podman rename "$NEW_CONTAINER" "$CONTAINER_NAME"

echo "✓ Traffic switched to new container"

# 6. Eski secret'ı sil, yeni secret'ı doğru isimle yeniden oluştur
echo "6. Finalizing secrets..."

# Yeni secret'ı kalıcı isimle oluştur
echo -n "$NEW_SECRET_VALUE" | podman secret create "${SECRET_NAME}_rotated_$(date +%Y%m%d)" -

# Geçici secret'ı sil
podman secret rm "$TEMP_SECRET"

echo ""
echo "=== Secret Rotation Tamamlandı ==="
echo "✓ Container: $CONTAINER_NAME"
echo "✓ Secret: $SECRET_NAME rotated"
echo "✓ Old container removed"
echo "✓ New container running with new secret"
```

**Otomatik Scheduled Rotation:**

```bash
# Crontab entry - her 90 günde bir
0 2 1 */3 * /usr/local/bin/rotate_secret.sh db_password "$(openssl rand -base64 32)" webapp >> /var/log/secret_rotation.log 2>&1
```

#### Senaryo 3: Multi-Environment Management

```bash
#!/bin/bash
# multi_env_secrets.sh - Environment-specific secrets

ENVIRONMENT="$1"  # prod, staging, dev

case "$ENVIRONMENT" in
    prod)
        echo "Setting up PRODUCTION secrets..."
        echo -n "prod-db-password-very-strong" | podman secret create prod_db_password -
        echo -n "sk-prod-openai-key" | podman secret create prod_api_key_openai -
        ;;
    staging)
        echo "Setting up STAGING secrets..."
        echo -n "staging-db-password" | podman secret create staging_db_password -
        echo -n "sk-staging-openai-key" | podman secret create staging_api_key_openai -
        ;;
    dev)
        echo "Setting up DEV secrets..."
        echo -n "dev-simple-password" | podman secret create dev_db_password -
        echo -n "sk-dev-test-key" | podman secret create dev_api_key_openai -
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT"
        exit 1
        ;;
esac

echo "✓ $ENVIRONMENT secrets configured"
```

### Secret Best Practices

#### 1. Principle of Least Privilege

```bash
# ✓ Her container sadece ihtiyacı olan secret'a erişmeli

# Backend container - sadece DB ve cache secret'ları
$ podman run -d \
    --name backend \
    --secret db_password \
    --secret redis_password \
    backend:latest

# Frontend container - secret'sız (public assets)
$ podman run -d \
    --name frontend \
    frontend:latest

# Admin container - tüm secret'lara erişim
$ podman run -d \
    --name admin \
    --secret db_password \
    --secret redis_password \
    --secret admin_api_key \
    admin:latest
```

#### 2. Secret Versioning

```bash
# Secret'ları versiyonla ve rollback imkanı tanı

# v1
$ echo "password_v1" | podman secret create db_password_v1 -

# v2 (rotation)
$ echo "password_v2" | podman secret create db_password_v2 -

# v3 (latest)
$ echo "password_v3" | podman secret create db_password_v3 -

# Aktif versiyonu kullan
$ podman run -d --secret source=db_password_v3,target=db_password myapp

# Sorun olursa rollback
$ podman stop myapp
$ podman rm myapp
$ podman run -d --secret source=db_password_v2,target=db_password myapp
```

#### 3. Secret Audit Logging

```bash
#!/bin/bash
# audit_secrets.sh - Secret kullanım auditi

LOG_FILE="/var/log/secret_audit.log"

echo "=== Secret Audit $(date) ===" | tee -a "$LOG_FILE"

# Tüm secret'ları listele
podman secret ls --format "{{.Name}}" | while read secret; do
    echo "" | tee -a "$LOG_FILE"
    echo "Secret: $secret" | tee -a "$LOG_FILE"
    
    # Oluşturma tarihi
    CREATED=$(podman secret inspect "$secret" --format '{{.CreatedAt}}')
    echo "  Created: $CREATED" | tee -a "$LOG_FILE"
    
    # Kullanan container'lar
    CONTAINERS=$(podman ps -a --format "{{.Names}}" | while read container; do
        if podman inspect "$container" 2>/dev/null | grep -q "\"Name\": \"$secret\""; then
            echo -n "$container "
        fi
    done)
    
    if [ -n "$CONTAINERS" ]; then
        echo "  Used by: $CONTAINERS" | tee -a "$LOG_FILE"
    else
        echo "  Used by: NONE (unused secret!)" | tee -a "$LOG_FILE"
    fi
done

# Kullanılmayan secret'lar
echo "" | tee -a "$LOG_FILE"
echo "=== Unused Secrets ===" | tee -a "$LOG_FILE"
podman secret ls --format "{{.Name}}" | while read secret; do
    used=false
    podman ps -a --format "{{.Names}}" | while read container; do
        if podman inspect "$container" 2>/dev/null | grep -q "\"Name\": \"$secret\""; then
            used=true
            break
        fi
    done
    
    if [ "$used" = false ]; then
        echo "  - $secret (consider removing)" | tee -a "$LOG_FILE"
    fi
done
```

#### 4. Backup ve Recovery

```bash
#!/bin/bash
# backup_secrets.sh - Encrypted secret backup

BACKUP_DIR="/secure/backups/secrets/$(date +%Y%m%d)"
ENCRYPTION_PASSWORD="your-strong-encryption-password"

mkdir -p "$BACKUP_DIR"

echo "=== Secret Backup ==="
echo "Backup directory: $BACKUP_DIR"

# Her secret için
podman secret ls --format "{{.Name}}" | while read secret; do
    echo "Backing up: $secret"
    
    # Secret içeriğini al (geçici container ile)
    temp_container="backup-temp-$$"
    
    # Alpine ile secret mount et ve oku
    SECRET_CONTENT=$(podman run --rm \
        --name "$temp_container" \
        --secret "$secret" \
        alpine cat "/run/secrets/$secret")
    
    # Şifrele ve kaydet
    echo -n "$SECRET_CONTENT" | \
        openssl enc -aes-256-cbc -salt -pbkdf2 \
        -pass pass:"$ENCRYPTION_PASSWORD" \
        > "$BACKUP_DIR/${secret}.enc"
    
    echo "✓ $secret backed up"
done

echo ""
echo "=== Backup Complete ==="
echo "Location: $BACKUP_DIR"
echo "Files:"
ls -lh "$BACKUP_DIR"
```

```bash
#!/bin/bash
# restore_secrets.sh - Secret restoration

BACKUP_DIR="$1"
ENCRYPTION_PASSWORD="$2"

if [ -z "$BACKUP_DIR" ] || [ -z "$ENCRYPTION_PASSWORD" ]; then
    echo "Usage: $0 <backup_dir> <encryption_password>"
    exit 1
fi

echo "=== Secret Restore ==="
echo "Source: $BACKUP_DIR"

for encrypted_file in "$BACKUP_DIR"/*.enc; do
    [ -e "$encrypted_file" ] || continue
    
    secret_name=$(basename "$encrypted_file" .enc)
    echo "Restoring: $secret_name"
    
    # Decrypt ve secret oluştur
    openssl enc -aes-256-cbc -d -pbkdf2 \
        -pass pass:"$ENCRYPTION_PASSWORD" \
        -in "$encrypted_file" | \
        podman secret create "$secret_name" -
    
    echo "✓ $secret_name restored"
done

echo ""
echo "=== Restore Complete ==="
podman secret ls
```

#### 5. Secret Validation

```bash
#!/bin/bash
# validate_secrets.sh - Secret bütünlük kontrolü

echo "=== Secret Validation ==="

# Gerekli secret'ların listesi
REQUIRED_SECRETS=(
    "prod_db_password"
    "prod_redis_password"
    "prod_jwt_secret"
    "prod_api_key_openai"
)

MISSING=()

for secret in "${REQUIRED_SECRETS[@]}"; do
    if podman secret ls --format "{{.Name}}" | grep -q "^${secret}$"; then
        echo "✓ $secret exists"
    else
        echo "✗ $secret MISSING"
        MISSING+=("$secret")
    fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
    echo ""
    echo "ERROR: Missing secrets:"
    printf '  - %s\n' "${MISSING[@]}"
    exit 1
fi

echo ""
echo "✓ All required secrets present"
```

---

## Özet

### Linux Namespaces

**8 farklı namespace türü:**

1. **PID Namespace**: Process ID izolasyonu
   - Her container kendi PID 1'ine sahip
   - Process tree izolasyonu
   - Zombie reaping

2. **Network Namespace**: Network stack izolasyonu
   - Kendi IP adresi
   - Kendi port'lar
   - Kendi firewall kuralları

3. **Mount Namespace**: Filesystem izolasyonu
   - Kendi root filesystem
   - Overlay filesystem desteği
   - Volume mounting

4. **UTS Namespace**: Hostname izolasyonu
   - Her container kendi hostname'i
   - Logging ve monitoring için kritik

5. **IPC Namespace**: Inter-process communication izolasyonu
   - Shared memory izolasyonu
   - Message queue izolasyonu

6. **User Namespace**: UID/GID mapping
   - Rootless container'lar
   - Güvenlik artışı

7. **Cgroup Namespace**: Cgroup görünümü izolasyonu
   - Resource limit gizleme

8. **Time Namespace**: Sistem saati izolasyonu
   - Test ve simülasyon

**Container teknolojilerinin temeli**: Docker, Podman, LXC bu namespace'leri kullanır.

### Podman Secrets

**Hassas bilgilerin güvenli yönetimi:**

- Environment variable'dan daha güvenli
- File-based mount ile container'da kullanım
- Process listesinde görünmez
- Şifreli depolama
- Rotation desteği
- Versioning mümkün
- Audit ve monitoring

**En İyi Pratikler:**

1. Environment variable yerine secret kullan
2. Least privilege prensibi uygula (her container sadece ihtiyacı kadar)
3. Secret rotation planı yap (90 gün)
4. Secrets'ları versiyonla
5. Audit logging yap
6. Encrypted backup al
7. Validation ve integrity check

**Gerçek Dünya Kullanımı:**

- Web application stack (DB, cache, API keys)
- Blue-green deployment ile rotation
- Multi-environment yönetimi (prod, staging, dev)
- Compliance gereksinimleri (PCI-DSS, SOC 2)

---

## Ek Kaynaklar

**Resmi Dokümantasyon:**

- Linux man pages: 
  - `man namespaces(7)`
  - `man unshare(1)`
  - `man nsenter(1)`
  - `man ip-netns(8)`

- Podman documentation: https://docs.podman.io/
  - Secrets guide: https://docs.podman.io/en/latest/markdown/podman-secret.1.html

**Linux Kernel:**

- Linux Kernel Documentation: https://www.kernel.org/doc/html/latest/
- Namespace implementation: kernel/nsproxy.c

**Standartlar:**

- OCI Runtime Specification: https://github.com/opencontainers/runtime-spec

**Güvenlik:**

- CIS Docker Benchmark
- NIST Container Security Guide

**Community:**

- Podman GitHub: https://github.com/containers/podman
- Podman discussions: https://github.com/containers/podman/discussions

---

**Son Güncelleme:** 24 Ekim 2025  
**Versiyon:** 2.0  
**Yazar:** Claude (Anthropic AI)
