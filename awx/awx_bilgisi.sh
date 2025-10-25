# Admin şifresi
sudo microk8s kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 --decode
echo

# Service ve Port bilgisi
sudo microk8s kubectl get service awx-service -n awx

# Tam bilgi
NODE_IP=$(hostname -I | awk '{print $1}')
NODE_PORT=$(sudo microk8s kubectl get service awx-service -n awx -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
ADMIN_PASS=$(sudo microk8s kubectl get secret awx-admin-password -n awx -o jsonpath='{.data.password}' | base64 --decode)

echo "============================================"
echo "AWX URL:      http://$NODE_IP:$NODE_PORT"
echo "Username:     admin"
echo "Password:     $ADMIN_PASS"
echo "============================================"
