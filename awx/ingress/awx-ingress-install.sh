#!/bin/bash
# AWX Ingress & TLS Auto Installer - İyileştirilmiş v17.2
# Author: Remzi (Enhanced)
# Date: 2025-10-17
# Description: AWX için tam otomatik Ingress + TLS/SSL kurulum scripti
# Changelog v17.2:
#   - SAN dosyası oluşturma hatası düzeltildi
#   - Tekrarlanan kod blokları kaldırıldı
#   - IP doğrulama regex'leri iyileştirildi
#   - Değişken tanımlamaları eklendi
#   - Hata toleransı artırıldı

set -euo pipefail

# Renkler
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# Sabitler
AWX_NAMESPACE="awx"
WORK_DIR="$PWD/dosyalar"
LOG_FILE="$WORK_DIR/awx-ingress-installer-$(date +%Y%m%d-%H%M%S).log"
README_FILE="$WORK_DIR/README.md"

# Global değişkenler
GLOBAL_IP=""
HOST_IP=""
POD_IP=""
FULL_HOSTNAME=""
SHORT_HOSTNAME=""
AWX_DOMAIN="awx.lab.akyuz.tech"
AWX_LOCAL="awx.local"

# Dizin yapısı oluştur
mkdir -p "$WORK_DIR"/{certificates,yaml-configs,logs}

# Loglama fonksiyonları
log_info() { 
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() { 
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() { 
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() { 
    echo -e "${MAGENTA}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() { 
    echo -e "${CYAN}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

error_exit() { 
    log_error "$1"
    log_error "Detaylar için log dosyasına bakın: $LOG_FILE"
    echo ""
    echo -e "${RED}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║  HATA OLUŞTU - İşlem durduruldu                           ║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Sorun giderme için:${NC}"
    echo -e "  1. Log dosyasını inceleyin: ${CYAN}$LOG_FILE${NC}"
    echo -e "  2. AWX pod'larını kontrol edin: ${CYAN}sudo microk8s kubectl get pods -n awx${NC}"
    echo -e "  3. Ingress durumunu kontrol edin: ${CYAN}sudo microk8s kubectl get ingress -n awx${NC}"
    exit 1
}

# IP adresi doğrulama fonksiyonu
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        if [[ $i1 -le 255 && $i2 -le 255 && $i3 -le 255 && $i4 -le 255 ]]; then
            return 0
        fi
    fi
    return 1
}

# Banner
show_banner() {
    clear
    echo -e "${MAGENTA}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║       AWX Ingress & TLS/SSL Otomatik Kurulum Scripti          ║"
    echo "║                   Version 17.2 - Enhanced                      ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Ön kontroller
pre_flight_checks() {
    log_step "Ön kontroller yapılıyor..."
    
    # MicroK8s kontrolü
    if ! command -v microk8s &> /dev/null; then
        error_exit "MicroK8s bulunamadı. Lütfen önce MicroK8s kurun."
    fi
    log_info "✓ MicroK8s mevcut"
    
    # AWX namespace kontrolü
    if ! sudo microk8s kubectl get namespace "$AWX_NAMESPACE" &> /dev/null; then
        error_exit "AWX namespace bulunamadı. AWX kurulu değil."
    fi
    log_info "✓ AWX namespace mevcut"
    
    # AWX pod kontrolü
    POD_COUNT=$(sudo microk8s kubectl get pods -n "$AWX_NAMESPACE" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$POD_COUNT" -lt 2 ]]; then
        log_warn "AWX pod'ları çalışmıyor veya tam hazır değil. Devam ediliyor..."
    else
        log_info "✓ AWX pod'ları çalışıyor ($POD_COUNT pod aktif)"
    fi
    
    # AWX service kontrolü
    if ! sudo microk8s kubectl get service awx-service -n "$AWX_NAMESPACE" &> /dev/null; then
        error_exit "awx-service bulunamadı. AWX servisi çalışmıyor."
    fi
    log_info "✓ AWX service mevcut"
    
    log_success "Tüm ön kontroller başarılı!"
    echo ""
}

# IP adreslerini topla
collect_ip_addresses() {
    log_step "IP adresleri toplanıyor..."
    
    # Global/Public IP - Doğrulama ile
    echo ""
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    read -rp "🌍 Global/Public IP adresinizi girin (örn: 203.0.113.45): " GLOBAL_IP
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    
    # IP formatını doğrula
    if ! validate_ip "$GLOBAL_IP"; then
        error_exit "Geçersiz IP adresi formatı! Lütfen geçerli bir IPv4 adresi girin (örn: 203.0.113.45)"
    fi
    
    log_info "Global IP: $GLOBAL_IP"
    
    # Host IP - Doğrulama ile
    HOST_IP=$(hostname -I | awk '{print $1}')
    if [[ -z "$HOST_IP" ]] || ! validate_ip "$HOST_IP"; then
        HOST_IP="127.0.0.1"
        log_warn "Host IP alınamadı, varsayılan kullanılıyor: $HOST_IP"
    fi
    log_info "Host IP: $HOST_IP"
    
    # Hostname - Doğrulama ile
    FULL_HOSTNAME=$(hostname -f 2>/dev/null || hostname)
    SHORT_HOSTNAME=$(hostname -s 2>/dev/null || hostname | cut -d'.' -f1)
    
    # Hostname'lerde boşluk veya geçersiz karakter kontrolü
    FULL_HOSTNAME=$(echo "$FULL_HOSTNAME" | tr -d '[:space:]')
    SHORT_HOSTNAME=$(echo "$SHORT_HOSTNAME" | tr -d '[:space:]')
    
    [[ -z "$FULL_HOSTNAME" ]] && FULL_HOSTNAME="awx.local"
    [[ -z "$SHORT_HOSTNAME" ]] && SHORT_HOSTNAME="awx"
    
    log_info "Hostname: $FULL_HOSTNAME (kısa: $SHORT_HOSTNAME)"
    
    # Pod IP - Daha güvenli yöntem ile al
    log_info "Pod IP adresi alınıyor..."
    POD_IP=$(sudo microk8s kubectl get pods -n "$AWX_NAMESPACE" -o jsonpath='{.items[?(@.metadata.name contains "awx-web")].status.podIP}' 2>/dev/null | awk '{print $1}')
    
    # awx-web yoksa awx-task'ı dene
    if [[ -z "$POD_IP" ]] || ! validate_ip "$POD_IP"; then
        POD_IP=$(sudo microk8s kubectl get pods -n "$AWX_NAMESPACE" -o jsonpath='{.items[?(@.metadata.name contains "awx-task")].status.podIP}' 2>/dev/null | awk '{print $1}')
    fi
    
    # Hala geçersizse varsayılan değer kullan
    if [[ -z "$POD_IP" ]] || ! validate_ip "$POD_IP"; then
        POD_IP="10.1.0.1"
        log_warn "Pod IP alınamadı, varsayılan kullanılıyor: $POD_IP"
    fi
    
    log_info "Pod IP: $POD_IP"
    
    echo ""
    log_info "Toplanan ve doğrulanan bilgiler:"
    echo -e "  ${CYAN}Global IP:${NC}      $GLOBAL_IP"
    echo -e "  ${CYAN}Host IP:${NC}        $HOST_IP"
    echo -e "  ${CYAN}Pod IP:${NC}         $POD_IP"
    echo -e "  ${CYAN}Full Hostname:${NC}  $FULL_HOSTNAME"
    echo -e "  ${CYAN}Short Hostname:${NC} $SHORT_HOSTNAME"
    echo -e "  ${CYAN}Domain:${NC}         $AWX_DOMAIN"
    
    # Son kontrol - tüm IP'lerin geçerliliğini doğrula
    for ip_check in "$GLOBAL_IP" "$HOST_IP" "$POD_IP"; do
        if ! validate_ip "$ip_check"; then
            error_exit "Geçersiz IP adresi tespit edildi: $ip_check"
        fi
    done
    
    log_success "✓ Tüm IP adresleri doğrulandı"
    echo ""
}

# Ingress addon'u etkinleştir ve kontrol et
enable_ingress_addon() {
    log_step "MicroK8s Ingress addon kontrol ediliyor..."
    
    if ! sudo microk8s status | grep -q "ingress: enabled"; then
        log_info "Ingress addon etkinleştiriliyor..."
        sudo microk8s enable ingress >> "$LOG_FILE" 2>&1 || error_exit "Ingress addon etkinleştirilemedi"
        log_info "Ingress controller'ın başlaması bekleniyor (90 saniye)..."
        sleep 90
    else
        log_info "✓ Ingress addon zaten etkin"
        sleep 5
    fi
    
    # Ingress namespace'ini kontrol et
    if ! sudo microk8s kubectl get namespace ingress &> /dev/null; then
        log_warn "Ingress namespace bulunamadı, oluşturuluyor..."
        sudo microk8s kubectl create namespace ingress >> "$LOG_FILE" 2>&1
    fi
    
    # Ingress controller pod'larını kontrol et
    log_info "Ingress controller pod'ları kontrol ediliyor..."
    INGRESS_POD_COUNT=0
    for i in {1..30}; do
        INGRESS_POD_COUNT=$(sudo microk8s kubectl get pods -n ingress --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [[ "$INGRESS_POD_COUNT" -gt 0 ]]; then
            log_success "✓ Ingress controller çalışıyor ($INGRESS_POD_COUNT pod)"
            break
        fi
        if [[ $i -lt 30 ]]; then
            log_info "Bekleniyor... ($i/30)"
            sleep 3
        fi
    done
    
    if [[ "$INGRESS_POD_COUNT" -eq 0 ]]; then
        log_warn "Ingress controller pod'ları henüz hazır değil, ancak devam ediliyor..."
        log_warn "Manuel kontrol için: sudo microk8s kubectl get pods -n ingress"
    fi
    
    # Ingress controller deployment kontrolü (alternatif isimler)
    log_info "Ingress controller deployment kontrol ediliyor..."
    DEPLOYMENT_FOUND=false
    
    for deploy_name in "nginx-ingress-microk8s-controller" "ingress-nginx-controller" "nginx-ingress-controller"; do
        if sudo microk8s kubectl get deployment "$deploy_name" -n ingress &> /dev/null; then
            log_info "Deployment bulundu: $deploy_name"
            if sudo microk8s kubectl wait --for=condition=available deployment/"$deploy_name" -n ingress --timeout=60s >> "$LOG_FILE" 2>&1; then
                log_success "✓ Ingress controller deployment hazır!"
                DEPLOYMENT_FOUND=true
                break
            else
                log_warn "Deployment henüz hazır değil: $deploy_name"
            fi
        fi
    done
    
    if [[ "$DEPLOYMENT_FOUND" == false ]]; then
        log_warn "Bilinen ingress controller deployment bulunamadı, ancak devam ediliyor..."
        sudo microk8s kubectl get deployments -n ingress >> "$LOG_FILE" 2>&1 || true
    fi
    
    echo ""
}

# TLS sertifikaları oluştur
generate_tls_certificates() {
    log_step "TLS sertifikaları oluşturuluyor (SAN destekli)..."
    
    CERT_DIR="$WORK_DIR/certificates"
    CERT_CA_KEY="$CERT_DIR/local-awx-ca.key"
    CERT_CA="$CERT_DIR/local-awx-ca.crt"
    CERT_KEY="$CERT_DIR/local-awx.key"
    CERT_CSR="$CERT_DIR/local-awx.csr"
    CERT_CRT="$CERT_DIR/local-awx.crt"
    CERT_EXTFILE="$CERT_DIR/awx-extfile.cnf"
    
    # Dizin oluştur
    mkdir -p "$CERT_DIR"
    
    # CA sertifikası oluştur
    log_info "CA sertifikası oluşturuluyor..."
    openssl req -x509 -nodes -new -sha256 -days 825 -newkey rsa:2048 \
        -subj "/CN=AWX-Local-CA/O=AWX Lab/C=TR" \
        -keyout "$CERT_CA_KEY" -out "$CERT_CA" >> "$LOG_FILE" 2>&1 || error_exit "CA sertifikası oluşturulamadı"
    log_success "✓ CA sertifikası oluşturuldu"
    
    # Private key ve CSR oluştur
    log_info "Private key ve CSR oluşturuluyor..."
    openssl req -newkey rsa:2048 -nodes -keyout "$CERT_KEY" \
        -subj "/CN=$AWX_DOMAIN/O=AWX Lab/C=TR" \
        -out "$CERT_CSR" >> "$LOG_FILE" 2>&1 || error_exit "CSR oluşturulamadı"
    log_success "✓ Private key ve CSR oluşturuldu"
    
    # SAN extension dosyası oluştur
    log_info "SAN (Subject Alternative Names) yapılandırması hazırlanıyor..."
    
    cat > "$CERT_EXTFILE" <<EOF
subjectAltName = @alt_names
extendedKeyUsage = serverAuth

[alt_names]
DNS.1 = $AWX_DOMAIN
DNS.2 = $AWX_LOCAL
DNS.3 = $FULL_HOSTNAME
DNS.4 = $SHORT_HOSTNAME
DNS.5 = localhost
IP.1 = 127.0.0.1
IP.2 = $HOST_IP
IP.3 = $POD_IP
IP.4 = $GLOBAL_IP
EOF
    
    log_info "SAN içeriği:"
    cat "$CERT_EXTFILE" | tee -a "$LOG_FILE"
    echo ""
    
    # SAN dosyasını doğrula
    if ! grep -q "DNS.1" "$CERT_EXTFILE" || ! grep -q "IP.1" "$CERT_EXTFILE"; then
        error_exit "SAN dosyası düzgün oluşturulamadı"
    fi
    
    # Son sertifikayı imzala
    log_info "SSL sertifikası imzalanıyor..."
    openssl x509 -req -in "$CERT_CSR" -CA "$CERT_CA" -CAkey "$CERT_CA_KEY" \
        -CAcreateserial -out "$CERT_CRT" -days 825 -sha256 \
        -extfile "$CERT_EXTFILE" >> "$LOG_FILE" 2>&1 || error_exit "Sertifika imzalanamadı"
    
    log_success "✓ TLS sertifikası başarıyla oluşturuldu"
    
    # Sertifika detaylarını göster
    log_info "Sertifika detayları:"
    openssl x509 -in "$CERT_CRT" -text -noout | grep -A 10 "Subject Alternative Name" | tee -a "$LOG_FILE"
    echo ""
    
    # Dosya izinlerini ayarla
    chmod 600 "$CERT_KEY" "$CERT_CA_KEY"
    chmod 644 "$CERT_CRT" "$CERT_CA"
    
    log_success "Sertifika dosyaları: $CERT_DIR"
}

# Kubernetes secret oluştur
create_tls_secret() {
    log_step "Kubernetes TLS secret oluşturuluyor..."
    
    # Mevcut secret'ı sil (varsa)
    if sudo microk8s kubectl get secret awx-tls -n "$AWX_NAMESPACE" &> /dev/null; then
        log_info "Mevcut TLS secret siliniyor..."
        sudo microk8s kubectl delete secret awx-tls -n "$AWX_NAMESPACE" >> "$LOG_FILE" 2>&1
    fi
    
    # Yeni secret oluştur
    log_info "Yeni TLS secret oluşturuluyor..."
    sudo microk8s kubectl create secret tls awx-tls \
        --cert="$WORK_DIR/certificates/local-awx.crt" \
        --key="$WORK_DIR/certificates/local-awx.key" \
        -n "$AWX_NAMESPACE" >> "$LOG_FILE" 2>&1 || error_exit "TLS secret oluşturulamadı"
    
    log_success "✓ TLS secret başarıyla oluşturuldu"
    
    # Secret'ı doğrula
    log_info "Secret doğrulanıyor..."
    sudo microk8s kubectl get secret awx-tls -n "$AWX_NAMESPACE" -o yaml >> "$LOG_FILE" 2>&1
    echo ""
}

# Ingress yapılandırması oluştur
create_ingress_config() {
    log_step "Ingress yapılandırması oluşturuluyor..."
    
    INGRESS_YAML="$WORK_DIR/yaml-configs/awx-ingress.yaml"
    
    cat > "$INGRESS_YAML" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: awx-ingress
  namespace: $AWX_NAMESPACE
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTP"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - $AWX_DOMAIN
    - $AWX_LOCAL
    secretName: awx-tls
  rules:
  - host: $AWX_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: awx-service
            port:
              number: 80
  - host: $AWX_LOCAL
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: awx-service
            port:
              number: 80
EOF
    
    log_info "Ingress YAML dosyası oluşturuldu: $INGRESS_YAML"
    
    # Mevcut ingress'i sil (varsa)
    if sudo microk8s kubectl get ingress awx-ingress -n "$AWX_NAMESPACE" &> /dev/null; then
        log_info "Mevcut ingress siliniyor..."
        sudo microk8s kubectl delete ingress awx-ingress -n "$AWX_NAMESPACE" >> "$LOG_FILE" 2>&1
    fi
    
    # Ingress'i uygula
    log_info "Ingress uygulanıyor..."
    sudo microk8s kubectl apply -f "$INGRESS_YAML" >> "$LOG_FILE" 2>&1 || error_exit "Ingress uygulanamadı"
    
    log_success "✓ Ingress başarıyla oluşturuldu"
    
    # Ingress'in hazır olmasını bekle
    log_info "Ingress'in hazır olması bekleniyor (10 saniye)..."
    sleep 10
    echo ""
}

# Ingress durumunu kontrol et
verify_ingress() {
    log_step "Ingress durumu kontrol ediliyor..."
    
    echo ""
    log_info "Ingress detayları:"
    sudo microk8s kubectl get ingress -n "$AWX_NAMESPACE" -o wide | tee -a "$LOG_FILE"
    echo ""
    
    log_info "Ingress tam bilgi:"
    sudo microk8s kubectl describe ingress awx-ingress -n "$AWX_NAMESPACE" >> "$LOG_FILE" 2>&1
    
    log_success "✓ Ingress başarıyla yapılandırıldı"
}

# /etc/hosts dosyasını güncelle
update_hosts_file() {
    log_step "/etc/hosts dosyası güncelleniyor..."
    
    # Mevcut girişleri kontrol et
    if grep -q "$AWX_DOMAIN" /etc/hosts; then
        log_info "✓ $AWX_DOMAIN zaten /etc/hosts dosyasında mevcut"
    else
        log_info "$AWX_DOMAIN /etc/hosts dosyasına ekleniyor..."
        echo "$HOST_IP $AWX_DOMAIN" | sudo tee -a /etc/hosts >> "$LOG_FILE" 2>&1
        log_success "✓ $AWX_DOMAIN eklendi"
    fi
    
    if grep -q "$AWX_LOCAL" /etc/hosts; then
        log_info "✓ $AWX_LOCAL zaten /etc/hosts dosyasında mevcut"
    else
        log_info "$AWX_LOCAL /etc/hosts dosyasına ekleniyor..."
        echo "$HOST_IP $AWX_LOCAL" | sudo tee -a /etc/hosts >> "$LOG_FILE" 2>&1
        log_success "✓ $AWX_LOCAL eklendi"
    fi
    echo ""
}

# README oluştur
create_readme() {
    log_step "README dosyası oluşturuluyor..."
    
    cat > "$README_FILE" <<EOFREADME
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
- [ ] https://$AWX_DOMAIN erişilebilir
- [ ] https://$AWX_LOCAL erişilebilir
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
\`\`\`
$WORK_DIR/certificates/local-awx-ca.crt
\`\`\`

#### Ubuntu/Debian için:
\`\`\`bash
sudo cp $WORK_DIR/certificates/local-awx-ca.crt /usr/local/share/ca-certificates/awx-local-ca.crt
sudo update-ca-certificates
\`\`\`

#### RHEL/Rocky/CentOS için:
\`\`\`bash
sudo cp $WORK_DIR/certificates/local-awx-ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
\`\`\`

#### Windows için:
1. \`local-awx-ca.crt\` dosyasına çift tıklayın
2. "Install Certificate" butonuna tıklayın
3. "Local Machine" seçin
4. "Place all certificates in the following store" seçin
5. "Trusted Root Certification Authorities" seçin
6. Kurulumu tamamlayın

#### macOS için:
\`\`\`bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $WORK_DIR/certificates/local-awx-ca.crt
\`\`\`

#### Firefox için (ayrı sertifika deposu kullanır):
1. Firefox > Settings > Privacy & Security
2. "View Certificates" butonuna tıklayın
3. "Authorities" sekmesine gidin
4. "Import" ile CA sertifikasını ekleyin
5. "Trust this CA to identify websites" seçeneğini işaretleyin

---

## 🔍 Erişim Kontrolleri

### Ingress Durumunu Kontrol Etme:
\`\`\`bash
# Ingress listesi
sudo microk8s kubectl get ingress -n awx

# Detaylı bilgi
sudo microk8s kubectl describe ingress awx-ingress -n awx

# Ingress controller logları
sudo microk8s kubectl logs -n ingress -l app.kubernetes.io/name=ingress-nginx
\`\`\`

### AWX Servislerini Kontrol Etme:
\`\`\`bash
# Tüm podlar
sudo microk8s kubectl get pods -n awx

# Servisler
sudo microk8s kubectl get services -n awx

# AWX web pod logları
sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-web

# AWX task pod logları
sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-task
\`\`\`

### Sertifika Bilgilerini Görüntüleme:
\`\`\`bash
# Sertifika içeriği
openssl x509 -in $WORK_DIR/certificates/local-awx.crt -text -noout

# SAN listesi
openssl x509 -in $WORK_DIR/certificates/local-awx.crt -text -noout | grep -A 10 "Subject Alternative Name"

# Geçerlilik tarihleri
openssl x509 -in $WORK_DIR/certificates/local-awx.crt -noout -dates
\`\`\`

### HTTPS Erişimi Test Etme:
\`\`\`bash
# curl ile test (sertifika doğrulama ile)
curl -v https://$AWX_DOMAIN

# curl ile test (sertifika doğrulama olmadan)
curl -k -v https://$AWX_DOMAIN

# Specific IP ile test
curl -v --resolve $AWX_DOMAIN:443:$HOST_IP https://$AWX_DOMAIN
\`\`\`

---

## 🛠️ Sorun Giderme

### Problem: Sertifika güvenilir değil hatası
**Çözüm:**
1. CA sertifikasının doğru yüklendiğini kontrol edin
2. Tarayıcıyı tamamen kapatıp açın
3. Firefox kullanıyorsanız, Firefox'a ayrıca sertifika ekleyin

### Problem: Ingress 404 hatası veriyor
**Çözüm:**
\`\`\`bash
# Ingress controller çalışıyor mu?
sudo microk8s kubectl get pods -n ingress

# AWX service mevcut mu?
sudo microk8s kubectl get service awx-service -n awx

# Ingress yapılandırması doğru mu?
sudo microk8s kubectl get ingress awx-ingress -n awx -o yaml
\`\`\`

### Problem: DNS çözümlenmiyor
**Çözüm:**
1. /etc/hosts dosyasını kontrol edin:
\`\`\`bash
cat /etc/hosts | grep awx
\`\`\`

2. Eksikse elle ekleyin:
\`\`\`bash
echo "$HOST_IP $AWX_DOMAIN $AWX_LOCAL" | sudo tee -a /etc/hosts
\`\`\`

### Logları İnceleme:
Tüm işlem logları burada:
\`\`\`bash
cat $LOG_FILE
\`\`\`
EOFREADME
    
    log_success "✓ README.md oluşturuldu: $README_FILE"
}

# Özet rapor göster
show_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║          🎉 KURULUM BAŞARIYLA TAMAMLANDI! 🎉                  ║${NC}"
    echo -e "${GREEN}║                    Version 17.2                                ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${CYAN}📦 Oluşturulan Dosyalar:${NC}"
    echo -e "  ${YELLOW}Sertifikalar:${NC}      $WORK_DIR/certificates/"
    echo -e "  ${YELLOW}YAML Configs:${NC}      $WORK_DIR/yaml-configs/"
    echo -e "  ${YELLOW}Log Dosyası:${NC}       $LOG_FILE"
    echo -e "  ${YELLOW}README:${NC}            $README_FILE"
    echo ""
    
    echo -e "${CYAN}🔐 TLS/SSL Bilgileri:${NC}"
    echo -e "  ${YELLOW}CA Sertifika:${NC}      $WORK_DIR/certificates/local-awx-ca.crt"
    echo -e "  ${YELLOW}Server Sertifika:${NC}  $WORK_DIR/certificates/local-awx.crt"
    echo -e "  ${YELLOW}Private Key:${NC}       $WORK_DIR/certificates/local-awx.key"
    echo ""
    
    echo -e "${CYAN}🌐 Erişim URL'leri:${NC}"
    echo -e "  ${GREEN}HTTPS (Domain):${NC}     https://$AWX_DOMAIN"
    echo -e "  ${GREEN}HTTPS (Local):${NC}      https://$AWX_LOCAL"
    echo ""
    
    echo -e "${CYAN}📋 Sonraki Adımlar:${NC}"
    echo -e "  1. ${YELLOW}CA sertifikasını sisteminize yükleyin${NC}"
    echo -e "  2. ${YELLOW}Tarayıcınızda URL'leri test edin${NC}"
    echo -e "  3. ${YELLOW}README.md dosyasını okuyun${NC}"
    echo ""
    
    echo -e "${MAGENTA}⚠️  ÖNEMLİ:${NC} CA sertifikasını yüklemeden HTTPS bağlantıları güvenilir olmayacaktır!"
    echo ""
    
    # Son kontrol - Ingress durumu
    log_step "Son durum kontrolü..."
    echo ""
    echo -e "${CYAN}Ingress Durumu:${NC}"
    sudo microk8s kubectl get ingress -n "$AWX_NAMESPACE" -o wide 2>/dev/null || log_warn "Ingress durumu alınamadı"
    echo ""
    
    echo -e "${CYAN}AWX Pod Durumu:${NC}"
    sudo microk8s kubectl get pods -n "$AWX_NAMESPACE" 2>/dev/null || log_warn "Pod durumu alınamadı"
    echo ""
    
    log_success "Kurulum tamamlandı! Detaylı bilgi için README.md dosyasını okuyun."
}

# Ana fonksiyon
main() {
    show_banner
    pre_flight_checks
    collect_ip_addresses
    enable_ingress_addon
    generate_tls_certificates
    create_tls_secret
    create_ingress_config
    verify_ingress
    update_hosts_file
    create_readme
    show_summary
}

# Script başlatma
main "$@"