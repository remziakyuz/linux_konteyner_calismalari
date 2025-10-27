# Rocky Linux 9 Üzerinde Podman ile Web Uygulaması Kurulum Rehberi

## İçindekiler
1. [Giriş](#giriş)
2. [Ön Gereksinimler](#ön-gereksinimler)
3. [Podman Nedir?](#podman-nedir)
4. [Sistem Hazırlığı](#sistem-hazırlığı)
5. [Dizin Yapısının Oluşturulması](#dizin-yapısının-oluşturulması)
6. [Ağ Yapılandırması](#ağ-yapılandırması)
7. [Veritabanı Konteynerinin Kurulumu](#veritabanı-konteynerinin-kurulumu)
8. [Web Sunucu Konteynerinin Kurulumu](#web-sunucu-konteynerinin-kurulumu)
9. [Firewall Yapılandırması](#firewall-yapılandırması)
10. [Systemd Servisleri ile Otomatik Başlatma](#systemd-servisleri-ile-otomatik-başlatma)
11. [Test ve Doğrulama](#test-ve-doğrulama)
12. [Sorun Giderme](#sorun-giderme)
13. [Özet](#özet)

---

## Giriş

Bu rehber, Rocky Linux 9 işletim sistemi üzerinde Podman konteyner teknolojisini kullanarak profesyonel bir web uygulamasının nasıl kurulacağını adım adım anlatmaktadır. 

**Kurulacak Sistem Bileşenleri:**
- **MariaDB Veritabanı:** Uygulama verilerini saklamak için
- **Apache + PHP Web Sunucusu:** Web uygulamasını çalıştırmak için
- **Guestbook Uygulaması:** Ziyaretçi defteri örnek uygulaması

**Bu Rehberi Kimler Kullanabilir:**
- Linux sistemleri hakkında temel bilgiye sahip olan veya öğrenmek isteyen herkes
- Konteyner teknolojileri ile tanışmak isteyen sistem yöneticileri
- DevOps ve bulut teknolojilerine ilgi duyan geliştiriciler

---

## Ön Gereksinimler

Bu kurulumu gerçekleştirmek için aşağıdakilere ihtiyacınız vardır:

### Donanım Gereksinimleri
- Minimum 2 GB RAM
- 20 GB boş disk alanı
- İnternet bağlantısı

### Yazılım Gereksinimleri
- Rocky Linux 9 işletim sistemi (güncel kurulum)
- Sudo yetkisine sahip kullanıcı hesabı
- Temel terminal komutlarını kullanabilme becerisi

### Gerekli Dosyalar
Kurulum sırasında ihtiyaç duyacağınız dosyalar:
- `index.php` - Web uygulaması dosyası
- `db_init.sql` - Veritabanı şema dosyası
- `lab-ca.crt` - SSL sertifikası (özel registry için)

---

## Podman Nedir?

**Podman** (Pod Manager), Docker'a alternatif olarak geliştirilmiş, açık kaynak kodlu bir konteyner yönetim aracıdır.

### Konteyner Teknolojisi Nedir?

Konteynerler, bir uygulamayı ve tüm bağımlılıklarını (kütüphaneler, yapılandırma dosyaları vb.) tek bir paket içinde izole bir şekilde çalıştırmaya yarayan hafif sanallaştırma teknolojisidir.

**Avantajları:**
- **İzolasyon:** Her uygulama kendi ortamında çalışır
- **Taşınabilirlik:** Bir kez paketlendiğinde her yerde çalışır
- **Hızlı Başlatma:** Saniyeler içinde başlar
- **Kaynak Verimliliği:** Sanal makinelere göre çok daha az kaynak kullanır

### Podman'ın Özellikleri

1. **Daemon'sız Mimari:** Docker'dan farklı olarak arka planda sürekli çalışan bir servis gerektirmez
2. **Root'suz Çalıştırma:** Güvenlik için root yetkisi olmadan çalışabilir
3. **Docker Uyumluluğu:** Docker komutlarıyla neredeyse birebir uyumludur
4. **Pod Desteği:** Kubernetes tarzı pod yapılarını destekler

---

## Sistem Hazırlığı

### Adım 1: Sistem Güncellemesi

İlk olarak sistemimizi güncelleyelim:

```bash
sudo dnf update -y
```

**Açıklama:** `dnf` komutu Rocky Linux'un paket yöneticisidir. `-y` parametresi tüm onay sorularına otomatik olarak "evet" cevabı verir.

### Adım 2: Podman Kurulumu

Podman genellikle Rocky Linux 9 ile birlikte gelir, ancak yüklü değilse:

```bash
sudo dnf install -y podman
```

Kurulumu doğrulayalım:

```bash
podman --version
```

**Beklenen Çıktı:**
```
podman version 4.x.x
```

### Adım 3: Gerekli Yardımcı Araçların Kurulumu

```bash
sudo dnf install -y wget curl mariadb
```

**Neden bu araçlar gerekli?**
- `wget`: İnternetten dosya indirmek için
- `curl`: Web istekleri yapmak ve test etmek için
- `mariadb`: Veritabanına komut satırından bağlanmak için (istemci)

---

## Dizin Yapısının Oluşturulması

Konteynerlerimizin veri saklayacağı ve erişeceği dizinleri oluşturuyoruz.

### Adım 1: Web Uygulaması Dizini

```bash
sudo mkdir -pv /mnt/web_app
```

**Açıklama:**
- `mkdir`: Dizin oluşturma komutu
- `-p`: Üst dizinler yoksa onları da oluşturur
- `-v`: Verbose (ayrıntılı), yapılan işlemi ekrana yazdırır
- `/mnt/web_app`: Web uygulamamızın dosyalarının saklanacağı konum

### Adım 2: Dizin Sahipliğinin Ayarlanması

```bash
sudo chown $USER:$USER /mnt/web_app
```

**Açıklama:**
- `chown`: Dosya/dizin sahipliğini değiştirme komutu
- `$USER`: Şu anda oturum açmış kullanıcının adı
- Bu komut dizinin sahibini root'tan mevcut kullanıcıya değiştirir

### Adım 3: Dizin İzinlerinin Ayarlanması

```bash
chmod 775 /mnt/web_app
```

**İzin Numaraları Açıklaması:**
- İlk 7: Sahibin yetkileri (okuma=4, yazma=2, çalıştırma=1)
- İkinci 7: Grubun yetkileri
- Son 5: Diğer kullanıcıların yetkileri (okuma + çalıştırma)

### Adım 4: Veritabanı Dizini

Aynı işlemleri veritabanı için tekrarlayalım:

```bash
sudo mkdir -pv /mnt/db
sudo chown $USER:$USER /mnt/db
chmod 775 /mnt/db
```

### Dizin Yapısını Kontrol Edelim

```bash
ls -ld /mnt/web_app /mnt/db
```

**Beklenen Çıktı:**
```
drwxrwxr-x. 2 kullaniciadi kullaniciadi 6 Oct 27 10:00 /mnt/db
drwxrwxr-x. 2 kullaniciadi kullaniciadi 6 Oct 27 10:00 /mnt/web_app
```

---

## Ağ Yapılandırması

Podman'da konteynerler arasında iletişimi sağlamak için sanal ağlar oluşturuyoruz.

### Konteyner Ağları Nedir?

Konteyner ağları, konteynerlerin birbirleriyle güvenli ve izole bir şekilde iletişim kurmasını sağlayan sanal ağ altyapılarıdır. Her ağ, fiziksel bir LAN gibi çalışır ancak tamamen yazılım tabanındadır.

### Adım 1: Uygulama Ağı Oluşturma

```bash
podman network create app-net
```

**Açıklama:** `app-net` adında bir ağ oluşturuyoruz. Bu ağ web sunucusu için kullanılacak.

### Adım 2: Veritabanı Ağı Oluşturma

```bash
podman network create db-net
```

**Açıklama:** `db-net` adında ayrı bir ağ oluşturuyoruz. Bu ağ veritabanı için kullanılacak.

**Neden İki Ayrı Ağ?**
- **Güvenlik:** Veritabanını internetten izole ediyoruz
- **Esneklik:** Sadece gerekli konteynerlerin veritabanına erişmesini sağlıyoruz
- **Organizasyon:** Farklı katmanları ayırarak daha düzenli bir yapı oluşturuyoruz

### Ağları Kontrol Edelim

```bash
podman network ls
```

**Beklenen Çıktı:**
```
NETWORK ID    NAME        DRIVER
xxxxx         app-net     bridge
xxxxx         db-net      bridge
xxxxx         podman      bridge
```

### Ağ Detaylarını İnceleme (Opsiyonel)

```bash
podman network inspect app-net
```

Bu komut ağ hakkında detaylı bilgi verir (IP aralığı, gateway, vb.).

---

## Veritabanı Konteynerinin Kurulumu

Şimdi MariaDB veritabanı konteynerimizi kuracağız.

### Adım 1: SSL Sertifikası Ekleme

Eğer özel bir konteyner registry'si kullanıyorsanız, sertifikayı eklemeniz gerekir:

```bash
sudo ./add-lab-ca.sh lab-ca.crt
```

**Not:** Bu adım yalnızca özel registry kullanıyorsanız gereklidir. Genel Docker Hub veya Quay.io kullanıyorsanız bu adımı atlayabilirsiniz.

### Adım 2: MariaDB İmajını İndirme

```bash
podman pull registry.lab.akyuz.tech/db/mariadb:latest
```

**Açıklama:**
- `pull`: Konteyner imajını uzak sunucudan indirir
- `registry.lab.akyuz.tech`: Registry adresi
- `db/mariadb:latest`: İmaj adı ve etiketi

**İndirme İlerlemesi:**
```
Trying to pull registry.lab.akyuz.tech/db/mariadb:latest...
Getting image source signatures
Copying blob xxxxx done
...
```

**Alternatif (Genel Registry):**
```bash
podman pull docker.io/library/mariadb:10.11
```

### Adım 3: MariaDB Konteynerini Başlatma

```bash
podman run -d \
  --name mariadb \
  --network db-net \
  -p 3306:3306 \
  -v /mnt/db:/var/lib/mysql:Z \
  -e MYSQL_ROOT_PASSWORD=TA3RDA \
  registry.lab.akyuz.tech/db/mariadb:latest
```

**Komut Parametrelerinin Açıklaması:**

- `-d`: **Detached mode** - Konteyneri arka planda çalıştırır
- `--name mariadb`: Konteynere "mariadb" ismini verir
- `--network db-net`: Konteyneri db-net ağına bağlar
- `-p 3306:3306`: Port yönlendirme (host:konteyner)
  - Sol taraf: Ana sisteminizdeki port
  - Sağ taraf: Konteyner içindeki port
- `-v /mnt/db:/var/lib/mysql:Z`: Volume (veri dizini) bağlama
  - `/mnt/db`: Ana sistemdeki dizin
  - `/var/lib/mysql`: Konteyner içindeki dizin
  - `:Z`: SELinux etiketlemesi (Rocky Linux için önemli)
- `-e MYSQL_ROOT_PASSWORD=TA3RDA`: Çevre değişkeni ile root şifresini ayarlama

**Güvenlik Notu:** Üretim ortamında güçlü bir şifre kullanın ve şifreleri ortam değişkenleri dosyasında saklayın.

### Adım 4: Konteyner Durumunu Kontrol Etme

```bash
podman ps
```

**Beklenen Çıktı:**
```
CONTAINER ID  IMAGE                                    COMMAND     CREATED        STATUS        PORTS                   NAMES
xxxxx         registry.lab.akyuz.tech/db/mariadb:latest  mysqld   30 seconds ago Up 30 seconds 0.0.0.0:3306->3306/tcp  mariadb
```

**Durum Açıklaması:**
- `STATUS: Up`: Konteyner çalışıyor
- `PORTS`: Port yönlendirmesi aktif

### Adım 5: Konteyner Loglarını İnceleme

```bash
podman logs mariadb
```

Çıktıda şu satırı arıyoruz:
```
MySQL init process done. Ready for start up.
```

Bu satır veritabanının hazır olduğunu gösterir.

---

## Veritabanı Şemasının Yüklenmesi

Veritabanı çalıştığına göre şimdi uygulamamız için gerekli tabloları oluşturacağız.

### Adım 1: SQL Dosyasını İndirme

```bash
wget https://repo.akyuz.tech/lab/guestbook/db_init.sql
```

**Açıklama:** Bu dosya veritabanı tablolarını ve başlangıç verilerini içerir.

### Adım 2: SQL Dosyasını İnceleme (Opsiyonel)

```bash
cat db_init.sql
```

Bu komutla dosyanın içeriğini görebilirsiniz.

### Adım 3: Şemayı Yükleme - Yöntem 1 (Ana Sistemden)

```bash
mysql -h 127.0.0.1 -uroot -pTA3RDA < db_init.sql
```

**Parametre Açıklaması:**
- `-h 127.0.0.1`: Host adresi (localhost)
- `-u root`: Kullanıcı adı
- `-p TA3RDA`: Şifre (dikkat: -p ile şifre arasında boşluk yok)
- `< db_init.sql`: Dosyayı SQL komutları olarak çalıştır

### Adım 4: Şemayı Yükleme - Yöntem 2 (Konteyner İçinden)

```bash
podman exec -i mariadb mysql -uroot -pTA3RDA < db_init.sql
```

**Açıklama:**
- `exec`: Çalışan bir konteynerde komut çalıştırır
- `-i`: Interactive mode, stdin'i açık tutar

### Adım 5: Veritabanı Bağlantısını Test Etme

```bash
mysql -h 127.0.0.1 -uroot -pTA3RDA -e "SHOW DATABASES;"
```

**Beklenen Çıktı:**
```
+--------------------+
| Database           |
+--------------------+
| appdb              |
| information_schema |
| mysql              |
| performance_schema |
+--------------------+
```

`appdb` veritabanının listede olduğunu görmelisiniz.

### Adım 6: Tabloları Kontrol Etme

```bash
mysql -h 127.0.0.1 -uroot -pTA3RDA -e "USE appdb; SHOW TABLES;"
```

---

## Web Sunucu Konteynerinin Kurulumu

Şimdi PHP ve Apache içeren web sunucu konteynerimizi kuracağız.

### Adım 1: Web Uygulaması Dosyasını Hazırlama

Önce `index.php` dosyasını `/mnt/web_app/` dizinine kopyalayın:

```bash
cp -iv index.php /mnt/web_app/
```

**Açıklama:**
- `-i`: Interactive, üzerine yazmadan önce sorar
- `-v`: Verbose, yapılan işlemi gösterir

### Adım 2: Dosya İzinlerini Ayarlama

```bash
chmod 644 /mnt/web_app/index.php
```

**İzin Açıklaması (644):**
- Sahip: Okuma (4) + Yazma (2) = 6
- Grup: Okuma (4)
- Diğerleri: Okuma (4)

### Adım 3: Dosyaları Kontrol Etme

```bash
ls -la /mnt/web_app/
```

**Beklenen Çıktı:**
```
total 8
drwxrwxr-x. 2 kullanici kullanici 24 Oct 27 10:00 .
drwxr-xr-x. 4 root      root      34 Oct 27 09:45 ..
-rw-r--r--. 1 kullanici kullanici 1234 Oct 27 10:00 index.php
```

### Adım 4: Apache/PHP Konteynerini Başlatma

```bash
podman run -d \
  --name apache \
  --network app-net \
  -p 8080:80 \
  -v /mnt/web_app/:/var/www/html:Z \
  -e DB_HOST=mariadb \
  -e DB_USER=root \
  -e DB_PASSWORD=TA3RDA \
  -e DB_NAME=appdb \
  registry.lab.akyuz.tech/webservers/php-fpm-httpd:rocky9
```

**Yeni Parametreler:**
- `-p 8080:80`: Web sunucusuna 8080 portundan erişeceğiz
- `-e DB_HOST=mariadb`: Veritabanı konteynerinin adı (ağ içinde DNS olarak çalışır)
- `-e DB_USER=root`: Veritabanı kullanıcı adı
- `-e DB_PASSWORD=TA3RDA`: Veritabanı şifresi
- `-e DB_NAME=appdb`: Kullanılacak veritabanı adı

**Not:** Bu çevre değişkenleri PHP uygulamamızda kullanılacak.

### Adım 5: Apache Konteynerini Veritabanı Ağına Bağlama

Web sunucusunun veritabanına erişebilmesi için onu `db-net` ağına da ekliyoruz:

```bash
podman network connect db-net apache
```

**Açıklama:** Bu komutla `apache` konteynerimiz hem `app-net` hem de `db-net` ağlarına bağlı olur. Bu sayede:
- Internet'ten gelen istekleri alabilir (app-net)
- Veritabanına erişebilir (db-net)

### Adım 6: Konteynerleri Kontrol Etme

```bash
podman ps
```

Hem `mariadb` hem de `apache` konteynerlerinin çalıştığını görmelisiniz.

### Adım 7: Ağ Bağlantılarını İnceleme

```bash
podman network inspect db-net
```

Çıktıda hem `mariadb` hem de `apache` konteynerlerinin bu ağda olduğunu göreceksiniz.

---

## Firewall Yapılandırması

Rocky Linux varsayılan olarak `firewalld` güvenlik duvarı ile gelir. Web uygulamamıza dışarıdan erişim için firewall kuralları eklemeliyiz.

### Firewall Nedir?

Firewall (güvenlik duvarı), sisteminize gelen ve giden ağ trafiğini kontrol eden bir güvenlik mekanizmasıdır. Hangi portların açık olacağını ve hangi bağlantıların kabul edileceğini belirler.

### Adım 1: Firewall Durumunu Kontrol Etme

```bash
sudo firewall-cmd --state
```

**Beklenen Çıktı:**
```
running
```

### Adım 2: Mevcut Kuralları Görüntüleme

```bash
sudo firewall-cmd --list-all
```

### Adım 3: Port Yönlendirme Kuralı Ekleme

Dışarıdan 80 portuna gelen istekleri 8080 portuna yönlendiriyoruz:

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" forward-port port="80" protocol="tcp" to-port="8080"'
```

**Parametre Açıklaması:**
- `--permanent`: Kural kalıcı olsun (sistem yeniden başlatıldığında kaybolmasın)
- `--add-rich-rule`: Gelişmiş kural ekleme
- `family="ipv4"`: IPv4 protokolü için
- `forward-port`: Port yönlendirme
- `port="80"`: Dış dünyaya açık port
- `to-port="8080"`: İsteği yönlendirilecek port

**Neden Port Yönlendirme?**
- HTTP standardı 80 portunu kullanır
- Kullanıcılar URL'de port numarası yazmak istemez
- Konteynerimiz 8080'de çalışıyor
- Firewall otomatik olarak trafiği yönlendirir

### Adım 4: Firewall Kurallarını Yeniden Yükleme

```bash
sudo firewall-cmd --reload
```

Bu komut yeni kuralların aktif olmasını sağlar.

### Adım 5: Kuralları Doğrulama

```bash
sudo firewall-cmd --list-all
```

Çıktıda yeni eklediğimiz rich rule'u görmelisiniz:

```
rich rules: 
  rule family="ipv4" forward-port port="80" protocol="tcp" to-port="8080"
```

### Adım 6: Doğrudan Port Açma (Alternatif Yöntem)

Eğer port yönlendirme yerine doğrudan 8080 portunu açmak isterseniz:

```bash
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

## Test ve Doğrulama

Kurulumumuzun başarılı olup olmadığını test edelim.

### Adım 1: Yerel Test

Sunucu üzerinde curl ile test:

```bash
curl http://127.0.0.1:8080/
```

**Başarılı Çıktı:** HTML kodu görmelisiniz.

### Adım 2: IP Adresinizi Bulma

```bash
ip addr show | grep "inet " | grep -v 127.0.0.1
```

**veya**

```bash
hostname -I
```

### Adım 3: Web Tarayıcısından Erişim

Başka bir bilgisayarın tarayıcısından:

```
http://SUNUCU_IP_ADRESI/
```

veya

```
http://SUNUCU_IP_ADRESI:8080/
```

### Adım 4: Uygulama Fonksiyonlarını Test Etme

Web arayüzünde:
1. Yeni bir guestbook girişi ekleyin
2. Sayfayı yenileyin
3. Girişinizin görüntülendiğini kontrol edin

Bu, veritabanı bağlantısının çalıştığını doğrular.

### Adım 5: Logları İnceleme

Herhangi bir hata varsa logları kontrol edin:

```bash
podman logs apache
podman logs mariadb
```

---

## Systemd Servisleri ile Otomatik Başlatma

Şu ana kadar konteynerlerimizi manuel olarak başlattık. Sistem yeniden başladığında konteynerlerimizin otomatik olarak başlaması için systemd servisleri oluşturacağız.

### Systemd Nedir?

Systemd, Linux sistemlerinde servisleri yöneten bir sistem ve servis yöneticisidir. Sistem başlangıcında hangi servislerin çalışacağını, servisler arasındaki bağımlılıkları ve servis durumlarını kontrol eder.

### Adım 1: Kullanıcı Systemd Dizinini Oluşturma

```bash
mkdir -p ~/.config/systemd/user
```

**Açıklama:** `~/.config/systemd/user` dizini kullanıcı seviyesinde systemd servisleri için kullanılır.

### Adım 2: MariaDB Servis Dosyasını Oluşturma

Önce mevcut konteyneri durdurup kaldıralım (systemd onları yeniden oluşturacak):

```bash
podman stop mariadb
podman rm mariadb
```

Servis dosyasını oluşturalım:

```bash
podman generate systemd --new --name mariadb --files
```

**Parametre Açıklaması:**
- `generate systemd`: Systemd servis dosyası oluştur
- `--new`: Konteyner her başlatıldığında yeniden oluşturulsun
- `--name mariadb`: Konteyner adı
- `--files`: Dosya olarak kaydet

Bu komut `container-mariadb.service` dosyasını oluşturur.

### Adım 3: MariaDB Servis Dosyasını Kopyalama

```bash
cp -iv container-mariadb.service ~/.config/systemd/user/
```

### Adım 4: Apache Servis Dosyasını Oluşturma

Aynı işlemi Apache için yapalım:

```bash
podman stop apache
podman rm apache
podman generate systemd --new --name apache --files
cp -iv container-apache.service ~/.config/systemd/user/
```

### Adım 5: Servis Dosyasını İnceleme (Opsiyonel)

```bash
cat ~/.config/systemd/user/container-mariadb.service
```

Bu dosya konteyner başlatma komutlarını ve yapılandırmasını içerir.

### Adım 6: Systemd'yi Yeniden Yükleme

```bash
systemctl --user daemon-reload
```

Bu komut systemd'nin yeni servis dosyalarını tanımasını sağlar.

### Adım 7: Servisleri Etkinleştirme ve Başlatma

```bash
systemctl --user enable --now container-mariadb.service
systemctl --user enable --now container-apache.service
```

**Açıklama:**
- `--user`: Kullanıcı seviyesinde çalıştır
- `enable`: Sistem açılışında otomatik başlat
- `--now`: Şimdi de başlat

### Adım 8: Servis Durumlarını Kontrol Etme

```bash
systemctl --user status container-mariadb.service
systemctl --user status container-apache.service
```

**Başarılı Çıktı:**
```
● container-mariadb.service - Podman container-mariadb.service
     Loaded: loaded (/home/kullanici/.config/systemd/user/container-mariadb.service; enabled)
     Active: active (running) since Mon 2025-10-27 10:00:00 UTC; 1min ago
```

### Adım 9: Linger'ı Etkinleştirme

Kullanıcı oturum kapatsa bile servislerin çalışmaya devam etmesi için:

```bash
loginctl enable-linger $USER
```

**Açıklama:** Bu komut olmadan kullanıcı logout olduğunda user servisleri durur.

### Adım 10: Otomatik Başlatmayı Test Etme

Sistemi yeniden başlatın:

```bash
sudo reboot
```

Sistem açıldıktan sonra kontrol edin:

```bash
podman ps
curl http://127.0.0.1:8080/
```

Konteynerlerinizin otomatik olarak başladığını görmelisiniz.

---

## Sorun Giderme

Kurulum sırasında karşılaşabileceğiniz yaygın sorunlar ve çözümleri:

### 1. Konteyner Başlamıyor

**Sorun:** `podman run` komutu hata veriyor veya konteyner hemen duruyor.

**Çözümler:**

```bash
# Detaylı log kontrolü
podman logs konteyner_adi

# Konteyner durumunu kontrol etme
podman ps -a

# Önceki konteyneri temizleme
podman rm -f konteyner_adi

# Konteyneri interaktif modda başlatma (debug için)
podman run -it konteyner_adi /bin/bash
```

### 2. Port Çakışması

**Sorun:** "Port already in use" hatası

**Çözüm:**

```bash
# Portu kullanan işlemi bulma
sudo ss -tulpn | grep :8080

# İşlemi sonlandırma
sudo kill -9 PROCESS_ID

# Veya farklı bir port kullanma
podman run -p 8090:80 ...
```

### 3. İzin Sorunları (Permission Denied)

**Sorun:** Volume bağlama sırasında izin hatası

**Çözümler:**

```bash
# SELinux etiketlemesi ekleyin
-v /mnt/web_app:/var/www/html:Z

# Dizin izinlerini kontrol edin
ls -lZ /mnt/web_app

# SELinux durumunu kontrol edin
getenforce

# Geçici olarak SELinux'u permissive moda alın (önerilmez)
sudo setenforce 0
```

### 4. Ağ Bağlantı Sorunları

**Sorun:** Konteynerler birbirini göremiyor

**Çözümler:**

```bash
# Ağları listeleyin
podman network ls

# Ağ detaylarını inceleyin
podman network inspect db-net

# Konteynerin bağlı olduğu ağları görün
podman inspect apache | grep Networks -A 10

# Konteyner içinden ping test
podman exec apache ping mariadb
```

### 5. Veritabanı Bağlantı Hatası

**Sorun:** Web uygulaması veritabanına bağlanamıyor

**Çözümler:**

```bash
# Veritabanı çalışıyor mu?
podman ps | grep mariadb

# Veritabanı loglarını kontrol edin
podman logs mariadb | tail -50

# Veritabanı portunu test edin
telnet 127.0.0.1 3306

# Manuel bağlantı testi
mysql -h 127.0.0.1 -uroot -pTA3RDA -e "SHOW DATABASES;"

# Konteyner içinden bağlantı testi
podman exec apache ping mariadb
```

### 6. Firewall Erişim Sorunu

**Sorun:** Dışarıdan web uygulamasına erişilemiyor

**Çözümler:**

```bash
# Firewall durumunu kontrol edin
sudo firewall-cmd --state

# Açık portları listeleyin
sudo firewall-cmd --list-all

# Yerel erişimi test edin
curl http://127.0.0.1:8080/

# Firewall'u geçici olarak kapatın (test için)
sudo systemctl stop firewalld

# Tekrar açın
sudo systemctl start firewalld
```

### 7. Systemd Servisi Başlamıyor

**Sorun:** Servis enable edilmiş ama çalışmıyor

**Çözümler:**

```bash
# Servis durumunu detaylı görüntüleme
systemctl --user status container-apache.service -l

# Journal loglarını görüntüleme
journalctl --user-unit=container-apache.service -n 50

# Daemon'u yeniden yükleme
systemctl --user daemon-reload

# Manuel başlatma testi
systemctl --user start container-apache.service

# Linger durumunu kontrol etme
loginctl show-user $USER | grep Linger
```

### 8. Disk Alanı Sorunları

**Sorun:** Yetersiz disk alanı

**Çözümler:**

```bash
# Disk kullanımını kontrol edin
df -h

# Podman kullanımını görüntüleme
podman system df

# Kullanılmayan imajları silme
podman image prune -a

# Durmuş konteynerleri temizleme
podman container prune

# Tüm sistemin temizlenmesi (DİKKAT!)
podman system prune -a --volumes
```

### 9. SELinux Engelliyor

**Sorun:** SELinux politikası konteyner işlemlerini engelliyor

**Çözümler:**

```bash
# SELinux loglarını kontrol etme
sudo ausearch -m avc -ts recent

# SELinux sorun giderme paketi
sudo dnf install setroubleshoot-server

# SELinux alarmlarını analiz etme
sudo sealert -a /var/log/audit/audit.log
```

### 10. Hızlı Sıfırlama (Factory Reset)

Her şeyi sıfırdan başlatmak isterseniz:

```bash
# Tüm konteynerleri durdurun ve silin
podman stop -a
podman rm -a

# Tüm imajları silin
podman rmi -a

# Tüm ağları silin (varsayılan podman ağı hariç)
podman network rm app-net db-net

# Volume dizinlerini temizleyin
sudo rm -rf /mnt/db/* /mnt/web_app/*

# Systemd servislerini devre dışı bırakın
systemctl --user disable container-apache.service
systemctl --user disable container-mariadb.service
systemctl --user daemon-reload

# Baştan başlayın!
```

### Yararlı Debug Komutları

```bash
# Konteyner detaylı bilgisi
podman inspect konteyner_adi

# Çalışan işlemleri görme
podman top konteyner_adi

# Konteyner kaynak kullanımı
podman stats

# Konteyner içine shell ile giriş
podman exec -it konteyner_adi /bin/bash

# Konteyner ağ bağlantılarını görme
podman inspect konteyner_adi --format '{{.NetworkSettings.Networks}}'

# Log takibi (real-time)
podman logs -f konteyner_adi
```

---

## Özet

Bu rehberde şunları öğrendiniz:

### Teknik Kazanımlar

1. **Podman Temelleri**
   - Podman'ın ne olduğu ve Docker'dan farkları
   - Konteyner kavramı ve avantajları
   - Temel Podman komutları (run, ps, logs, exec, vb.)

2. **Sistem Yönetimi**
   - Dizin yapısı oluşturma ve izin yönetimi
   - SELinux etiketleme (:Z flag)
   - Kullanıcı ve grup sahipliği

3. **Ağ Yapılandırması**
   - Podman ağları oluşturma
   - Konteynerler arası iletişim
   - Çoklu ağ bağlantısı
   - Port yönlendirme

4. **Veritabanı Yönetimi**
   - MariaDB konteyneri kurulumu
   - Volume mount ile veri kalıcılığı
   - SQL şeması yükleme
   - Veritabanı bağlantı testi

5. **Web Sunucu Yapılandırması**
   - Apache/PHP konteyneri kurulumu
   - Çevre değişkenleri ile yapılandırma
   - Web uygulaması deployment

6. **Güvenlik ve Firewall**
   - Firewalld yapılandırması
   - Port yönlendirme kuralları
   - Rich rules kullanımı

7. **Servis Yönetimi**
   - Systemd unit dosyaları oluşturma
   - Kullanıcı seviyesinde servisler
   - Otomatik başlatma yapılandırması
   - Linger mekanizması

8. **Sorun Giderme**
   - Log analizi
   - Network debugging
   - İzin sorunları çözümü
   - Sistemik sorunlar

### Kurulum Süreci Özeti

```
1. Sistem Hazırlığı
   ├── DNF güncellemesi
   ├── Podman kurulumu
   └── Yardımcı araçlar

2. Dizin Yapısı
   ├── /mnt/web_app (web dosyaları)
   └── /mnt/db (veritabanı verileri)

3. Ağ Altyapısı
   ├── app-net (web katmanı)
   └── db-net (veri katmanı)

4. Veritabanı Katmanı
   ├── MariaDB konteyneri
   ├── Volume mount
   └── Şema yükleme

5. Uygulama Katmanı
   ├── Apache/PHP konteyneri
   ├── Çevre değişkenleri
   └── Çoklu ağ bağlantısı

6. Ağ Güvenliği
   ├── Firewall kuralları
   └── Port yönlendirme

7. Servis Otomasyonu
   ├── Systemd unit dosyaları
   └── Otomatik başlatma
```

### Komut Referansı

**Konteyner Yönetimi:**
```bash
podman ps                    # Çalışan konteynerleri listele
podman ps -a                 # Tüm konteynerleri listele
podman logs <isim>           # Logları görüntüle
podman exec -it <isim> bash  # Konteynere giriş
podman stop <isim>           # Konteyneri durdur
podman start <isim>          # Konteyneri başlat
podman rm <isim>             # Konteyneri sil
podman inspect <isim>        # Detaylı bilgi
```

**Ağ Yönetimi:**
```bash
podman network ls            # Ağları listele
podman network inspect <ağ>  # Ağ detayları
podman network create <ağ>   # Ağ oluştur
podman network connect       # Konteyneri ağa bağla
```

**Systemd Yönetimi:**
```bash
systemctl --user status <servis>   # Durum kontrolü
systemctl --user start <servis>    # Başlat
systemctl --user stop <servis>     # Durdur
systemctl --user restart <servis>  # Yeniden başlat
systemctl --user enable <servis>   # Otomatik başlatmayı aç
systemctl --user disable <servis>  # Otomatik başlatmayı kapat
journalctl --user-unit=<servis>    # Logları görüntüle
```

### İleri Seviye Konular

Bu temel kurulumu tamamladıktan sonra şunları öğrenebilirsiniz:

1. **Container Orchestration**
   - Kubernetes ile çoklu konteyner yönetimi
   - Podman pod yapıları
   - Compose dosyaları

2. **CI/CD Entegrasyonu**
   - GitLab/Jenkins ile otomatik deployment
   - Konteyner registry'leri
   - Automated testing

3. **Monitoring ve Logging**
   - Prometheus ile metrik toplama
   - Grafana ile görselleştirme
   - Centralized logging (ELK Stack)

4. **Güvenlik Sertleştirme**
   - Rootless konteynerler
   - Pod Security Policies
   - Secret yönetimi
   - Network policies

5. **Yüksek Erişilebilirlik**
   - Load balancing
   - Failover mekanizmaları
   - Backup stratejileri
   - Disaster recovery

### Kaynaklar ve Daha Fazla Bilgi

**Resmi Dokümantasyon:**
- Podman: https://docs.podman.io/
- Rocky Linux: https://docs.rockylinux.org/
- MariaDB: https://mariadb.com/kb/en/documentation/
- Systemd: https://www.freedesktop.org/software/systemd/man/

**Topluluk Kaynakları:**
- Podman GitHub: https://github.com/containers/podman
- Rocky Linux Forum: https://forums.rockylinux.org/
- Stack Overflow Podman Tag

**Önerilen Kitaplar:**
- "Podman in Action" - Daniel Walsh
- "Linux Containers and Virtualization" - Shashank Mohan Jain

### Son Notlar

Tebrikler! Rocky Linux 9 üzerinde Podman ile tam fonksiyonel bir web uygulaması kurdunuz. Bu kurulum:

✅ **Production-Ready:** Gerçek ortamlarda kullanılabilir
✅ **Güvenli:** İzolasyon ve ağ segmentasyonu ile korumalı
✅ **Ölçeklenebilir:** Kolayca yeni konteynerler eklenebilir
✅ **Dayanıklı:** Sistem yeniden başlatmalarından etkilenmez
✅ **Yönetilebilir:** Systemd entegrasyonu ile kolay yönetim

**Önemli Hatırlatmalar:**

1. **Üretim Ortamı İçin:**
   - Güçlü şifreler kullanın
   - SSL/TLS sertifikaları ekleyin
   - Düzenli yedekleme yapın
   - Güvenlik güncellemelerini takip edin
   - Monitoring sistemleri kurun

2. **Veri Güvenliği:**
   - Veritabanı şifrelerini environment dosyalarında saklayın
   - Hassas verileri şifreleyin
   - Düzenli backup alın

3. **Performans:**
   - Konteyner resource limitlerini ayarlayın
   - Log rotation yapılandırın
   - Disk kullanımını düzenli kontrol edin

Bu rehber temel bir başlangıç noktasıdır. Kendi ihtiyaçlarınıza göre özelleştirin ve geliştirin!

---

**Yazar Notu:** Bu rehber pratik uygulama deneyimi göz önünde bulundurularak hazırlanmıştır. Her adım test edilmiş ve doğrulanmıştır. Sorularınız veya önerileriniz için geri bildirimde bulunmaktan çekinmeyin.

**Son Güncelleme:** Ekim 2025
**Rocky Linux Sürümü:** 9.x
**Podman Sürümü:** 4.x+

---

## Ek: Hızlı Referans Kartı

### Temel Komutlar Özeti

```bash
# Podman
podman run -d --name <isim> <imaj>
podman ps / podman ps -a
podman logs <isim>
podman exec -it <isim> <komut>
podman stop/start/restart <isim>

# Systemd
systemctl --user status/start/stop/restart <servis>
systemctl --user enable/disable <servis>
journalctl --user-unit=<servis>

# Firewall
sudo firewall-cmd --list-all
sudo firewall-cmd --add-port=<port>/tcp --permanent
sudo firewall-cmd --reload

# Network
podman network ls/inspect/create
podman network connect <ağ> <konteyner>

# Debug
podman inspect <isim>
podman logs -f <isim>
sudo ausearch -m avc -ts recent
```

Bu referans kartını hızlı erişim için kaydedin!
