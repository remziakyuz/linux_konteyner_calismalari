# AWX Ingress & TLS/SSL Kurulum Dokümantasyonu

## 📋 İçindekiler
- [Genel Bakış](#genel-bakış)
- [Kurulum Sonrası Adımlar](#kurulum-sonrası-adımlar)
- [Sertifika Yükleme](#sertifika-yükleme)
- [Erişim Kontrolleri](#erişim-kontrolleri)
- [Sorun Giderme](#sorun-giderme)
- [Dosya Yapısı](#dosya-yapısı)

---

## 🎯 Genel Bakış

Bu script, AWX için Ingress controller ve TLS/SSL sertifikalarını otomatik olarak yapılandırır.

### Upstream Docs:
- AWX Operator: https://github.com/ansible/awx-operator
- Kubernetes Ingress: https://kubernetes.io/docs/concepts/services-networking/ingress/
- NGINX Ingress: https://kubernetes.github.io/ingress-nginx/

---

## ✅ Kurulum Başarı Kontrol Listesi

- [ ] Script hatasız tamamlandı
- [ ] CA sertifikası sistem/tarayıcıya yüklendi
- [ ] https://awx.lab.akyuz.tech erişilebilir
- [ ] https://awx.local erişilebilir
- [ ] Sertifika uyarısı yok
- [ ] AWX login ekranı görünüyor
- [ ] Ingress ADDRESS değeri var

---

**Son Güncelleme:** 2025-10-17  
**Script Version:** v17.2 (Enhanced)  
**Yazar:** Remzi

**v17.2 İyileştirmeleri:**
- ✅ SAN dosyası oluşturma hatası düzeltildi
- ✅ IP doğrulama regex'leri iyileştirildi
- ✅ Tekrarlanan kod blokları kaldırıldı
- ✅ Hata toleransı artırıldı
- ✅ Değişken yönetimi iyileştirildi

---

## 🚀 Kurulum Sonrası Adımlar

### 1. CA Sertifikasını Yükleyin

CA sertifikası burada bulunmaktadır:
```
/awx-install/dosyalar/certificates/local-awx-ca.crt
```

#### Ubuntu/Debian için:
```bash
sudo cp /awx-install/dosyalar/certificates/local-awx-ca.crt /usr/local/share/ca-certificates/awx-local-ca.crt
sudo update-ca-certificates
```

#### RHEL/Rocky/CentOS için:
```bash
sudo cp /awx-install/dosyalar/certificates/local-awx-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

#### Windows için:
1. `local-awx-ca.crt` dosyasına çift tıklayın
2. "Install Certificate" butonuna tıklayın
3. "Local Machine" seçin
4. "Place all certificates in the following store" seçin
5. "Trusted Root Certification Authorities" seçin
6. Kurulumu tamamlayın

#### macOS için:
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain /awx-install/dosyalar/certificates/local-awx-ca.crt
```

#### Firefox için (ayrı sertifika deposu kullanır):
1. Firefox > Settings > Privacy & Security
2. "View Certificates" butonuna tıklayın
3. "Authorities" sekmesine gidin
4. "Import" ile CA sertifikasını ekleyin
5. "Trust this CA to identify websites" seçeneğini işaretleyin

---

## 🔍 Erişim Kontrolleri

### Ingress Durumunu Kontrol Etme:
```bash
# Ingress listesi
sudo microk8s kubectl get ingress -n awx

# Detaylı bilgi
sudo microk8s kubectl describe ingress awx-ingress -n awx

# Ingress controller logları
sudo microk8s kubectl logs -n ingress -l app.kubernetes.io/name=ingress-nginx
```

### AWX Servislerini Kontrol Etme:
```bash
# Tüm podlar
sudo microk8s kubectl get pods -n awx

# Servisler
sudo microk8s kubectl get services -n awx

# AWX web pod logları
sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-web

# AWX task pod logları
sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-task
```

### Sertifika Bilgilerini Görüntüleme:
```bash
# Sertifika içeriği
openssl x509 -in /awx-install/dosyalar/certificates/local-awx.crt -text -noout

# SAN listesi
openssl x509 -in /awx-install/dosyalar/certificates/local-awx.crt -text -noout | grep -A 10 "Subject Alternative Name"

# Geçerlilik tarihleri
openssl x509 -in /awx-install/dosyalar/certificates/local-awx.crt -noout -dates
```

### HTTPS Erişimi Test Etme:
```bash
# curl ile test (sertifika doğrulama ile)
curl -v https://awx.lab.akyuz.tech

# curl ile test (sertifika doğrulama olmadan)
curl -k -v https://awx.lab.akyuz.tech

# Specific IP ile test
curl -v --resolve awx.lab.akyuz.tech:443:192.168.1.98 https://awx.lab.akyuz.tech
```

---

## 🛠️ Sorun Giderme

### Problem: Sertifika güvenilir değil hatası
**Çözüm:**
1. CA sertifikasının doğru yüklendiğini kontrol edin
2. Tarayıcıyı tamamen kapatıp açın
3. Firefox kullanıyorsanız, Firefox'a ayrıca sertifika ekleyin

### Problem: Ingress 404 hatası veriyor
**Çözüm:**
```bash
# Ingress controller çalışıyor mu?
sudo microk8s kubectl get pods -n ingress

# AWX service mevcut mu?
sudo microk8s kubectl get service awx-service -n awx

# Ingress yapılandırması doğru mu?
sudo microk8s kubectl get ingress awx-ingress -n awx -o yaml
```

### Problem: DNS çözümlenmiyor
**Çözüm:**
1. /etc/hosts dosyasını kontrol edin:
```bash
cat /etc/hosts | grep awx
```

2. Eksikse elle ekleyin:
```bash
echo "192.168.1.98 awx.lab.akyuz.tech awx.local" | sudo tee -a /etc/hosts
```

### Logları İnceleme:
Tüm işlem logları burada:
```bash
cat /awx-install/dosyalar/awx-ingress-installer-20251017-154201.log
```
