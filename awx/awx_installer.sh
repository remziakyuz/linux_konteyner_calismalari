#!/bin/bash

# AWX Auto Installer Script for Ubuntu 24.04 LTS - ADVANCED VERSION
# Production Ready - Enhanced with PV, Monitoring & Recovery
# MicroK8s with AWX Operator 2.19.1
# Enhanced by Remzi AKYUZ
# remzi@akyuz.tech

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Variables
AWX_OPERATOR_VERSION="2.19.1"
AWX_NAMESPACE="awx"
KUBECTL_VERSION="1.30.0"
MICROK8S_CHANNEL="1.30/stable"

# Enhanced directory structure
DATA_ROOT="/mnt/data"
LOG_DIR="${DATA_ROOT}/log"
ARCHIVE_DIR="${DATA_ROOT}/arsiv"
PV_DIR="${DATA_ROOT}/pv_awx"
PV_SIZE="40Gi"

# Create timestamp for this run
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/awx-installer-${TIMESTAMP}.log"
MAIN_LOG="${LOG_DIR}/awx-main.log"

# Installation mode
INSTALL_MODE="fresh"  # fresh, repair, reinstall

# Get system IP
SYSTEM_IP=$(hostname -I | awk '{print $1}')
[ -z "$SYSTEM_IP" ] && SYSTEM_IP="localhost"

# Initialize directories
initialize_directories() {
    log_step "Initializing directory structure..."
    
    # Create base directories
    sudo mkdir -p "${LOG_DIR}" "${ARCHIVE_DIR}" "${PV_DIR}"
    
    # Set ownership for log and archive directories
    sudo chown -R $USER:$USER "${LOG_DIR}" "${ARCHIVE_DIR}"
    sudo chmod -R 755 "${LOG_DIR}" "${ARCHIVE_DIR}"
    
    # PostgreSQL specific permissions for PV directory
    # PostgreSQL runs as UID 26 (postgres user in container)
    log_info "Setting PostgreSQL permissions on PV directory..."
    
    # First, create the directory with proper ownership
    if [ ! -d "${PV_DIR}" ]; then
        sudo mkdir -p "${PV_DIR}"
    fi
    
    # Set ownership to postgres user (UID:26, GID:26)
    # This is critical for PostgreSQL to work properly
    sudo chown -R 26:26 "${PV_DIR}"
    
    # Set directory permissions to 700 (rwx------)
    # PostgreSQL requires strict permissions on data directory
    sudo chmod 700 "${PV_DIR}"
    
    log_success "PV directory permissions set (Owner: 26:26, Mode: 700)"
    
    # Create log file
    touch "$LOG_FILE"
    
    # Link to main log
    if [ ! -f "$MAIN_LOG" ]; then
        ln -sf "$LOG_FILE" "$MAIN_LOG"
    fi
    
    # Verify permissions
    log_debug "Directory structure verification:"
    log_debug "  Log dir:     $(ls -ld ${LOG_DIR} | awk '{print $1, $3, $4}')"
    log_debug "  Archive dir: $(ls -ld ${ARCHIVE_DIR} | awk '{print $1, $3, $4}')"
    log_debug "  PV dir:      $(ls -ld ${PV_DIR} | awk '{print $1, $3, $4}')"
    
    log_success "Directory structure initialized"
    log_info "Log directory: ${LOG_DIR}"
    log_info "Archive directory: ${ARCHIVE_DIR}"
    log_info "PV directory: ${PV_DIR} (PostgreSQL ready)"
}

# Enhanced logging functions with file and console output
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${GREEN}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
}

log_warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1"
    echo -e "${YELLOW}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
}

log_debug() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $1"
    echo -e "${BLUE}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
}

log_success() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
    echo -e "${MAGENTA}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
}

log_step() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $1"
    echo -e "${CYAN}${msg}${NC}"
    echo "${msg}" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Installation failed! Check log file: $LOG_FILE"
    log_error "Main log available at: $MAIN_LOG"
    cleanup_on_error
    exit 1
}

cleanup_on_error() {
    log_warn "Cleaning up after error..."
    # Keep archive files for debugging
    rm -f /tmp/awx-*.yaml 2>/dev/null || true
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --reinstall)
                INSTALL_MODE="reinstall"
                log_info "Mode: Reinstall (will remove existing AWX installation)"
                shift
                ;;
            --repair)
                INSTALL_MODE="repair"
                log_info "Mode: Repair (will fix existing installation)"
                shift
                ;;
            --fresh)
                INSTALL_MODE="fresh"
                log_info "Mode: Fresh installation"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
AWX Advanced Installer - Usage

Options:
  --fresh      Fresh installation (default)
  --reinstall  Remove and reinstall AWX completely
  --repair     Repair existing installation
  --help       Show this help message

Examples:
  $0                  # Fresh installation
  $0 --reinstall      # Remove and reinstall
  $0 --repair         # Fix existing installation

EOF
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo -e "${RED}This script should not be run as root. Run as a regular user with sudo privileges.${NC}"
    exit 1
fi

# Initialize before logging
if [ ! -d "$DATA_ROOT" ]; then
    sudo mkdir -p "${LOG_DIR}" "${ARCHIVE_DIR}" "${PV_DIR}"
    sudo chown -R $USER:$USER "${DATA_ROOT}"
fi

# Ensure log directory exists before any logging
mkdir -p "${LOG_DIR}"
touch "$LOG_FILE"

print_banner() {
    clear
    echo -e "${MAGENTA}===========================================================${NC}"
    echo -e "${GREEN}   🚀 AWX Advanced Installer - Production Ready${NC}"
    echo -e "${CYAN}   STRICTLY for Ubuntu 24.04 LTS | MicroK8s${NC}"
    echo -e "${CYAN}   AWX Operator: $AWX_OPERATOR_VERSION${NC}"
    echo -e "${CYAN}   Installation Mode: $INSTALL_MODE${NC}"
    echo -e "${MAGENTA}===========================================================${NC}"
    echo
    echo -e "${YELLOW}⚠️  System Requirements:${NC}"
    echo "   • Operating System: Ubuntu 24.04 LTS (REQUIRED)"
    echo "   • CPU Cores:        4+ cores (Recommended)"
    echo "   • RAM:              8GB+ (Recommended)"
    echo "   • Disk Space:       50GB+ free on /mnt/data partition (Recommended)"
    echo "   •                   (40GB PV + 10GB for logs/archives/system)"
    echo "   • Internet:         Active connection (Required)"
    echo
    echo -e "${CYAN}📂 Data Directories:${NC}"
    echo "   • Logs:      ${LOG_DIR}"
    echo "   • Archive:   ${ARCHIVE_DIR}"
    echo "   • PV Data:   ${PV_DIR}"
    echo
    log_info "Installation log: $LOG_FILE"
    log_info "System IP: $SYSTEM_IP"
    echo
}

# Pre-flight checks and package installation
install_essential_packages() {
    log_step "Installing essential packages..."
    
    local packages=(
        "iputils-ping"
        "net-tools"
        "curl"
        "wget"
        "git"
        "apt-transport-https"
        "ca-certificates"
        "software-properties-common"
        "gnupg"
        "lsb-release"
        "jq"
        "htop"
        "iotop"
        "sysstat"
        "dnsutils"
    )
    
    log_info "Updating package lists..."
    sudo apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Failed to update package lists"
    
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            log_info "Installing $package..."
            sudo apt-get install -y "$package" >> "$LOG_FILE" 2>&1 || log_warn "Failed to install $package (non-critical)"
        else
            log_debug "$package already installed"
        fi
    done
    
    log_success "Essential packages installed"
}

# Pre-installation tests
run_preflight_tests() {
    log_step "Running pre-flight tests..."
    
    local test_failed=0
    
    # Test 1: Network connectivity
    log_info "Test 1/7: Network connectivity..."
    if ping -c 3 8.8.8.8 >> "$LOG_FILE" 2>&1; then
        log_success "✓ Internet connectivity OK"
    else
        log_error "✗ No internet connectivity"
        test_failed=1
    fi
    
    # Test 2: DNS resolution
    log_info "Test 2/7: DNS resolution..."
    if nslookup google.com >> "$LOG_FILE" 2>&1; then
        log_success "✓ DNS resolution OK"
    else
        log_error "✗ DNS resolution failed"
        test_failed=1
    fi
    
    # Test 3: Disk space for /mnt/data
    log_info "Test 3/7: Disk space for data directory..."
    
    # Create /mnt/data if it doesn't exist for testing
    if [ ! -d "/mnt/data" ]; then
        sudo mkdir -p /mnt/data
        sudo chown -R $USER:$USER /mnt/data
    fi
    
    local data_mount=$(df -P /mnt/data 2>/dev/null | awk 'NR==2 {print $6}' || echo "/")
    local available_space=$(df -BG /mnt/data 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    local total_space=$(df -BG /mnt/data 2>/dev/null | awk 'NR==2 {print $2}' | sed 's/G//' || df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
    
    log_debug "  Mount point: $data_mount"
    log_debug "  Total space: ${total_space}GB"
    log_debug "  Available: ${available_space}GB"
    
    if [ "$data_mount" == "/" ]; then
        log_debug "  Note: /mnt/data is on root partition"
    else
        log_debug "  Note: /mnt/data is on separate partition"
    fi
    
    if [ "$available_space" -gt 50 ]; then
        log_success "✓ Disk space OK (${available_space}GB available on $data_mount)"
    else
        log_warn "⚠ Low disk space (${available_space}GB available on $data_mount, 50GB+ recommended)"
        log_warn "  AWX requires: ~10GB for base install + 40GB for PV + logs/archives"
        if [ "$available_space" -lt 30 ]; then
            log_error "  CRITICAL: Less than 30GB available - installation will likely fail!"
            test_failed=1
        elif [ "$available_space" -lt 50 ]; then
            log_warn "  WARNING: Installation may succeed but monitoring and future growth will be limited"
        fi
    fi
    
    # Test 4: Memory
    log_info "Test 4/7: Memory..."
    local total_mem=$(free -g | awk '/^Mem:/ {print $2}')
    if [ "$total_mem" -ge 8 ]; then
        log_success "✓ Memory OK (${total_mem}GB)"
    else
        log_warn "⚠ Low memory (${total_mem}GB, 8GB+ recommended)"
    fi
    
    # Test 5: CPU cores
    log_info "Test 5/7: CPU cores..."
    local cpu_cores=$(nproc)
    if [ "$cpu_cores" -ge 4 ]; then
        log_success "✓ CPU cores OK ($cpu_cores cores)"
    else
        log_warn "⚠ Low CPU cores ($cpu_cores cores, 4+ recommended)"
    fi
    
    # Test 6: Port availability
    log_info "Test 6/7: Port availability..."
    if ! sudo netstat -tuln | grep -q ":30080 "; then
        log_success "✓ Port 30080 available"
    else
        log_warn "⚠ Port 30080 already in use"
    fi
    
    # Test 7: Directory permissions
    log_info "Test 7/7: Directory permissions..."
    if [ -w "$DATA_ROOT" ]; then
        log_success "✓ Directory permissions OK"
    else
        log_error "✗ Cannot write to $DATA_ROOT"
        test_failed=1
    fi
    
    if [ $test_failed -eq 1 ]; then
        log_error "Pre-flight tests failed!"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "All pre-flight tests passed!"
    fi
    
    echo
}

confirm_installation() {
    log_warn "This script will install and configure:"
    echo "  ✓ System updates and essential packages"
    echo "  ✓ Docker CE"
    echo "  ✓ MicroK8s Kubernetes ($MICROK8S_CHANNEL)"
    echo "  ✓ Persistent Volume (${PV_SIZE} at ${PV_DIR})"
    echo "  ✓ AWX Operator $AWX_OPERATOR_VERSION"
    echo "  ✓ AWX (Ansible Automation Platform)"
    echo
    echo -e "${CYAN}Data will be stored in:${NC}"
    echo "  • Logs:       ${LOG_DIR}"
    echo "  • Archives:   ${ARCHIVE_DIR}"
    echo "  • PV Data:    ${PV_DIR} (${PV_SIZE})"
    echo
    echo -e "${CYAN}Installation Mode:${NC} ${YELLOW}${INSTALL_MODE}${NC}"
    echo
    log_warn "Estimated installation time: 30-45 minutes"
    echo
    
    if [ "$INSTALL_MODE" == "reinstall" ]; then
        log_error "⚠️  REINSTALL MODE: This will DELETE existing AWX installation!"
        read -p "Are you sure you want to REINSTALL? (yes/no): " -r
        if [[ ! $REPLY == "yes" ]]; then
            log_info "Installation cancelled"
            exit 0
        fi
    fi
    
    read -p "Do you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
    echo
}

check_system() {
    log_step "Checking system requirements..."
    
    # Check if running on Linux
    if [[ "$(uname -s)" != "Linux" ]]; then
        error_exit "This script requires Linux. Detected: $(uname -s)"
    fi
    
    # Check if lsb_release is available
    if ! command -v lsb_release &> /dev/null; then
        log_warn "lsb_release not found, installing..."
        sudo apt-get update >> "$LOG_FILE" 2>&1
        sudo apt-get install -y lsb-release >> "$LOG_FILE" 2>&1
    fi
    
    # Check if running on Ubuntu
    if [ ! -f /etc/os-release ]; then
        error_exit "Cannot detect OS. /etc/os-release file not found."
    fi
    
    # Source the os-release file
    . /etc/os-release
    
    # Strict Ubuntu check
    if [[ "$ID" != "ubuntu" ]]; then
        log_error "════════════════════════════════════════════════════════"
        log_error "  ⚠️  UNSUPPORTED OPERATING SYSTEM DETECTED"
        log_error "════════════════════════════════════════════════════════"
        log_error "This script is designed ONLY for Ubuntu 24.04 LTS"
        log_error "Your system: $NAME ($ID) - Version: $VERSION"
        log_error "════════════════════════════════════════════════════════"
        error_exit "Unsupported operating system."
    fi
    
    # Check Ubuntu version
    UBUNTU_VERSION=$(lsb_release -rs)
    log_info "Detected Ubuntu version: $UBUNTU_VERSION"
    
    if [[ "$UBUNTU_VERSION" != "24.04" ]]; then
        log_error "════════════════════════════════════════════════════════"
        log_error "  ⚠️  UNSUPPORTED UBUNTU VERSION"
        log_error "════════════════════════════════════════════════════════"
        log_error "Required: Ubuntu 24.04 LTS"
        log_error "Detected: Ubuntu $UBUNTU_VERSION"
        log_error "════════════════════════════════════════════════════════"
        error_exit "Unsupported Ubuntu version."
    fi
    
    log_success "Operating System: Ubuntu $UBUNTU_VERSION ✓"
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [[ $CPU_CORES -lt 4 ]]; then
        log_warn "System has only $CPU_CORES CPU cores. Recommended: 4+ cores"
    else
        log_info "CPU cores: $CPU_CORES ✓"
    fi
    
    # Check memory
    MEMORY_GB=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $MEMORY_GB -lt 8 ]]; then
        log_warn "System has only ${MEMORY_GB}GB RAM. Recommended: 8GB+"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        log_info "Memory: ${MEMORY_GB}GB ✓"
    fi
    
    # Check disk space for /mnt/data
    local data_mount=$(df -P /mnt/data 2>/dev/null | awk 'NR==2 {print $6}' || echo "/")
    local data_space=$(df -BG /mnt/data 2>/dev/null | awk 'NR==2 {print $4}' | sed 's/G//' || df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    log_info "Data directory mount point: $data_mount"
    
    if [[ $data_space -lt 50 ]]; then
        log_warn "Low disk space on $data_mount: ${data_space}GB available (50GB+ recommended)"
        log_warn "AWX requires significant disk space for logs, archives, and persistent data"
    else
        log_info "Disk space on $data_mount: ${data_space}GB available ✓"
    fi
    
    log_success "System requirements check completed"
}

# Handle reinstall mode
handle_reinstall() {
    if [ "$INSTALL_MODE" == "reinstall" ]; then
        log_step "Removing existing AWX installation..."
        
        # Delete AWX namespace and all resources
        if sudo microk8s kubectl get namespace $AWX_NAMESPACE &>/dev/null; then
            log_info "Deleting AWX namespace..."
            sudo microk8s kubectl delete namespace $AWX_NAMESPACE --timeout=300s >> "$LOG_FILE" 2>&1 || true
            
            # Wait for namespace deletion
            local wait_count=0
            while sudo microk8s kubectl get namespace $AWX_NAMESPACE &>/dev/null; do
                if [ $wait_count -gt 60 ]; then
                    log_warn "Namespace deletion timeout, forcing..."
                    sudo microk8s kubectl delete namespace $AWX_NAMESPACE --grace-period=0 --force >> "$LOG_FILE" 2>&1 || true
                    break
                fi
                log_info "Waiting for namespace deletion... ($wait_count/60)"
                sleep 5
                ((wait_count++))
            done
            
            log_success "AWX namespace deleted"
        fi
        
        # Backup existing PV data
        if [ -d "$PV_DIR" ] && [ "$(ls -A $PV_DIR)" ]; then
            local backup_dir="${PV_DIR}_backup_${TIMESTAMP}"
            log_info "Backing up PV data to $backup_dir..."
            sudo mv "$PV_DIR" "$backup_dir"
            sudo mkdir -p "$PV_DIR"
            log_success "PV data backed up"
        fi
        
        # Set correct permissions on fresh PV directory
        log_info "Setting PostgreSQL permissions on fresh PV directory..."
        sudo chown -R 26:26 "$PV_DIR"
        sudo chmod 700 "$PV_DIR"
        
        log_success "Reinstall preparation completed"
    fi
    
    # Handle repair mode
    if [ "$INSTALL_MODE" == "repair" ]; then
        log_step "Repairing AWX installation..."
        
        # Fix PV directory permissions
        if [ -d "$PV_DIR" ]; then
            log_info "Checking and fixing PV directory permissions..."
            local current_owner=$(stat -c '%u:%g' "$PV_DIR" 2>/dev/null || echo "unknown")
            local current_perms=$(stat -c '%a' "$PV_DIR" 2>/dev/null || echo "unknown")
            
            log_info "Current PV owner: $current_owner (expected: 26:26)"
            log_info "Current PV perms: $current_perms (expected: 700)"
            
            if [ "$current_owner" != "26:26" ] || [ "$current_perms" != "700" ]; then
                log_warn "Fixing PV directory permissions..."
                sudo chown -R 26:26 "$PV_DIR"
                sudo chmod 700 "$PV_DIR"
                log_success "PV permissions fixed"
            else
                log_success "PV permissions are correct"
            fi
        fi
        
        # Restart PostgreSQL pod if it exists and is not running
        local postgres_pod=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=postgres --no-headers 2>/dev/null | awk '{print $1}' | head -1)
        if [ -n "$postgres_pod" ]; then
            local pod_status=$(sudo microk8s kubectl get pod $postgres_pod -n $AWX_NAMESPACE --no-headers 2>/dev/null | awk '{print $3}')
            
            if [[ "$pod_status" != "Running" ]]; then
                log_warn "PostgreSQL pod is not running (Status: $pod_status)"
                log_info "Deleting pod to force recreation..."
                sudo microk8s kubectl delete pod $postgres_pod -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
                log_info "Pod deleted, waiting for recreation..."
                sleep 10
            fi
        fi
        
        log_success "Repair operations completed"
    fi
}

update_system() {
    log_step "Updating system packages..."
    
    log_info "Running apt update..."
    sudo apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Failed to update package lists"
    
    log_info "Running apt upgrade..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y >> "$LOG_FILE" 2>&1 || log_warn "Some packages failed to upgrade"
    
    log_success "System packages updated"
}

install_docker() {
    log_step "Installing Docker CE..."
    
    if command -v docker &> /dev/null; then
        local docker_version=$(docker --version)
        log_info "Docker already installed: $docker_version"
        
        # Check if user is in docker group
        if groups | grep -q docker; then
            log_success "User already in docker group ✓"
        else
            log_info "Adding user to docker group..."
            sudo usermod -aG docker $USER
            log_warn "You may need to log out and back in for docker group changes"
        fi
        
        return 0
    fi
    
    log_info "Installing Docker dependencies..."
    sudo apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release >> "$LOG_FILE" 2>&1 || error_exit "Failed to install Docker dependencies"
    
    log_info "Adding Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>> "$LOG_FILE" || \
        error_exit "Failed to add Docker GPG key"
    
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    log_info "Adding Docker repository..."
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log_info "Installing Docker CE..."
    sudo apt-get update >> "$LOG_FILE" 2>&1
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to install Docker"
    
    log_info "Adding user to docker group..."
    sudo usermod -aG docker $USER
    
    log_info "Testing Docker installation..."
    sudo docker run --rm hello-world >> "$LOG_FILE" 2>&1 || log_warn "Docker test failed"
    
    log_success "Docker CE installed successfully"
}

install_microk8s() {
    log_step "Installing MicroK8s..."
    
    if command -v microk8s &> /dev/null; then
        log_info "MicroK8s already installed"
        
        if groups | grep -q microk8s; then
            log_success "User already in microk8s group ✓"
        else
            log_info "Adding user to microk8s group..."
            sudo usermod -aG microk8s $USER
            log_warn "You may need to log out and back in for microk8s group changes"
        fi
        
        return 0
    fi
    
    log_info "Installing MicroK8s snap package..."
    sudo snap install microk8s --classic --channel=$MICROK8S_CHANNEL >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to install MicroK8s"
    
    log_info "Adding user to microk8s group..."
    sudo usermod -aG microk8s $USER
    sudo chown -R $USER ~/.kube 2>/dev/null || true
    
    log_info "Waiting for MicroK8s to be ready..."
    local wait_count=0
    while ! sudo microk8s status --wait-ready --timeout 300 >> "$LOG_FILE" 2>&1; do
        if [ $wait_count -gt 10 ]; then
            error_exit "MicroK8s failed to start"
        fi
        log_info "Waiting for MicroK8s... ($wait_count/10)"
        sleep 30
        ((wait_count++))
    done
    
    log_success "MicroK8s installed successfully"
}

configure_microk8s() {
    log_step "Configuring MicroK8s..."
    
    log_info "Enabling required addons..."
    
    # Enable DNS
    if ! sudo microk8s status | grep -q "dns.*enabled"; then
        log_info "Enabling DNS addon..."
        sudo microk8s enable dns >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable DNS"
    else
        log_debug "DNS already enabled"
    fi
    
    # Enable storage
    if ! sudo microk8s status | grep -q "storage.*enabled"; then
        log_info "Enabling storage addon..."
        sudo microk8s enable storage >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable storage"
    else
        log_debug "Storage already enabled"
    fi
    
    # Enable ingress
    if ! sudo microk8s status | grep -q "ingress.*enabled"; then
        log_info "Enabling ingress addon..."
        sudo microk8s enable ingress >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable ingress"
    else
        log_debug "Ingress already enabled"
    fi
    
    log_info "Waiting for addons to be ready..."
    sleep 30
    
    log_success "MicroK8s configured successfully"
}

# Create PersistentVolume and PersistentVolumeClaim
create_persistent_volume() {
    log_step "Creating Persistent Volume..."
    
    # Ensure PV directory exists with correct permissions
    if [ ! -d "$PV_DIR" ]; then
        log_info "Creating PV directory: $PV_DIR"
        sudo mkdir -p "$PV_DIR"
    fi
    
    # Set PostgreSQL-specific permissions
    log_info "Setting PostgreSQL permissions on PV directory..."
    sudo chown -R 26:26 "$PV_DIR"
    sudo chmod 700 "$PV_DIR"
    
    # Verify permissions
    local pv_owner=$(stat -c '%u:%g' "$PV_DIR")
    local pv_perms=$(stat -c '%a' "$PV_DIR")
    
    log_info "PV directory: $PV_DIR"
    log_info "PV owner: $pv_owner (expected: 26:26)"
    log_info "PV permissions: $pv_perms (expected: 700)"
    
    if [ "$pv_owner" != "26:26" ]; then
        log_warn "PV ownership mismatch! Fixing..."
        sudo chown -R 26:26 "$PV_DIR"
    fi
    
    if [ "$pv_perms" != "700" ]; then
        log_warn "PV permissions mismatch! Fixing..."
        sudo chmod 700 "$PV_DIR"
    fi
    
    log_success "PV directory ready with correct permissions"
    log_info "PV size: $PV_SIZE"
    
    # Create PV YAML
    local pv_yaml="${ARCHIVE_DIR}/awx-pv-${TIMESTAMP}.yaml"
    cat > "$pv_yaml" <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: awx-pv
spec:
  capacity:
    storage: $PV_SIZE
  accessModes:
    - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: microk8s-hostpath
  hostPath:
    path: $PV_DIR
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: awx-pvc
  namespace: $AWX_NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $PV_SIZE
  storageClassName: microk8s-hostpath
EOF
    
    log_info "PV YAML saved to: $pv_yaml"
    
    # Create namespace if not exists
    if ! sudo microk8s kubectl get namespace $AWX_NAMESPACE &>/dev/null; then
        log_info "Creating namespace $AWX_NAMESPACE..."
        sudo microk8s kubectl create namespace $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
    fi
    
    # Apply PV configuration
    log_info "Applying PV configuration..."
    sudo microk8s kubectl apply -f "$pv_yaml" >> "$LOG_FILE" 2>&1 || error_exit "Failed to create PV"
    
    # Wait for PV to be available (PV is cluster-scoped, no namespace)
    log_info "Waiting for PV to be available..."
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if sudo microk8s kubectl get pv awx-pv &>/dev/null; then
            local pv_status=$(sudo microk8s kubectl get pv awx-pv -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            log_info "PV Status: $pv_status"
            
            if [[ "$pv_status" == "Available" ]] || [[ "$pv_status" == "Bound" ]]; then
                log_success "Persistent Volume created successfully (Status: $pv_status)"
                
                # Check PVC as well
                if sudo microk8s kubectl get pvc awx-pvc -n $AWX_NAMESPACE &>/dev/null; then
                    local pvc_status=$(sudo microk8s kubectl get pvc awx-pvc -n $AWX_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
                    log_info "PVC Status: $pvc_status"
                fi
                
                # Final permission check after PV creation
                log_info "Final permission verification..."
                local final_owner=$(stat -c '%u:%g' "$PV_DIR")
                local final_perms=$(stat -c '%a' "$PV_DIR")
                log_debug "  Final owner: $final_owner"
                log_debug "  Final permissions: $final_perms"
                
                return 0
            fi
        fi
        sleep 2
        ((wait_count++))
    done
    
    log_warn "PV creation verification timeout, but continuing..."
    log_info "You can verify manually with: sudo microk8s kubectl get pv awx-pv"
}

install_awx_operator() {
    log_step "Installing AWX Operator..."
    
    # Create namespace if not exists
    if ! sudo microk8s kubectl get namespace $AWX_NAMESPACE &>/dev/null; then
        log_info "Creating namespace $AWX_NAMESPACE..."
        sudo microk8s kubectl create namespace $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
    else
        log_info "Namespace $AWX_NAMESPACE already exists"
    fi
    
    # Check if operator already installed
    if sudo microk8s kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE &>/dev/null; then
        log_info "AWX Operator already installed, checking status..."
        if sudo microk8s kubectl wait --for=condition=available --timeout=30s \
            deployment/awx-operator-controller-manager -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
            log_success "AWX Operator already installed and ready"
            return 0
        else
            log_warn "Existing operator not ready, reinstalling..."
            sudo microk8s kubectl delete deployment awx-operator-controller-manager -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1 || true
            sleep 10
        fi
    fi
    
    # Download operator using multiple methods
    local operator_yaml="${ARCHIVE_DIR}/awx-operator-${TIMESTAMP}.yaml"
    local method_success=0
    
    # Method 1: Try using kubectl directly with URL
    log_info "Method 1: Trying kubectl apply with direct URL..."
    local direct_url="https://raw.githubusercontent.com/ansible/awx-operator/${AWX_OPERATOR_VERSION}/config/default"
    if sudo microk8s kubectl apply -k "$direct_url" -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
        log_success "Operator installed via kubectl kustomize"
        method_success=1
    else
        log_warn "Method 1 failed, trying alternative methods..."
    fi
    
    # Method 2: Try git clone with kustomize
    if [ $method_success -eq 0 ]; then
        log_info "Method 2: Cloning repository and using kustomize..."
        local temp_dir=$(mktemp -d)
        cd "$temp_dir"
        
        if git clone --depth 1 --branch ${AWX_OPERATOR_VERSION} https://github.com/ansible/awx-operator.git >> "$LOG_FILE" 2>&1; then
            cd awx-operator
            
            log_info "Generating operator manifest..."
            if sudo microk8s kubectl kustomize config/default > "$operator_yaml" 2>> "$LOG_FILE"; then
                if sudo microk8s kubectl apply -f "$operator_yaml" -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
                    log_success "Operator installed via git clone + kustomize"
                    method_success=1
                fi
            fi
            cd - > /dev/null
        fi
        rm -rf "$temp_dir"
    fi
    
    # Method 3: Try direct YAML download
    if [ $method_success -eq 0 ]; then
        log_info "Method 3: Trying direct YAML download..."
        local urls=(
            "https://github.com/ansible/awx-operator/releases/download/${AWX_OPERATOR_VERSION}/awx-operator.yaml"
            "https://raw.githubusercontent.com/ansible/awx-operator/${AWX_OPERATOR_VERSION}/deploy/awx-operator.yaml"
        )
        
        for url in "${urls[@]}"; do
            log_info "Trying URL: $url"
            if curl -fsSL --retry 3 --retry-delay 5 --max-time 60 "$url" -o "$operator_yaml" 2>> "$LOG_FILE"; then
                # Validate downloaded YAML
                if [ -s "$operator_yaml" ] && grep -q "apiVersion" "$operator_yaml"; then
                    local yaml_size=$(stat -c%s "$operator_yaml" 2>/dev/null || echo "0")
                    log_info "Downloaded YAML size: $yaml_size bytes"
                    
                    if [ "$yaml_size" -gt 1000 ]; then
                        log_info "Applying downloaded operator YAML..."
                        if sudo microk8s kubectl apply -f "$operator_yaml" -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
                            log_success "Operator installed via direct download"
                            method_success=1
                            break
                        fi
                    fi
                fi
            fi
        done
    fi
    
    # Method 4: Install via helm as last resort
    if [ $method_success -eq 0 ]; then
        log_info "Method 4: Trying Helm installation..."
        
        # Check if helm is available
        if ! command -v helm &> /dev/null; then
            log_info "Installing Helm..."
            curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash >> "$LOG_FILE" 2>&1
        fi
        
        if command -v helm &> /dev/null; then
            log_info "Adding AWX Operator Helm repo..."
            helm repo add awx-operator https://ansible.github.io/awx-operator/ >> "$LOG_FILE" 2>&1 || true
            helm repo update >> "$LOG_FILE" 2>&1
            
            log_info "Installing AWX Operator via Helm..."
            if helm install awx-operator awx-operator/awx-operator -n $AWX_NAMESPACE --version ${AWX_OPERATOR_VERSION} >> "$LOG_FILE" 2>&1; then
                log_success "Operator installed via Helm"
                method_success=1
            fi
        fi
    fi
    
    # Check if any method succeeded
    if [ $method_success -eq 0 ]; then
        log_error "All installation methods failed!"
        log_error "Please check your internet connection and try again"
        log_error "You can also try manual installation:"
        log_error "  kubectl apply -k https://github.com/ansible/awx-operator/config/default?ref=${AWX_OPERATOR_VERSION}"
        error_exit "Failed to install AWX Operator"
    fi
    
    log_info "Waiting for operator deployment to be created..."
    local wait_count=0
    while [ $wait_count -lt 60 ]; do
        if sudo microk8s kubectl get deployment awx-operator-controller-manager -n $AWX_NAMESPACE &>/dev/null; then
            log_info "Operator deployment found, waiting for it to be ready..."
            if sudo microk8s kubectl wait --for=condition=available --timeout=300s \
                deployment/awx-operator-controller-manager -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
                
                # Verify operator is actually running
                local ready_pods=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l control-plane=controller-manager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
                if [ "$ready_pods" -gt 0 ]; then
                    log_success "AWX Operator installed and running successfully"
                    
                    # Save successful installation method info
                    echo "AWX Operator ${AWX_OPERATOR_VERSION} installed successfully at $(date)" >> "${ARCHIVE_DIR}/operator-install-info.txt"
                    return 0
                else
                    log_warn "Operator deployment ready but pod not running yet, waiting..."
                fi
            fi
        fi
        
        # Show current status every 10 seconds
        if [ $((wait_count % 10)) -eq 0 ]; then
            log_info "Waiting for operator deployment... ($wait_count/60)"
            local pod_status=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null || echo "No pods found")
            log_debug "Current pods: $pod_status"
        fi
        
        sleep 5
        ((wait_count++))
    done
    
    log_error "Operator deployment status:"
    sudo microk8s kubectl get all -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
    sudo microk8s kubectl describe deployment awx-operator-controller-manager -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
    error_exit "AWX Operator failed to become ready within timeout"
}

create_postgres_secret() {
    log_step "Creating PostgreSQL secret..."
    
    # Generate secure password
    local postgres_password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    local secret_yaml="${ARCHIVE_DIR}/awx-postgres-secret-${TIMESTAMP}.yaml"
    
    cat > "$secret_yaml" <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: awx-postgres-configuration
  namespace: $AWX_NAMESPACE
type: Opaque
stringData:
  host: awx-postgres-15
  port: "5432"
  database: awx
  username: awx
  password: $postgres_password
  type: managed
EOF
    
    log_info "Applying PostgreSQL secret..."
    sudo microk8s kubectl apply -f "$secret_yaml" >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to create PostgreSQL secret"
    
    # Save password securely
    local creds_file="${ARCHIVE_DIR}/postgres-credentials-${TIMESTAMP}.txt"
    cat > "$creds_file" <<EOF
PostgreSQL Credentials
Created: $(date)
--------------------
Password: $postgres_password
--------------------
KEEP THIS FILE SECURE!
EOF
    chmod 600 "$creds_file"
    
    log_success "PostgreSQL secret created"
    log_info "Credentials saved to: $creds_file"
}

create_awx_instance() {
    log_step "Creating AWX instance..."
    
    local awx_yaml="${ARCHIVE_DIR}/awx-deployment-${TIMESTAMP}.yaml"
    
    cat > "$awx_yaml" <<EOF
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: $AWX_NAMESPACE
spec:
  service_type: NodePort
  nodeport_port: 30080
  postgres_configuration_secret: awx-postgres-configuration
  postgres_storage_class: microk8s-hostpath
  postgres_storage_requirements:
    requests:
      storage: 8Gi
  postgres_data_volume_init: true
  postgres_init_container_resource_requirements:
    requests:
      cpu: 10m
      memory: 64Mi
    limits:
      cpu: 1000m
      memory: 1Gi
  postgres_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  projects_persistence: true
  projects_storage_access_mode: ReadWriteOnce
  projects_storage_class: microk8s-hostpath
  projects_storage_size: 8Gi
  web_replicas: 1
  task_replicas: 1
  web_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  task_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  ee_resource_requirements:
    requests:
      cpu: 100m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 2Gi
  ee_images:
    - name: AWX EE
      image: quay.io/ansible/awx-ee:latest
EOF
    
    log_info "Applying AWX configuration..."
    sudo microk8s kubectl apply -f "$awx_yaml" >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to create AWX instance"
    
    log_success "AWX instance creation initiated"
    log_info "Configuration saved to: $awx_yaml"
    
    # Wait a bit for the operator to process
    log_info "Waiting for operator to process AWX instance..."
    sleep 30
    
    # Check if AWX instance was created
    local wait_count=0
    while [ $wait_count -lt 30 ]; do
        if sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE &>/dev/null; then
            log_success "AWX instance registered with operator"
            
            # Show initial status
            local initial_status=$(sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE -o jsonpath='{.status}' 2>/dev/null || echo "{}")
            log_debug "Initial AWX status: $initial_status"
            break
        fi
        log_debug "Waiting for AWX instance to be registered... ($wait_count/30)"
        sleep 5
        ((wait_count++))
    done
    
    if ! sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE &>/dev/null; then
        log_error "AWX instance was not registered by operator"
        log_error "Checking operator logs..."
        sudo microk8s kubectl logs -n $AWX_NAMESPACE -l control-plane=controller-manager --tail=50 >> "$LOG_FILE" 2>&1
        error_exit "Failed to register AWX instance"
    fi
}

# Enhanced wait function with minute-by-minute status
wait_for_awx() {
    log_step "Waiting for AWX deployment to complete..."
    log_info "This process will provide status updates every minute"
    echo
    
    local max_wait=3600  # 60 minutes max
    local elapsed=0
    local last_status=""
    local deployment_ready=0
    
    while [ $elapsed -lt $max_wait ]; do
        local current_minute=$((elapsed / 60))
        
        # Get current status
        local awx_exists=$(sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE 2>/dev/null && echo "yes" || echo "no")
        
        if [ "$awx_exists" == "yes" ]; then
            local awx_status=$(sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Running")].status}' 2>/dev/null || echo "Unknown")
            local awx_phase=$(sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            
            # If phase is empty but status is True, try to get more info
            if [ -z "$awx_phase" ] && [ "$awx_status" == "True" ]; then
                awx_phase="Running"
            fi
        else
            local awx_status="NotFound"
            local awx_phase="NotCreated"
        fi
        
        # Count running pods
        local total_pods=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | wc -l)
        local running_pods=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        local ready_pods=0
        
        # Count pods that are actually ready (not just running)
        if [ $total_pods -gt 0 ]; then
            ready_pods=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]+/[0-9]+$' | awk -F'/' '$1==$2 {print}' | wc -l)
        fi
        
        # Get critical pod details
        local web_pod_status=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx-web --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "NotFound")
        local task_pod_status=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx-task --no-headers 2>/dev/null | awk '{print $3}' | head -1 || echo "NotFound")
        
        # PostgreSQL pod - try multiple label selectors
        local postgres_pod_status=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=postgres --no-headers 2>/dev/null | awk '{print $3}' | head -1)
        if [ -z "$postgres_pod_status" ]; then
            # Try alternative label
            postgres_pod_status=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep postgres | awk '{print $3}' | head -1 || echo "NotFound")
        fi
        
        local postgres_pod_name=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep postgres | awk '{print $1}' | head -1 || echo "")
        
        # Check for PostgreSQL CrashLoopBackOff
        if [[ "$postgres_pod_status" == "CrashLoopBackOff" ]] || [[ "$postgres_pod_status" == "Error" ]]; then
            if [ $((elapsed % 120)) -eq 0 ] && [ $elapsed -gt 0 ]; then
                echo
                log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                log_error "PostgreSQL Pod Issue Detected!"
                log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                
                if [ -n "$postgres_pod_name" ]; then
                    log_error "Checking PostgreSQL pod logs..."
                    echo
                    log_error "Current logs:"
                    sudo microk8s kubectl logs $postgres_pod_name -n $AWX_NAMESPACE --tail=20 2>&1 | while read line; do
                        log_error "  $line"
                    done
                    
                    echo
                    log_error "Previous logs (from crashed container):"
                    sudo microk8s kubectl logs $postgres_pod_name -n $AWX_NAMESPACE --previous --tail=20 2>&1 | while read line; do
                        log_error "  $line"
                    done
                    
                    echo
                    log_error "PostgreSQL PVC status:"
                    sudo microk8s kubectl get pvc -n $AWX_NAMESPACE 2>&1 | grep postgres | while read line; do
                        log_error "  $line"
                    done
                    
                    echo
                    log_error "Recent events:"
                    sudo microk8s kubectl get events -n $AWX_NAMESPACE --sort-by='.lastTimestamp' 2>&1 | grep -i postgres | tail -5 | while read line; do
                        log_error "  $line"
                    done
                fi
                
                log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                
                # Try to fix common PostgreSQL issues
                if [ $elapsed -lt 1800 ]; then  # Only try fixes in first 30 minutes
                    log_warn "Attempting to resolve PostgreSQL issues..."
                    
                    # Check PVC binding
                    local pvc_status=$(sudo microk8s kubectl get pvc -n $AWX_NAMESPACE -o jsonpath='{.items[?(@.metadata.name=="postgres-15-awx-postgres-15-0")].status.phase}' 2>/dev/null)
                    if [[ "$pvc_status" != "Bound" ]]; then
                        log_error "PostgreSQL PVC not bound (Status: $pvc_status)"
                        log_info "This is likely a storage issue. Checking storage..."
                        
                        # Check if storage class exists
                        if ! sudo microk8s kubectl get storageclass microk8s-hostpath &>/dev/null; then
                            log_error "Storage class 'microk8s-hostpath' not found!"
                            log_info "Checking MicroK8s storage addon..."
                            if ! sudo microk8s status | grep -q "storage.*enabled"; then
                                log_warn "Enabling storage addon..."
                                sudo microk8s enable storage >> "$LOG_FILE" 2>&1
                                sleep 10
                            fi
                        fi
                    fi
                    
                    # Try deleting the pod to force recreation
                    if [ $elapsed -gt 300 ]; then  # After 5 minutes
                        log_warn "Deleting failed PostgreSQL pod to force recreation..."
                        sudo microk8s kubectl delete pod $postgres_pod_name -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
                        sleep 30
                    fi
                fi
            fi
        fi
        
        # Status update every minute
        if [ $((elapsed % 60)) -eq 0 ] && [ $elapsed -gt 0 ]; then
            echo
            log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_info "Status Update - Minute $current_minute"
            log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_info "AWX Phase: $awx_phase"
            log_info "AWX Status: $awx_status"
            log_info "Pods: $running_pods/$total_pods running, $ready_pods/$total_pods ready"
            echo
            log_info "Critical Pod Status:"
            log_debug "  Web Pod:      $web_pod_status"
            log_debug "  Task Pod:     $task_pod_status"
            log_debug "  Postgres Pod: $postgres_pod_status"
            echo
            log_info "All Pods:"
            sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | while read line; do
                local pod_name=$(echo $line | awk '{print $1}')
                local pod_ready=$(echo $line | awk '{print $2}')
                local pod_status=$(echo $line | awk '{print $3}')
                log_debug "  $pod_name [$pod_ready] - $pod_status"
            done
            log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo
        fi
        
        # Check if AWX is fully deployed using multiple criteria
        # Criteria 1: AWX status and phase check (optional - may not work if CRD is not found)
        local status_ok=0
        if [[ "$awx_status" == "True" ]] && ([[ "$awx_phase" == "Running" ]] || [[ -z "$awx_phase" ]]); then
            status_ok=1
        fi
        
        # Criteria 1b: If AWX CRD not found but pods are running, that's also OK
        if [[ "$awx_exists" == "no" ]] && [[ "$web_pod_status" == "Running" ]] && [[ "$task_pod_status" == "Running" ]]; then
            log_debug "AWX CRD not found, but pods are running - considering this as success"
            status_ok=1
        fi
        
        # Criteria 2: Critical pods must be running
        local pods_ok=0
        if [[ "$web_pod_status" == "Running" ]] && [[ "$task_pod_status" == "Running" ]] && [[ "$postgres_pod_status" == "Running" ]]; then
            pods_ok=1
        fi
        
        # Criteria 3: All pods must be ready (adjusted to ignore Completed jobs)
        local all_ready=0
        local running_count=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        local completed_count=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --field-selector=status.phase=Succeeded --no-headers 2>/dev/null | wc -l)
        local total_active=$((running_count + completed_count))
        
        # If we have at least 4 pods (operator, postgres, web, task) and they're all ready, that's enough
        if [ $ready_pods -ge 4 ] && [ $running_count -ge 4 ]; then
            all_ready=1
        fi
        
        # Alternative check: if web, task, and postgres are running, that's enough
        if [[ "$web_pod_status" == "Running" ]] && [[ "$task_pod_status" == "Running" ]] && [[ "$postgres_pod_status" == "Running" ]]; then
            # Check if these pods are actually ready (not just running)
            local web_ready=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx-web --no-headers 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]+/[0-9]+$' | awk -F'/' '$1==$2 {print "yes"}' | head -1)
            local task_ready=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx-task --no-headers 2>/dev/null | awk '{print $2}' | grep -E '^[0-9]+/[0-9]+$' | awk -F'/' '$1==$2 {print "yes"}' | head -1)
            
            if [[ "$web_ready" == "yes" ]] && [[ "$task_ready" == "yes" ]]; then
                all_ready=1
                log_debug "Critical pods (web, task, postgres) are ready"
            fi
        fi
        
        # Check if deployment is complete
        # Success if either:
        # 1. All three criteria met (ideal)
        # 2. pods_ok AND all_ready (AWX CRD might not be queryable but pods are fine)
        if ([ $status_ok -eq 1 ] && [ $pods_ok -eq 1 ] && [ $all_ready -eq 1 ]) || 
           ([ $pods_ok -eq 1 ] && [ $all_ready -eq 1 ]); then
            # Double check by verifying pods are actually healthy
            local unhealthy_pods=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep -vE "Running|Completed|Succeeded" | wc -l)
            
            if [ $unhealthy_pods -eq 0 ]; then
                echo
                log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                log_success "AWX Deployment Completed Successfully!"
                log_success "Total deployment time: $current_minute minutes"
                log_success "All critical pods are running and ready"
                
                if [[ "$awx_exists" == "no" ]]; then
                    log_warn "Note: AWX CRD query failed, but pods are healthy"
                    log_warn "This is usually not a problem - AWX is running"
                fi
                
                log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo
                deployment_ready=1
                break
            else
                log_debug "Some pods not yet healthy, waiting... (unhealthy: $unhealthy_pods)"
            fi
        fi
        
        # Show progress indicator
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo -n "."
        fi
        
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    if [ $deployment_ready -eq 0 ]; then
        echo
        log_error "AWX deployment timeout after $((max_wait / 60)) minutes"
        log_error "Final status: Phase=$awx_phase, Status=$awx_status"
        log_error "Pods: $running_pods/$total_pods running, $ready_pods/$total_pods ready"
        echo
        log_error "Pod Status Details:"
        sudo microk8s kubectl get pods -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
        sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | while read line; do
            log_error "  $line"
        done
        echo
        log_error "Recent Events:"
        sudo microk8s kubectl get events -n $AWX_NAMESPACE --sort-by='.lastTimestamp' | tail -20 >> "$LOG_FILE" 2>&1
        sudo microk8s kubectl get events -n $AWX_NAMESPACE --sort-by='.lastTimestamp' | tail -10 | while read line; do
            log_error "  $line"
        done
        echo
        log_error "AWX Instance Status:"
        sudo microk8s kubectl describe awx awx -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
        
        # Even if timeout, check if pods are actually running
        if [ "$web_pod_status" == "Running" ] && [ "$task_pod_status" == "Running" ]; then
            log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            log_warn "AWX pods appear to be running despite timeout!"
            log_warn "The installation might actually be successful."
            log_warn "Continuing with credential retrieval..."
            log_warn "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            return 0
        fi
        
        error_exit "AWX deployment did not complete in time"
    fi
    
    return 0
}

get_awx_credentials() {
    log_step "Retrieving AWX credentials..."
    
    # Wait for admin password secret
    local wait_count=0
    while [ $wait_count -lt 60 ]; do
        if sudo microk8s kubectl get secret awx-admin-password -n $AWX_NAMESPACE &>/dev/null; then
            break
        fi
        log_info "Waiting for admin password secret... ($wait_count/60)"
        sleep 5
        ((wait_count++))
    done
    
    # Get admin password
    local admin_password=$(sudo microk8s kubectl get secret awx-admin-password -n $AWX_NAMESPACE \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)
    
    if [ -z "$admin_password" ]; then
        error_exit "Failed to retrieve admin password"
    fi
    
    # Get service port
    local awx_port=""
    wait_count=0
    while [ $wait_count -lt 30 ]; do
        awx_port=$(sudo microk8s kubectl get service awx-service -n $AWX_NAMESPACE \
            -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null)
        
        if [ -n "$awx_port" ]; then
            break
        fi
        
        log_info "Waiting for service port... ($wait_count/30)"
        sleep 10
        ((wait_count++))
    done
    
    if [ -z "$awx_port" ]; then
        awx_port="30080"  # Default port
        log_warn "Using default port: $awx_port"
    fi
    
    # Get node IP
    local node_ip=$(sudo microk8s kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    
    if [ -z "$node_ip" ] || [ "$node_ip" = "127.0.0.1" ]; then
        node_ip=$(hostname -I | awk '{print $1}')
    fi
    
    [ -z "$node_ip" ] && node_ip="localhost"
    
    # Display credentials
    echo
    echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}   🎉 AWX Installation Completed Successfully!${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}📍 AWX URL:${NC}      ${YELLOW}http://$node_ip:$awx_port${NC}"
    echo -e "${CYAN}👤 Username:${NC}     ${YELLOW}admin${NC}"
    echo -e "${CYAN}🔑 Password:${NC}     ${YELLOW}$admin_password${NC}"
    echo
    echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
    echo
    
    # Save comprehensive credentials
    local creds_file="${ARCHIVE_DIR}/awx-credentials-${TIMESTAMP}.txt"
    cat > "$creds_file" <<EOF
════════════════════════════════════════════════════════
AWX Installation Credentials
════════════════════════════════════════════════════════
Installation Date: $(date)
Installation Log:  $LOG_FILE
Archive Directory: $ARCHIVE_DIR
PV Directory:      $PV_DIR

AWX Access:
-----------
URL:      http://$node_ip:$awx_port
Username: admin
Password: $admin_password

System Information:
-------------------
System IP:        $node_ip
AWX Version:      24.6.1
Operator Version: $AWX_OPERATOR_VERSION
Kubernetes:       MicroK8s $MICROK8S_CHANNEL
Namespace:        $AWX_NAMESPACE
PV Size:          $PV_SIZE
PV Path:          $PV_DIR

Useful Commands:
----------------
Check AWX status:
  sudo microk8s kubectl get awx -n $AWX_NAMESPACE
  
Check all pods:
  sudo microk8s kubectl get pods -n $AWX_NAMESPACE
  
View AWX web logs:
  sudo microk8s kubectl logs -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx-web -f
  
View AWX task logs:
  sudo microk8s kubectl logs -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx-task -f
  
Restart AWX:
  sudo microk8s kubectl rollout restart deployment/awx-web -n $AWX_NAMESPACE
  sudo microk8s kubectl rollout restart deployment/awx-task -n $AWX_NAMESPACE

Database Access:
  sudo microk8s kubectl exec -it -n $AWX_NAMESPACE awx-postgres-15-0 -- psql -U awx awx

Backup Command:
  sudo microk8s kubectl exec -it -n $AWX_NAMESPACE awx-postgres-15-0 -- \
    pg_dump -U awx awx > ${ARCHIVE_DIR}/awx-backup-\$(date +%Y%m%d).sql

Repair Installation:
  $0 --repair

Reinstall AWX:
  $0 --reinstall

════════════════════════════════════════════════════════
EOF
    
    chmod 600 "$creds_file"
    log_success "Credentials saved to: $creds_file"
    
    echo -e "${CYAN}📖 Access Instructions:${NC}"
    echo "  1. Open your web browser"
    echo "  2. Navigate to: http://$node_ip:$awx_port"
    echo "  3. Login with the credentials above"
    echo "  4. Wait 2-3 minutes if you see 'Bad Gateway' (AWX is still initializing)"
    echo
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/awx-*.yaml 2>/dev/null || true
    log_success "Cleanup completed"
}

show_post_install_notes() {
    echo
    echo -e "${YELLOW}⚠️  IMPORTANT POST-INSTALLATION NOTES:${NC}"
    echo
    echo -e "${CYAN}1. Data Locations:${NC}"
    echo "   • Logs:           ${LOG_DIR}"
    echo "   • Archive/Config: ${ARCHIVE_DIR}"
    echo "   • Persistent Data: ${PV_DIR}"
    echo
    echo -e "${CYAN}2. Group Permissions:${NC}"
    echo "   Log out and log back in for group changes to take effect"
    echo "   OR run: newgrp docker && newgrp microk8s"
    echo
    echo -e "${CYAN}3. First Access:${NC}"
    echo "   AWX may take 2-3 minutes to be fully accessible"
    echo "   If you see connection errors, wait and refresh your browser"
    echo
    echo -e "${CYAN}4. Firewall:${NC}"
    echo "   If accessing remotely, ensure port is open:"
    echo "   sudo ufw allow 30080/tcp"
    echo
    echo -e "${CYAN}5. Maintenance Commands:${NC}"
    echo "   • Fresh install:  $0 --fresh"
    echo "   • Repair:         $0 --repair"
    echo "   • Reinstall:      $0 --reinstall"
    echo
    echo -e "${CYAN}6. Monitoring:${NC}"
    echo "   • View logs:      tail -f $LOG_FILE"
    echo "   • Main log:       tail -f $MAIN_LOG"
    echo "   • Check status:   sudo microk8s kubectl get pods -n awx"
    echo "   • Check PV:       sudo microk8s kubectl get pv awx-pv"
    echo "   • Check events:   sudo microk8s kubectl get events -n awx"
    echo
    echo -e "${CYAN}7. Troubleshooting:${NC}"
    echo "   • If pods not running: sudo microk8s kubectl describe pod <POD_NAME> -n awx"
    echo "   • View pod logs:       sudo microk8s kubectl logs -n awx <POD_NAME>"
    echo "   • Restart deployment:  sudo microk8s kubectl rollout restart deployment -n awx"
    echo
    log_info "Installation completed at: $(date)"
    echo
}

main() {
    # Parse arguments first
    parse_arguments "$@"
    
    # Initialize directories early
    initialize_directories
    
    # Print banner
    print_banner
    
    # Install essential packages first
    install_essential_packages
    
    # Run pre-flight tests
    run_preflight_tests
    
    # Check system requirements
    check_system
    
    # Confirm installation
    confirm_installation
    
    # Handle reinstall if needed
    handle_reinstall
    
    log_info "Starting AWX installation process..."
    log_info "Installation mode: $INSTALL_MODE"
    log_info "Estimated time: 30-45 minutes"
    echo
    
    # Installation steps
    update_system
    install_docker
    install_microk8s
    configure_microk8s
    
    # Create PV before operator
    create_persistent_volume
    
    install_awx_operator
    create_postgres_secret
    create_awx_instance
    
    # Wait with enhanced monitoring
    wait_for_awx
    
    # Get credentials and finish
    get_awx_credentials
    cleanup
    show_post_install_notes
    
    log_success "🎉 AWX installation completed successfully!"
    log_info "All logs saved to: $LOG_FILE"
    log_info "All configurations archived to: $ARCHIVE_DIR"
    echo
}

# Handle script interruption
trap 'echo; log_error "Script interrupted by user"; cleanup; exit 130' INT TERM

# Run main function with all arguments
main "$@"
