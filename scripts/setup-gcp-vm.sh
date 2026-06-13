#!/usr/bin/env bash
# Configura la VM de GCP con k3s, Docker y el proyecto CircleGuard.
# Ejecutar en la VM después de conectarse por SSH.

set -euo pipefail

log() { echo ""; echo "▶  $*"; echo ""; }

# ── 1. Actualizar sistema ─────────────────────────────────────────────────────
log "Actualizando paquetes..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# ── 2. Instalar Docker ────────────────────────────────────────────────────────
log "Instalando Docker..."
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"

# ── 3. Instalar k3s ──────────────────────────────────────────────────────────
log "Instalando k3s..."
curl -sfL https://get.k3s.io | sh -

# Configurar kubeconfig accesible sin sudo
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config
chmod 600 ~/.kube/config

# ── 4. Instalar herramientas ─────────────────────────────────────────────────
log "Instalando kubectl, Terraform, Trivy, Java..."

# kubectl (cliente standalone, aunque k3s ya incluye uno)
curl -LO "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Terraform
sudo apt-get install -y -qq gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update -qq && sudo apt-get install -y terraform

# Trivy
sudo apt-get install -y -qq wget apt-transport-https gnupg
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb generic main" \
  | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update -qq && sudo apt-get install -y trivy

# Java 21 (para Gradle si se compila en la VM)
sudo apt-get install -y -qq openjdk-21-jdk

# Node.js 20 (para el frontend)
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y -qq nodejs

# Python 3 + pip (para tests E2E y Locust)
sudo apt-get install -y -qq python3 python3-pip

# ── 5. Jenkins (contenedor Docker) ───────────────────────────────────────────
log "Levantando Jenkins en Docker..."
sudo mkdir -p /var/jenkins_home && sudo chown 1000:1000 /var/jenkins_home

# Necesita acceso a Docker y a kubectl desde dentro del contenedor
newgrp docker <<'DOCKERGRP'
docker run -d \
  --name jenkins \
  --restart=unless-stopped \
  -p 8080:8080 \
  -v /var/jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$HOME/.kube/config:/root/.kube/config:ro" \
  -v /usr/local/bin/kubectl:/usr/local/bin/kubectl:ro \
  -v /usr/local/bin/trivy:/usr/local/bin/trivy:ro \
  jenkins/jenkins:lts-jdk21
DOCKERGRP

# ── 6. Verificación ───────────────────────────────────────────────────────────
log "Verificando instalaciones..."
kubectl get nodes
docker --version
terraform version
trivy --version
java --version

log "Setup completado."
echo ""
echo "════════════════════════════════════════════"
echo "  Accesos:"
echo "  Jenkins  → http://$(curl -s ifconfig.me):8080"
echo "  K8s API  → kubectl ya configurado"
echo ""
echo "  Contraseña inicial de Jenkins:"
echo "  docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo "════════════════════════════════════════════"
