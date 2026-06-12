#!/bin/bash
# Genera certificado TLS autofirmado para CircleGuard (dev/Minikube).
# Ejecutar una sola vez antes de aplicar tls.yaml.
#
# Uso: bash k8s/dev/security/generate-tls.sh

set -e

NAMESPACE="dev"
SECRET_NAME="circleguard-tls"
DOMAIN="circleguard.local"
CERT_DIR=$(mktemp -d)

echo "[1/4] Generando clave privada y certificado autofirmado para $DOMAIN..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout "$CERT_DIR/tls.key" \
  -out    "$CERT_DIR/tls.crt" \
  -subj   "/CN=$DOMAIN/O=CircleGuard/C=CO" \
  -addext "subjectAltName=DNS:$DOMAIN,DNS:grafana.$DOMAIN,DNS:kibana.$DOMAIN,DNS:jaeger.$DOMAIN"

echo "[2/4] Creando/actualizando Secret TLS en namespace $NAMESPACE..."
kubectl create secret tls "$SECRET_NAME" \
  --cert="$CERT_DIR/tls.crt" \
  --key="$CERT_DIR/tls.key" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "[3/4] Limpiando archivos temporales..."
rm -rf "$CERT_DIR"

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "<minikube-ip>")
echo "[4/4] Listo. Agrega las siguientes líneas a /etc/hosts:"
echo ""
echo "  $MINIKUBE_IP  $DOMAIN"
echo "  $MINIKUBE_IP  grafana.$DOMAIN"
echo "  $MINIKUBE_IP  kibana.$DOMAIN"
echo "  $MINIKUBE_IP  jaeger.$DOMAIN"
echo ""
echo "Acceso HTTPS: https://$DOMAIN/api/..."
