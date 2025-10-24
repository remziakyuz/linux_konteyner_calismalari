#!/bin/bash
# =====================================================
#  Proxmox VM Yönetim Scripti
#  Hazırlayan: Remzi Akyuz için özel sürüm
#  Versiyon: 3.0 (snapshot + range + yardım desteği)
# =====================================================

# ------------------------------
# Genel Ayarlar
# ------------------------------
PVE_NODES=("hl06" "py06")  # Cluster node'ları (gerekirse ekle)
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
RESET="\e[0m"

# ------------------------------
# Yardımcı Fonksiyonlar
# ------------------------------

usage() {
    echo -e "${YELLOW}Kullanım:${RESET}"
    echo "  $0 start <vmid|range|name>                → VM veya ID aralığını başlat"
    echo "  $0 stop <vmid|range|name>                 → VM veya ID aralığını durdur"
    echo "  $0 snap-create <vmid|name> <snap>         → Snapshot oluştur"
    echo "  $0 snap-list <vmid|name>                  → Snapshot listesi"
    echo "  $0 snap-rollback <vmid|name> <snap>       → Snapshot'a geri dön"
    echo "  $0 snap-delete <vmid|name> <snap>         → Snapshot sil"
    echo ""
    echo -e "${YELLOW}Örnekler:${RESET}"
    echo "  $0 start 110-120"
    echo "  $0 stop s05.akyuz.tech"
    echo "  $0 snap-create 110 pre-upgrade"
    echo "  $0 snap-list 110"
    echo "  $0 snap-rollback 110 pre-upgrade"
    echo "  $0 snap-delete 110 pre-upgrade"
    echo ""
}

error_exit() {
    echo -e "${RED}Hata:${RESET} $1"
    echo ""
    usage
    exit 1
}

# VMID bul (isim veya ID)
get_vmid() {
    local input="$1"
    if [[ "$input" =~ ^[0-9]+$ ]]; then
        echo "$input"
    else
        id=$(qm list | awk -v name="$input" '$2 == name {print $1}')
        echo "$id"
    fi
}

# ID aralığını genişlet (ör: 110-120)
expand_range() {
    local range="$1"
    if [[ "$range" =~ ^[0-9]+-[0-9]+$ ]]; then
        seq ${range%-*} ${range#*-}
    else
        echo "$range"
    fi
}

# VM başlat
start_vm() {
    [[ -z "$1" ]] && error_exit "start komutu için VMID veya aralık gerekli!"
    for id in $(expand_range "$1"); do
        echo -e "▶️  ${YELLOW}VM $id başlatılıyor...${RESET}"
        qm start "$id" 2>/dev/null && echo -e "${GREEN}✅ VM $id başlatıldı.${RESET}" || echo -e "${RED}⚠️  VM $id başlatılamadı.${RESET}"
        sleep 1
    done
}

# VM durdur
stop_vm() {
    [[ -z "$1" ]] && error_exit "stop komutu için VMID veya aralık gerekli!"
    for id in $(expand_range "$1"); do
        echo -e "⏹️  ${YELLOW}VM $id durduruluyor...${RESET}"
        qm stop "$id" 2>/dev/null && echo -e "${GREEN}✅ VM $id durduruldu.${RESET}" || echo -e "${RED}⚠️  VM $id durdurulamadı.${RESET}"
        sleep 1
    done
}

# Snapshot oluştur
snap_create() {
    vmid=$(get_vmid "$1")
    snapname="$2"
    [[ -z "$vmid" || -z "$snapname" ]] && error_exit "Kullanım: snap-create <vmid|name> <snapshot_name>"
    echo -e "📸 ${YELLOW}Snapshot alınıyor: $snapname (VM $vmid)...${RESET}"
    qm snapshot "$vmid" "$snapname" --description "Oluşturuldu $(date '+%Y-%m-%d %H:%M:%S')" &&
        echo -e "${GREEN}✅ Snapshot başarıyla oluşturuldu.${RESET}" || echo -e "${RED}⚠️ Snapshot oluşturulamadı.${RESET}"
}

# Snapshot listele
snap_list() {
    vmid=$(get_vmid "$1")
    [[ -z "$vmid" ]] && error_exit "Kullanım: snap-list <vmid|name>"
    echo -e "📋 ${YELLOW}Snapshot listesi (VM $vmid):${RESET}"
    qm listsnapshot "$vmid"
}

# Snapshot'tan geri dön
snap_rollback() {
    vmid=$(get_vmid "$1")
    snapname="$2"
    [[ -z "$vmid" || -z "$snapname" ]] && error_exit "Kullanım: snap-rollback <vmid|name> <snapshot_name>"
    echo -e "↩️  ${YELLOW}Snapshot'a geri dönülüyor: $snapname (VM $vmid)...${RESET}"
    qm rollback "$vmid" "$snapname" &&
        echo -e "${GREEN}✅ Snapshot geri yüklendi.${RESET}" || echo -e "${RED}⚠️ Snapshot geri yüklenemedi.${RESET}"
}

# Snapshot sil
snap_delete() {
    vmid=$(get_vmid "$1")
    snapname="$2"
    [[ -z "$vmid" || -z "$snapname" ]] && error_exit "Kullanım: snap-delete <vmid|name> <snapshot_name>"
    echo -e "🗑️  ${YELLOW}Snapshot siliniyor: $snapname (VM $vmid)...${RESET}"
    qm delsnapshot "$vmid" "$snapname" &&
        echo -e "${GREEN}✅ Snapshot silindi.${RESET}" || echo -e "${RED}⚠️ Snapshot silinemedi.${RESET}"
}

# ------------------------------
# Komut Yönlendirme
# ------------------------------
case "$1" in
    start)
        start_vm "$2"
        ;;
    stop)
        stop_vm "$2"
        ;;
    snap-create)
        snap_create "$2" "$3"
        ;;
    snap-list)
        snap_list "$2"
        ;;
    snap-rollback)
        snap_rollback "$2" "$3"
        ;;
    snap-delete)
        snap_delete "$2" "$3"
        ;;
    ""|help|-h|--help)
        usage
        ;;
    *)
        error_exit "Bilinmeyen komut: $1"
        ;;
esac

