#!/bin/bash
# awx-management.sh - AWX Yönetim Scripti
# Designed by Remzi AKYUZ
# remzi@akyuz.tech

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

AWX_NAMESPACE="awx"

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_status() {
    echo "=== Kubernetes Cluster Status ==="
    kubectl cluster-info
    echo ""
    
    echo "=== AWX Instance Status ==="
    kubectl get awx -n $AWX_NAMESPACE 2>/dev/null || echo "AWX instance not found"
    echo ""
    
    echo "=== AWX Pods Status ==="
    kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx
    echo ""
    
    echo "=== Operator Status ==="
    kubectl get pods -n $AWX_NAMESPACE -l name=awx-operator
    echo ""
    
    echo "=== All Pods in AWX Namespace ==="
    kubectl get pods -n $AWX_NAMESPACE
    echo ""
    
    echo "=== Services ==="
    kubectl get services -n $AWX_NAMESPACE
    echo ""
    
    echo "=== Persistent Volumes ==="
    kubectl get pvc -n $AWX_NAMESPACE
}

show_logs() {
    local pod_name=$(kubectl get pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -z "$pod_name" ]]; then
        log_error "No AWX pod found"
        exit 1
    fi
    
    log_info "Showing logs for pod: $pod_name"
    kubectl logs -n $AWX_NAMESPACE -f $pod_name
}

show_credentials() {
    if kubectl get secret awx-admin-password -n $AWX_NAMESPACE &> /dev/null; then
        ADMIN_PASSWORD=$(kubectl get secret awx-admin-password -n $AWX_NAMESPACE -o jsonpath='{.data.password}' | base64 --decode)
        AWX_SERVICE=$(kubectl get service awx-service -n $AWX_NAMESPACE -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' || echo "localhost")
        
        echo "=================================================="
        echo "AWX Connection Information:"
        echo "=================================================="
        echo "URL:      http://$NODE_IP:$AWX_SERVICE"
        echo "Username: admin"
        echo "Password: $ADMIN_PASSWORD"
        echo "=================================================="
    else
        log_error "AWX admin password secret not found"
        log_info "AWX might still be initializing. Try again in a few minutes."
    fi
}

restart_awx() {
    log_info "Restarting AWX..."
    
    # Delete AWX pods (they will be recreated by the operator)
    kubectl delete pods -n $AWX_NAMESPACE -l app.kubernetes.io/name=awx
    
    log_info "AWX pods are restarting..."
    log_info "You can check status with: $0 status"
}

uninstall_awx() {
    log_warn "This will completely uninstall AWX and all its data!"
    read -p "Are you sure you want to continue? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    log_info "Uninstalling AWX..."
    
    # Delete AWX instance
    kubectl delete awx awx -n $AWX_NAMESPACE --ignore-not-found=true
    
    # Delete operator
    kubectl delete -f awx-operator/config/default/ --ignore-not-found=true
    
    # Delete namespace
    kubectl delete namespace $AWX_NAMESPACE --ignore-not-found=true
    
    # Clean up CRDs
    kubectl get crd -o name | grep awx | xargs kubectl delete --ignore-not-found=true
    
    log_info "AWX uninstalled successfully"
}

show_usage() {
    echo "Usage: $0 {status|logs|credentials|restart|uninstall|help}"
    echo ""
    echo "Commands:"
    echo "  status      - Show AWX and Kubernetes status"
    echo "  logs        - Show AWX application logs"
    echo "  credentials - Show AWX connection credentials"
    echo "  restart     - Restart AWX pods"
    echo "  uninstall   - Completely uninstall AWX (warning: destroys data)"
    echo "  help        - Show this help message"
}

case "$1" in
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    credentials)
        show_credentials
        ;;
    restart)
        restart_awx
        ;;
    uninstall)
        uninstall_awx
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        echo "Unknown command: $1"
        echo ""
        show_usage
        exit 1
        ;;
esac