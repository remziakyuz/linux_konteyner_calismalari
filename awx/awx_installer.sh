#!/bin/bash

# AWX Auto Installer Script for Ubuntu 24.04 LTS
# Production Ready - Tested and Working
# MicroK8s with AWX Operator 2.19.1
# Designed by Remzi AKYUZ
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
LOG_FILE="/tmp/awx-installer-$(date +%Y%m%d-%H%M%S).log"

# Get system IP
SYSTEM_IP=$(hostname -I | awk '{print $1}')
[ -z "$SYSTEM_IP" ] && SYSTEM_IP="localhost"

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${MAGENTA}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1" | tee -a "$LOG_FILE"
}

# Error handling
error_exit() {
    log_error "$1"
    log_error "Installation failed! Check log file: $LOG_FILE"
    cleanup_on_error
    exit 1
}

cleanup_on_error() {
    log_warn "Cleaning up after error..."
    rm -f /tmp/awx-deployment.yaml
    rm -f /tmp/awx-postgres-secret.yaml
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    error_exit "This script should not be run as root. Run as a regular user with sudo privileges."
fi

# Check sudo access
if ! sudo -n true 2>/dev/null; then
    log_info "Testing sudo access..."
    sudo -v || error_exit "This script requires sudo privileges"
fi

print_banner() {
    clear
    echo -e "${MAGENTA}===========================================================${NC}"
    echo -e "${GREEN}   🚀 AWX Auto Installer Script - Production Ready${NC}"
    echo -e "${CYAN}   STRICTLY for Ubuntu 24.04 LTS | MicroK8s${NC}"
    echo -e "${CYAN}   AWX Operator: $AWX_OPERATOR_VERSION${NC}"
    echo -e "${MAGENTA}===========================================================${NC}"
    echo
    echo -e "${YELLOW}⚠️  System Requirements:${NC}"
    echo "   • Operating System: Ubuntu 24.04 LTS (REQUIRED)"
    echo "   • CPU Cores:        4+ cores (Recommended)"
    echo "   • RAM:              8GB+ (Recommended)"
    echo "   • Disk Space:       30GB+ free (Recommended)"
    echo "   • Internet:         Active connection (Required)"
    echo
    log_info "Installation log: $LOG_FILE"
    log_info "System IP: $SYSTEM_IP"
    echo
}

confirm_installation() {
    log_warn "This script will install and configure:"
    echo "  ✓ System updates and essential packages"
    echo "  ✓ Docker CE"
    echo "  ✓ MicroK8s Kubernetes ($MICROK8S_CHANNEL)"
    echo "  ✓ AWX Operator $AWX_OPERATOR_VERSION"
    echo "  ✓ AWX (Ansible Automation Platform)"
    echo
    log_warn "Estimated installation time: 30-45 minutes"
    echo
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
        error_exit "lsb_release command not found. Please install lsb-release package first: sudo apt install lsb-release"
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
        log_error ""
        log_error "This script is designed ONLY for Ubuntu 24.04 LTS"
        log_error ""
        log_error "Your system:"
        log_error "  Distribution: $NAME"
        log_error "  ID:          $ID"
        log_error "  Version:     $VERSION"
        log_error ""
        log_error "Required system:"
        log_error "  Distribution: Ubuntu"
        log_error "  ID:          ubuntu"
        log_error "  Version:     24.04"
        log_error ""
        log_error "════════════════════════════════════════════════════════"
        error_exit "Unsupported operating system. Only Ubuntu 24.04 LTS is supported."
    fi
    
    # Check Ubuntu version - Strict version check
    UBUNTU_VERSION=$(lsb_release -rs)
    log_info "Detected Ubuntu version: $UBUNTU_VERSION"
    
    if [[ "$UBUNTU_VERSION" != "24.04" ]]; then
        log_error "════════════════════════════════════════════════════════"
        log_error "  ⚠️  UNSUPPORTED UBUNTU VERSION DETECTED"
        log_error "════════════════════════════════════════════════════════"
        log_error ""
        log_error "This script requires Ubuntu 24.04 LTS"
        log_error ""
        log_error "Your Ubuntu version: $UBUNTU_VERSION"
        log_error "Required version:    24.04"
        log_error ""
        log_error "Reasons for strict version requirement:"
        log_error "  • Package compatibility"
        log_error "  • Kernel version requirements"
        log_error "  • MicroK8s snap compatibility"
        log_error "  • Docker CE repository compatibility"
        log_error ""
        log_error "════════════════════════════════════════════════════════"
        error_exit "Unsupported Ubuntu version. Please use Ubuntu 24.04 LTS."
    fi
    
    log_success "Operating System: Ubuntu $UBUNTU_VERSION ✓"
    
    # Verify it's actually Ubuntu 24.04 from multiple sources
    if [ -f /etc/lsb-release ]; then
        local distrib_id=$(grep "^DISTRIB_ID=" /etc/lsb-release | cut -d= -f2)
        local distrib_release=$(grep "^DISTRIB_RELEASE=" /etc/lsb-release | cut -d= -f2)
        
        if [[ "$distrib_id" != "Ubuntu" ]] || [[ "$distrib_release" != "24.04" ]]; then
            log_error "════════════════════════════════════════════════════════"
            log_error "  ⚠️  SYSTEM VERIFICATION FAILED"
            log_error "════════════════════════════════════════════════════════"
            log_error ""
            log_error "Cross-check with /etc/lsb-release failed:"
            log_error "  DISTRIB_ID:      $distrib_id (expected: Ubuntu)"
            log_error "  DISTRIB_RELEASE: $distrib_release (expected: 24.04)"
            log_error ""
            log_error "════════════════════════════════════════════════════════"
            error_exit "System verification failed. Your system may have been modified."
        fi
    fi
    
    log_info "System verification passed ✓"
    
    # Check CPU cores
    CPU_CORES=$(nproc)
    if [[ $CPU_CORES -lt 4 ]]; then
        log_warn "System has only $CPU_CORES CPU cores. Recommended: 4+ cores"
        log_warn "AWX may run slowly with fewer than 4 CPU cores"
    else
        log_info "CPU cores: $CPU_CORES ✓"
    fi
    
    # Check memory
    MEMORY_GB=$(free -g | awk '/^Mem:/ {print $2}')
    if [[ $MEMORY_GB -lt 8 ]]; then
        log_warn "System has only ${MEMORY_GB}GB RAM. Recommended: 8GB+"
        log_warn "AWX requires at least 8GB RAM for optimal performance"
        read -p "Continue anyway? This may cause installation failure (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user due to insufficient RAM"
            exit 0
        fi
    else
        log_info "System memory: ${MEMORY_GB}GB ✓"
    fi
    
    # Check disk space (in GB)
    DISK_SPACE_GB=$(df -BG / | awk 'NR==2 {gsub("G","",$4); print $4}')
    if [[ $DISK_SPACE_GB -lt 30 ]]; then
        log_warn "Available disk space: ${DISK_SPACE_GB}GB. Recommended: 30GB+"
        log_warn "AWX installation requires approximately 20-30GB of disk space"
        read -p "Continue anyway? This may cause installation failure (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user due to insufficient disk space"
            exit 0
        fi
    else
        log_info "Disk space: ${DISK_SPACE_GB}GB ✓"
    fi
    
    # Check internet connectivity
    log_info "Checking internet connectivity..."
    if ! ping -c 1 -W 5 8.8.8.8 &> /dev/null; then
        if ! ping -c 1 -W 5 1.1.1.1 &> /dev/null; then
            error_exit "No internet connection detected. Please check your network connection."
        fi
    fi
    log_info "Internet connectivity ✓"
    
    # Check if ports are available
    log_info "Checking if required ports are available..."
    if command -v netstat &> /dev/null || command -v ss &> /dev/null; then
        # Check if port 16443 (MicroK8s API) is in use
        if sudo netstat -tuln 2>/dev/null | grep -q ":16443 " || sudo ss -tuln 2>/dev/null | grep -q ":16443 "; then
            log_warn "Port 16443 is already in use. This may conflict with MicroK8s."
        fi
    fi
    
    log_success "System requirements check completed"
    echo
}

update_system() {
    log_step "Updating system packages..."
    
    sudo apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Failed to update package lists"
    
    # Install essential packages
    log_info "Installing essential packages..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        wget \
        git \
        vim \
        tmux \
        net-tools bind9-dnsutils  bind9-utils \
	build-essential g++-multilib  gcc-multilib autoconf automake libtool flex bison gdb autoconf-archive gnu-standards iputils-ping \
        gnupg \
        lsb-release \
        software-properties-common \
        jq \
        openssl >> "$LOG_FILE" 2>&1 || error_exit "Failed to install essential packages"
    
    log_success "System packages updated successfully"
    echo
}

install_docker() {
    log_step "Installing Docker CE..."
    
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        log_info "Docker is already installed: $DOCKER_VERSION"
        
        # Check if user is in docker group
        if groups $USER | grep -q docker; then
            log_info "User is already in docker group ✓"
        else
            log_info "Adding user to docker group..."
            sudo usermod -aG docker $USER
        fi
        echo
        return 0
    fi
    
    log_info "Installing Docker CE..."
    
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc >> "$LOG_FILE" 2>&1 || true
    
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg >> "$LOG_FILE" 2>&1
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update >> "$LOG_FILE" 2>&1 || error_exit "Failed to update after adding Docker repo"
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to install Docker"
    
    # Start and enable Docker
    sudo systemctl enable docker >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable Docker"
    sudo systemctl start docker >> "$LOG_FILE" 2>&1 || error_exit "Failed to start Docker"
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    
    # Verify Docker installation
    if sudo docker run hello-world >> "$LOG_FILE" 2>&1; then
        log_success "Docker installed and verified successfully"
    else
        error_exit "Docker installation verification failed"
    fi
    echo
}

install_microk8s() {
    log_step "Installing MicroK8s..."
    
    if command -v microk8s &> /dev/null; then
        log_info "MicroK8s is already installed"
        MICROK8S_VERSION=$(microk8s version 2>/dev/null || echo "unknown")
        log_info "MicroK8s version: $MICROK8S_VERSION"
    else
        # Check if snap is installed
        if ! command -v snap &> /dev/null; then
            log_info "Installing snapd..."
            sudo apt-get update >> "$LOG_FILE" 2>&1
            sudo apt-get install -y snapd >> "$LOG_FILE" 2>&1 || error_exit "Failed to install snapd"
            sudo systemctl enable snapd.socket >> "$LOG_FILE" 2>&1
            sudo systemctl start snapd.socket >> "$LOG_FILE" 2>&1
        fi
        
        # Wait for snap to be ready
        log_info "Waiting for snap to be ready..."
        sudo snap wait system seed.loaded >> "$LOG_FILE" 2>&1 || error_exit "Snap failed to initialize"
        
        # Install MicroK8s
        log_info "Installing MicroK8s (this may take a few minutes)..."
        sudo snap install microk8s --classic --channel=$MICROK8S_CHANNEL >> "$LOG_FILE" 2>&1 || \
            error_exit "Failed to install MicroK8s"
        
        sleep 5
    fi
    
    # Add user to microk8s group
    log_info "Configuring user permissions..."
    sudo usermod -a -G microk8s $USER >> "$LOG_FILE" 2>&1 || error_exit "Failed to add user to microk8s group"
    
    # Create .kube directory
    mkdir -p ~/.kube
    sudo chown -R $USER ~/.kube
    
    # Wait for MicroK8s to be ready
    log_info "Waiting for MicroK8s to be ready..."
    sudo microk8s status --wait-ready --timeout 300 >> "$LOG_FILE" 2>&1 || error_exit "MicroK8s failed to start"
    
    log_success "MicroK8s is ready"
    echo
}

configure_microk8s() {
    log_step "Configuring MicroK8s addons..."
    
    # Enable DNS addon
    log_info "Enabling DNS addon..."
    sudo microk8s enable dns >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable DNS addon"
    sleep 15
    
    # Enable storage addon
    log_info "Enabling storage addon..."
    sudo microk8s enable hostpath-storage >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable storage addon"
    sleep 15
    
    # Enable ingress addon
    log_info "Enabling ingress addon..."
    sudo microk8s enable ingress >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable ingress addon"
    sleep 15
    
    # Enable helm3 addon
    log_info "Enabling helm3 addon..."
    sudo microk8s enable helm3 >> "$LOG_FILE" 2>&1 || error_exit "Failed to enable helm3 addon"
    sleep 10
    
    # Set up kubectl alias
    log_info "Setting up kubectl alias..."
    if ! command -v kubectl &> /dev/null; then
        sudo snap alias microk8s.kubectl kubectl >> "$LOG_FILE" 2>&1 || log_warn "Failed to create kubectl alias"
    fi
    
    # Configure kubeconfig
    log_info "Configuring kubeconfig..."
    sudo microk8s kubectl config view --raw > ~/.kube/config 2>> "$LOG_FILE"
    chmod 600 ~/.kube/config
    
    # Wait for all system pods to be ready
    log_info "Waiting for all system pods to be ready (this may take 2-3 minutes)..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if sudo microk8s kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=10s >> "$LOG_FILE" 2>&1; then
            log_success "All system pods are ready"
            break
        fi
        attempt=$((attempt + 1))
        if [ $((attempt % 3)) -eq 0 ]; then
            log_info "Still waiting for system pods... (attempt $attempt/$max_attempts)"
        fi
        sleep 10
    done
    
    # Verify cluster
    log_info "Verifying Kubernetes cluster..."
    sudo microk8s kubectl cluster-info >> "$LOG_FILE" 2>&1 || log_warn "Failed to get cluster info"
    sudo microk8s kubectl get nodes >> "$LOG_FILE" 2>&1 || log_warn "Failed to get nodes"
    
    log_success "MicroK8s configured successfully"
    echo
}

install_awx_operator() {
    log_step "Installing AWX Operator $AWX_OPERATOR_VERSION..."
    
    # Create namespace
    log_info "Creating namespace: $AWX_NAMESPACE"
    sudo microk8s kubectl create namespace $AWX_NAMESPACE --dry-run=client -o yaml | \
        sudo microk8s kubectl apply -f - >> "$LOG_FILE" 2>&1 || error_exit "Failed to create namespace"
    
    # Set current namespace
    sudo microk8s kubectl config set-context --current --namespace=$AWX_NAMESPACE >> "$LOG_FILE" 2>&1
    
    # Download and apply AWX operator directly from GitHub releases
    log_info "Downloading AWX Operator manifests..."
    
    # Create temporary directory for operator files
    local temp_dir=$(mktemp -d)
    local current_dir=$(pwd)
    cd "$temp_dir" || error_exit "Failed to create temp directory"
    
    # Download the operator release
    log_info "Downloading operator release $AWX_OPERATOR_VERSION..."
    if ! curl -sL "https://github.com/ansible/awx-operator/archive/refs/tags/$AWX_OPERATOR_VERSION.tar.gz" -o awx-operator.tar.gz >> "$LOG_FILE" 2>&1; then
        cd "$current_dir"
        rm -rf "$temp_dir"
        error_exit "Failed to download AWX Operator"
    fi
    
    # Extract the archive
    log_info "Extracting operator files..."
    tar -xzf awx-operator.tar.gz >> "$LOG_FILE" 2>&1 || {
        cd "$current_dir"
        rm -rf "$temp_dir"
        error_exit "Failed to extract operator archive"
    }
    
    # Find the extracted directory (it might have a different name)
    local operator_dir=$(find . -maxdepth 1 -type d -name "awx-operator-*" | head -n 1)
    
    if [ -z "$operator_dir" ]; then
        cd "$current_dir"
        rm -rf "$temp_dir"
        error_exit "Failed to find extracted operator directory"
    fi
    
    log_info "Found operator directory: $operator_dir"
    cd "$operator_dir" || {
        cd "$current_dir"
        rm -rf "$temp_dir"
        error_exit "Failed to enter operator directory"
    }
    
    # Install kustomize if not present
    if [ ! -f "bin/kustomize" ]; then
        log_info "Installing kustomize..."
        make kustomize >> "$LOG_FILE" 2>&1 || {
            cd "$current_dir"
            rm -rf "$temp_dir"
            error_exit "Failed to install kustomize"
        }
    fi
    
    # Generate the manifests
    log_info "Generating operator manifests..."
    export NAMESPACE=$AWX_NAMESPACE
    if ! ./bin/kustomize build config/default > /tmp/awx-operator-install.yaml 2>> "$LOG_FILE"; then
        cd "$current_dir"
        rm -rf "$temp_dir"
        error_exit "Failed to generate operator manifests"
    fi
    
    # Apply the operator
    log_info "Applying AWX Operator to cluster..."
    if ! sudo microk8s kubectl apply -f /tmp/awx-operator-install.yaml >> "$LOG_FILE" 2>&1; then
        cd "$current_dir"
        rm -rf "$temp_dir"
        rm -f /tmp/awx-operator-install.yaml
        error_exit "Failed to deploy AWX Operator"
    fi
    
    # Cleanup
    cd "$current_dir" || true
    rm -rf "$temp_dir"
    rm -f /tmp/awx-operator-install.yaml
    
    log_info "AWX Operator manifests applied successfully"
    
    # Wait for operator to be ready
    log_info "Waiting for AWX Operator to be ready..."
    local max_wait=600
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        if sudo microk8s kubectl wait --for=condition=ready pod \
            -l control-plane=controller-manager \
            -n $AWX_NAMESPACE \
            --timeout=30s >> "$LOG_FILE" 2>&1; then
            log_success "AWX Operator is ready"
            return 0
        fi
        elapsed=$((elapsed + 30))
        if [ $((elapsed % 60)) -eq 0 ]; then
            log_info "Still waiting for operator... ($elapsed/$max_wait seconds)"
        fi
        sleep 30
    done
    
    error_exit "Timeout waiting for AWX Operator to be ready"
}

create_postgres_secret() {
    log_info "Creating PostgreSQL configuration secret..."
    
    # Generate secure password
    PG_PASSWORD=$(openssl rand -base64 32)
    
    cat > /tmp/awx-postgres-secret.yaml <<EOF
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
  password: $PG_PASSWORD
  type: managed
EOF
    
    sudo microk8s kubectl apply -f /tmp/awx-postgres-secret.yaml >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to create PostgreSQL secret"
    
    rm -f /tmp/awx-postgres-secret.yaml
    log_success "PostgreSQL secret created"
}

create_awx_instance() {
    log_step "Creating AWX instance..."
    
    # Get NodePort for URL (will be assigned after service creation)
    log_info "Preparing AWX deployment configuration..."
    
    # Create AWX deployment configuration with CSRF fixes
    cat > /tmp/awx-deployment.yaml <<EOF
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
  namespace: $AWX_NAMESPACE
spec:
  service_type: nodeport
  ingress_type: none
  hostname: $SYSTEM_IP
  
  postgres_storage_class: microk8s-hostpath
  postgres_configuration_secret: awx-postgres-configuration
  
  # Security and CSRF settings for HTTP NodePort access
  extra_settings:
    - setting: CSRF_TRUSTED_ORIGINS
      value: "['http://$SYSTEM_IP:30080', 'http://$SYSTEM_IP', 'http://localhost:30080', 'http://127.0.0.1:30080']"
    - setting: SESSION_COOKIE_SECURE
      value: "False"
    - setting: CSRF_COOKIE_SECURE
      value: "False"
  
  # Resource requirements
  web_resource_requirements:
    requests:
      cpu: 1000m
      memory: 2Gi
    limits:
      cpu: 2000m
      memory: 4Gi
  
  task_resource_requirements:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
  
  postgres_resource_requirements:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
  
  postgres_storage_requirements:
    requests:
      storage: 8Gi
EOF
    
    # Apply AWX deployment
    log_info "Applying AWX deployment configuration..."
    sudo microk8s kubectl apply -f /tmp/awx-deployment.yaml >> "$LOG_FILE" 2>&1 || \
        error_exit "Failed to apply AWX deployment"
    
    log_success "AWX instance creation initiated"
    log_info "AWX deployment may take 15-25 minutes to complete..."
    echo
}

wait_for_awx() {
    log_step "Waiting for AWX to be ready..."
    
    local timeout=2400
    local start_time=$(date +%s)
    local last_status=""
    local check_interval=30
    
    log_info "This process will take approximately 15-25 minutes"
    log_info "You can monitor progress in another terminal with:"
    log_info "  watch -n 5 'sudo microk8s kubectl get pods -n awx'"
    echo
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -ge $timeout ]; then
            error_exit "Timeout waiting for AWX to be ready after $((timeout/60)) minutes"
        fi
        
        local awx_status=$(sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE \
            -o jsonpath='{.status.conditions[?(@.type=="Running")].status}' 2>/dev/null || echo "Unknown")
        
        local pod_count=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep -v "Completed" | wc -l)
        local ready_pods=$(sudo microk8s kubectl get pods -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep -v "Completed" | grep "Running" | wc -l)
        
        if [ "$awx_status" != "$last_status" ] || [ $((elapsed % 120)) -eq 0 ]; then
            log_info "Progress: ${ready_pods}/${pod_count} pods running | AWX status: $awx_status | Elapsed: $((elapsed/60)) min"
            last_status="$awx_status"
        fi
        
        if [ "$awx_status" = "True" ]; then
            log_success "AWX is running!"
            break
        fi
        
        local error_msg=$(sudo microk8s kubectl get awx awx -n $AWX_NAMESPACE \
            -o jsonpath='{.status.conditions[?(@.type=="Failure")].message}' 2>/dev/null)
        
        if [ -n "$error_msg" ]; then
            error_exit "AWX deployment failed: $error_msg"
        fi
        
        sleep $check_interval
    done
    
    log_info "Waiting for all AWX pods to be ready..."
    sudo microk8s kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=awx \
        -n $AWX_NAMESPACE \
        --timeout=600s >> "$LOG_FILE" 2>&1 || log_warn "Some pods may not be ready yet"
    
    log_info "Finalizing AWX setup..."
    sleep 30
    
    log_success "AWX is fully ready!"
    echo
}

get_awx_credentials() {
    log_step "Retrieving AWX access information..."
    
    log_info "Waiting for admin password secret..."
    local max_wait=300
    local elapsed=0
    
    while [ $elapsed -lt $max_wait ]; do
        if sudo microk8s kubectl get secret awx-admin-password -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    local admin_password=$(sudo microk8s kubectl get secret awx-admin-password \
        -n $AWX_NAMESPACE \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)
    
    if [ -z "$admin_password" ]; then
        log_warn "Failed to retrieve admin password, retrying..."
        sleep 30
        admin_password=$(sudo microk8s kubectl get secret awx-admin-password \
            -n $AWX_NAMESPACE \
            -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)
    fi
    
    if [ -z "$admin_password" ]; then
        error_exit "Failed to retrieve admin password after retries"
    fi
    
    # Wait for service to be created
    log_info "Waiting for AWX service to be created..."
    elapsed=0
    max_wait=300
    
    while [ $elapsed -lt $max_wait ]; do
        if sudo microk8s kubectl get service awx-service -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1; then
            log_info "AWX service found"
            break
        fi
        log_info "Waiting for service... ($elapsed/$max_wait seconds)"
        sleep 10
        elapsed=$((elapsed + 10))
    done
    
    # Get AWX service NodePort with retries
    local awx_port=""
    local retry_count=0
    local max_retries=10
    
    while [ $retry_count -lt $max_retries ]; do
        awx_port=$(sudo microk8s kubectl get service awx-service \
            -n $AWX_NAMESPACE \
            -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null)
        
        if [ -n "$awx_port" ]; then
            log_info "AWX service port: $awx_port"
            break
        fi
        
        log_info "Waiting for service port to be assigned... (attempt $((retry_count + 1))/$max_retries)"
        sleep 10
        retry_count=$((retry_count + 1))
    done
    
    if [ -z "$awx_port" ]; then
        log_warn "Failed to retrieve NodePort automatically"
        log_info "Checking all services in awx namespace..."
        sudo microk8s kubectl get services -n $AWX_NAMESPACE >> "$LOG_FILE" 2>&1
        
        # Try to get any port from the service
        awx_port=$(sudo microk8s kubectl get service -n $AWX_NAMESPACE --no-headers 2>/dev/null | grep awx-service | awk '{print $5}' | cut -d: -f2 | cut -d/ -f1)
        
        if [ -z "$awx_port" ]; then
            log_error "Could not retrieve AWX service port"
            log_info "You can get the port manually with:"
            log_info "  sudo microk8s kubectl get service awx-service -n awx"
            
            # Still show what we can
            local node_ip=$(sudo microk8s kubectl get nodes \
                -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
            
            if [ -z "$node_ip" ] || [ "$node_ip" = "127.0.0.1" ]; then
                node_ip=$(hostname -I | awk '{print $1}')
            fi
            
            [ -z "$node_ip" ] && node_ip="localhost"
            
            echo
            echo -e "${MAGENTA}============================================================${NC}"
            echo -e "${GREEN}   🎉 AWX Installation Completed!${NC}"
            echo -e "${MAGENTA}============================================================${NC}"
            echo
            echo -e "${CYAN}📍 AWX URL:${NC}      ${YELLOW}http://$node_ip:<PORT>${NC}"
            echo -e "${CYAN}👤 Username:${NC}     ${YELLOW}admin${NC}"
            echo -e "${CYAN}🔑 Password:${NC}     ${YELLOW}$admin_password${NC}"
            echo
            echo -e "${YELLOW}⚠️  Please run this command to get the port:${NC}"
            echo -e "   ${CYAN}sudo microk8s kubectl get service awx-service -n awx${NC}"
            echo
            
            # Save credentials
            local creds_file="$HOME/awx-credentials.txt"
            cat > "$creds_file" <<EOF
============================================================
AWX Installation Credentials
============================================================
Installation Date: $(date)

AWX Access:
-----------
URL:      http://$node_ip:<PORT>
Username: admin
Password: $admin_password

To get the port number, run:
  sudo microk8s kubectl get service awx-service -n awx

============================================================
EOF
            chmod 600 "$creds_file"
            log_info "Partial credentials saved to: $creds_file"
            return 0
        fi
    fi
    
    # Get node IP
    local node_ip=$(sudo microk8s kubectl get nodes \
        -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    
    if [ -z "$node_ip" ] || [ "$node_ip" = "127.0.0.1" ]; then
        node_ip=$(hostname -I | awk '{print $1}')
    fi
    
    [ -z "$node_ip" ] && node_ip="localhost"
    
    echo
    echo -e "${MAGENTA}============================================================${NC}"
    echo -e "${GREEN}   🎉 AWX Installation Completed Successfully!${NC}"
    echo -e "${MAGENTA}============================================================${NC}"
    echo
    echo -e "${CYAN}📍 AWX URL:${NC}      ${YELLOW}http://$node_ip:$awx_port${NC}"
    echo -e "${CYAN}👤 Username:${NC}     ${YELLOW}admin${NC}"
    echo -e "${CYAN}🔑 Password:${NC}     ${YELLOW}$admin_password${NC}"
    echo
    echo -e "${MAGENTA}============================================================${NC}"
    echo
    
    echo -e "${CYAN}📖 Access Instructions:${NC}"
    echo "  1. Open your web browser"
    echo "  2. Navigate to: http://$node_ip:$awx_port"
    echo "  3. Login with the credentials above"
    echo "  4. Wait 2-3 minutes if you see 'Bad Gateway' (AWX is still starting)"
    echo
    
    echo -e "${CYAN}🛠️  Useful Management Commands:${NC}"
    echo "  Check AWX status:     sudo microk8s kubectl get awx -n awx"
    echo "  Check pods:           sudo microk8s kubectl get pods -n awx"
    echo "  View web logs:        sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-web -f"
    echo "  View task logs:       sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-task -f"
    echo "  Restart AWX web:      sudo microk8s kubectl rollout restart deployment/awx-web -n awx"
    echo "  Restart AWX task:     sudo microk8s kubectl rollout restart deployment/awx-task -n awx"
    echo
    
    local creds_file="$HOME/awx-credentials.txt"
    cat > "$creds_file" <<EOF
============================================================
AWX Installation Credentials
============================================================
Installation Date: $(date)
Installation Log:  $LOG_FILE

AWX Access:
-----------
URL:      http://$node_ip:$awx_port
Username: admin
Password: $admin_password

System Information:
-------------------
System IP:     $node_ip
AWX Version:   24.6.1
Operator:      $AWX_OPERATOR_VERSION
Kubernetes:    MicroK8s $MICROK8S_CHANNEL

Useful Commands:
----------------
Check AWX status:
  sudo microk8s kubectl get awx -n awx
  
Check all pods:
  sudo microk8s kubectl get pods -n awx
  
View logs:
  sudo microk8s kubectl logs -n awx -l app.kubernetes.io/name=awx-web -f
  
Restart AWX:
  sudo microk8s kubectl rollout restart deployment/awx-web -n awx
  sudo microk8s kubectl rollout restart deployment/awx-task -n awx

Database Access:
  sudo microk8s kubectl exec -it -n awx awx-postgres-15-0 -- psql -U awx awx

Backup Command:
  sudo microk8s kubectl exec -it -n awx awx-postgres-15-0 -- \
    pg_dump -U awx awx > awx-backup-\$(date +%Y%m%d).sql

============================================================
EOF
    
    chmod 600 "$creds_file"
    log_success "Credentials saved to: $creds_file"
    echo
}

cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f /tmp/awx-deployment.yaml
    rm -f /tmp/awx-postgres-secret.yaml
}

show_post_install_notes() {
    echo
    echo -e "${YELLOW}⚠️  IMPORTANT POST-INSTALLATION NOTES:${NC}"
    echo
    echo -e "${CYAN}1. Group Permissions:${NC}"
    echo "   You need to log out and log back in for group changes to take effect"
    echo "   OR run: newgrp docker && newgrp microk8s"
    echo
    echo -e "${CYAN}2. First Access:${NC}"
    echo "   AWX may take 2-3 minutes to be fully accessible after installation"
    echo "   If you see connection errors, wait and refresh your browser"
    echo
    echo -e "${CYAN}3. Firewall Configuration:${NC}"
    echo "   If accessing from another machine, ensure the NodePort is open:"
    echo "   sudo ufw allow [port]/tcp"
    echo
    echo -e "${CYAN}4. Troubleshooting:${NC}"
    echo "   - Check logs: $LOG_FILE"
    echo "   - Check pods: sudo microk8s kubectl get pods -n awx"
    echo "   - Check events: sudo microk8s kubectl get events -n awx --sort-by='.lastTimestamp'"
    echo
    echo -e "${CYAN}5. Backup & Maintenance:${NC}"
    echo "   - Regular backups recommended (see credentials file)"
    echo "   - Monitor resource usage: sudo microk8s kubectl top pods -n awx"
    echo "   - Update AWX: Refer to official documentation"
    echo
    log_info "Installation log saved to: $LOG_FILE"
    echo
}

main() {
    print_banner
    confirm_installation
    check_system
    
    log_info "Starting AWX installation process..."
    log_info "Estimated time: 30-45 minutes"
    echo
    
    # Installation steps
    update_system
    install_docker
    install_microk8s
    configure_microk8s
    install_awx_operator
    echo
    create_postgres_secret
    create_awx_instance
    wait_for_awx
    get_awx_credentials
    cleanup
    show_post_install_notes
    
    log_success "🎉 AWX installation completed successfully!"
    echo
}

# Handle script interruption
trap 'echo; log_error "Script interrupted by user"; cleanup; exit 130' INT TERM

# Run main function
main
