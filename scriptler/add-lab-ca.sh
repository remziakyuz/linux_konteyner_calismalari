#!/usr/bin/env bash
# add-lab-ca.sh — install local CA for registry.lab.akyuz.tech
# Usage: sudo ./add-lab-ca.sh /path/to/lab-ca.crt

set -e

CA_SRC="$1"
CA_NAME="lab-ca.crt"
REGISTRY_HOST="registry.lab.akyuz.tech"

if [[ -z "$CA_SRC" ]]; then
  echo "❌ Usage: sudo ./add-lab-ca.sh /path/to/lab-ca.crt"
  exit 1
fi

if [[ ! -f "$CA_SRC" ]]; then
  echo "❌ File not found: $CA_SRC"
  exit 1
fi

echo "🔹 Installing CA for Podman registry: $REGISTRY_HOST"

# System CA trust
echo "→ Copying to /etc/pki/ca-trust/source/anchors/"
cp "$CA_SRC" /etc/pki/ca-trust/source/anchors/$CA_NAME
update-ca-trust extract

# Podman-specific CA trust
echo "→ Copying to /etc/containers/certs.d/$REGISTRY_HOST/"
mkdir -p /etc/containers/certs.d/$REGISTRY_HOST/
cp "$CA_SRC" /etc/containers/certs.d/$REGISTRY_HOST/ca.crt

# Registry config check
if [[ -f /etc/containers/registries.conf ]]; then
  grep -q "$REGISTRY_HOST" /etc/containers/registries.conf || {
    echo "⚠️  $REGISTRY_HOST not found in registries.conf — consider adding it manually."
  }
fi

echo "✅ CA installation completed."
echo "You can now run:"
echo "  podman pull $REGISTRY_HOST/rockylinux/rockylinux"
