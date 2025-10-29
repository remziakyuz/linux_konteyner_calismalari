#!/bin/bash
# vm-autostart.sh - Proxmox VM otomatik başlatma yönetim scripti

# Renkli çıktı için
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Kullanım bilgisi
usage() {
    echo -e "${BLUE}Kullanım:${NC}"
    echo "  $0 <işlem> <vm-id>"
    echo "  $0 <işlem> <start-id>-<end-id>"
    echo ""
    echo -e "${BLUE}İşlemler:${NC}"
    echo "  check     - Otomatik başlatma durumunu kontrol et"
    echo "  enable    - Otomatik başlatmayı aktifleştir"
    echo "  disable   - Otomatik başlatmayı devre dışı bırak"
    echo ""
    echo -e "${BLUE}Örnekler:${NC}"
    echo "  $0 check 120              # VM 120'nin durumunu kontrol et"
    echo "  $0 enable 120-139         # VM 120-139 arası aktifleştir"
    echo "  $0 disable 120            # VM 120'yi devre dışı bırak"
    exit 1
}

# Parametre kontrolü
if [ $# -lt 2 ]; then
    echo -e "${RED}Hata: Yeterli parametre belirtilmedi!${NC}"
    usage
fi

ACTION=$1
PARAM=$2

# İşlem türü kontrolü
if [[ ! "$ACTION" =~ ^(check|enable|disable)$ ]]; then
    echo -e "${RED}Hata: Geçersiz işlem! (check, enable veya disable kullanın)${NC}"
    usage
fi

# VM durumunu kontrol eden fonksiyon
check_autostart() {
    local vmid=$1
    
    if qm status $vmid &>/dev/null; then
        ONBOOT=$(qm config $vmid 2>/dev/null | grep "onboot:" | awk '{print $2}')
        VM_NAME=$(qm config $vmid 2>/dev/null | grep "name:" | awk '{print $2}')
        
        if [ "$ONBOOT" == "1" ]; then
            echo -e "${GREEN}✓${NC} VM $vmid ${VM_NAME:+($VM_NAME)}: Otomatik başlatma ${GREEN}AÇIK${NC}"
        else
            echo -e "${YELLOW}○${NC} VM $vmid ${VM_NAME:+($VM_NAME)}: Otomatik başlatma ${YELLOW}KAPALI${NC}"
        fi
    else
        echo -e "${RED}✗${NC} VM $vmid: Mevcut değil"
    fi
}

# Otomatik başlatmayı aktifleştiren fonksiyon
enable_autostart() {
    local vmid=$1
    
    if qm status $vmid &>/dev/null; then
        qm set $vmid --onboot 1 &>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓${NC} VM $vmid: Otomatik başlatma ${GREEN}aktifleştirildi${NC}"
        else
            echo -e "${RED}✗${NC} VM $vmid: Hata oluştu"
        fi
    else
        echo -e "${YELLOW}○${NC} VM $vmid: Mevcut değil, atlanıyor"
    fi
}

# Otomatik başlatmayı devre dışı bırakan fonksiyon
disable_autostart() {
    local vmid=$1
    
    if qm status $vmid &>/dev/null; then
        qm set $vmid --onboot 0 &>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${YELLOW}✓${NC} VM $vmid: Otomatik başlatma ${YELLOW}devre dışı bırakıldı${NC}"
        else
            echo -e "${RED}✗${NC} VM $vmid: Hata oluştu"
        fi
    else
        echo -e "${YELLOW}○${NC} VM $vmid: Mevcut değil, atlanıyor"
    fi
}

# İşlem başlığı
case $ACTION in
    check)
        ACTION_TEXT="Durumu kontrol ediliyor"
        ;;
    enable)
        ACTION_TEXT="Otomatik başlatma aktifleştiriliyor"
        ;;
    disable)
        ACTION_TEXT="Otomatik başlatma devre dışı bırakılıyor"
        ;;
esac

# Parametre işleme
if [[ $PARAM =~ ^([0-9]+)-([0-9]+)$ ]]; then
    # Aralık formatı (örn: 120-139)
    START_ID=${BASH_REMATCH[1]}
    END_ID=${BASH_REMATCH[2]}
    
    echo -e "${BLUE}$ACTION_TEXT (ID: $START_ID - $END_ID)${NC}"
    echo "========================================================"
    
    for vmid in $(seq $START_ID $END_ID); do
        case $ACTION in
            check)
                check_autostart $vmid
                ;;
            enable)
                enable_autostart $vmid
                ;;
            disable)
                disable_autostart $vmid
                ;;
        esac
    done
    
elif [[ $PARAM =~ ^[0-9]+$ ]]; then
    # Tek ID formatı (örn: 120)
    echo -e "${BLUE}$ACTION_TEXT (ID: $PARAM)${NC}"
    echo "========================================================"
    
    case $ACTION in
        check)
            check_autostart $PARAM
            ;;
        enable)
            enable_autostart $PARAM
            ;;
        disable)
            disable_autostart $PARAM
            ;;
    esac
    
else
    echo -e "${RED}Hata: Geçersiz VM ID formatı!${NC}"
    usage
fi

echo "========================================================"
echo -e "${GREEN}İşlem tamamlandı!${NC}"
