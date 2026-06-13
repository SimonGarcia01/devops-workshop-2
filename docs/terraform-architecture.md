# Infraestructura como Código — Terraform

**Proyecto:** CircleGuard — Sistema de Control de Acceso y Contact Tracing  
**Versión:** 1.0.0  
**Fecha:** Junio 2026

---

## Índice

1. [Estructura de Módulos](#1-estructura-de-módulos)
2. [Arquitectura de Infraestructura](#2-arquitectura-de-infraestructura)
3. [Comparación por Ambiente](#3-comparación-por-ambiente)
4. [Backend Remoto (Terraform Cloud)](#4-backend-remoto-terraform-cloud)
5. [Flujo de Trabajo](#5-flujo-de-trabajo)
6. [Variables y Secretos](#6-variables-y-secretos)
7. [Comandos de Referencia](#7-comandos-de-referencia)

---

## 1. Estructura de Módulos

```
terraform/
├── environments/
│   ├── dev/
│   │   ├── main.tf           ← Orquesta los módulos para dev
│   │   ├── variables.tf      ← Variables del ambiente
│   │   ├── terraform.tfvars  ← Valores no-sensibles (image_tag, replicas)
│   │   ├── outputs.tf        ← Outputs del ambiente
│   │   └── backend.tf        ← Terraform Cloud workspace: circleguard-dev
│   ├── stage/
│   │   └── ...               ← Idem, workspace: circleguard-stage
│   └── prod/
│       └── ...               ← Idem, workspace: circleguard-prod
│
└── modules/
    ├── namespace/            ← Crea el namespace K8s con labels estándar
    ├── infrastructure/       ← PostgreSQL, Redis, Kafka, Zookeeper, Neo4j, LDAP
    └── microservice/         ← Deployment + Service para cada microservicio
```

### Diagrama de dependencias entre módulos

```
environments/{env}/main.tf
        │
        ├─── module "namespace"
        │         └── modules/namespace
        │                  └── kubernetes_namespace_v1
        │
        ├─── module "infrastructure"   depends_on: [namespace]
        │         └── modules/infrastructure
        │                  ├── kubernetes_deployment_v1.postgres
        │                  ├── kubernetes_service_v1.postgres
        │                  ├── kubernetes_deployment_v1.redis
        │                  ├── kubernetes_service_v1.redis
        │                  ├── kubernetes_deployment_v1.zookeeper
        │                  ├── kubernetes_service_v1.zookeeper
        │                  ├── kubernetes_deployment_v1.kafka
        │                  ├── kubernetes_service_v1.kafka
        │                  ├── kubernetes_deployment_v1.neo4j
        │                  ├── kubernetes_service_v1.neo4j
        │                  ├── kubernetes_deployment_v1.ldap
        │                  └── kubernetes_service_v1.ldap
        │
        ├─── module "auth_service"        depends_on: [infrastructure]
        ├─── module "identity_service"    depends_on: [infrastructure]
        ├─── module "gateway_service"     depends_on: [infrastructure]
        ├─── module "notification_service" depends_on: [infrastructure]
        ├─── module "promotion_service"   depends_on: [infrastructure]
        ├─── module "dashboard_service"   depends_on: [infrastructure, promotion]
        ├─── module "form_service"        depends_on: [infrastructure]
        └─── module "mobile"              depends_on: [auth_service]
                  │
                  └── modules/microservice
                           ├── kubernetes_deployment_v1.this
                           └── kubernetes_service_v1.this
```

### Módulo `microservice` — recursos que crea

```
module "microservice" {
  name           = "auth-service"       ← Nombre del Deployment y Service
  namespace      = "dev"
  image          = "simongarcia01/auth-service:latest"
  container_port = 8180
  replicas       = 1
  service_type   = "NodePort"           ← o "ClusterIP"
  node_port      = 30081                ← solo cuando service_type = NodePort
  env_vars       = { ... }              ← Variables de entorno del contenedor
  resources      = { ... }             ← CPU/memoria requests y limits
}

Crea:
  kubernetes_deployment_v1 "this"  → Pod(s) del microservicio
  kubernetes_service_v1    "this"  → Expone el pod (NodePort o ClusterIP)
```

---

## 2. Arquitectura de Infraestructura

### Vista por namespace (ambiente dev como ejemplo)

```
┌─────────────────────────────────────────────────────────────────┐
│  Kubernetes Cluster (Minikube)                                  │
│                                                                 │
│  ┌─────────────────────────── namespace: dev ────────────────┐  │
│  │                                                           │  │
│  │  ╔══ Capa de Datos (module: infrastructure) ══════════╗  │  │
│  │  ║                                                     ║  │  │
│  │  ║  [postgres-service:5432]  PostgreSQL 16             ║  │  │
│  │  ║  [redis-service:6379]     Redis 7.2                 ║  │  │
│  │  ║  [neo4j-service:7687]     Neo4j 5.26 (Bolt)        ║  │  │
│  │  ║  [neo4j-service:7474]     Neo4j 5.26 (HTTP)        ║  │  │
│  │  ║  [zookeeper-service:2181] Zookeeper 7.6             ║  │  │
│  │  ║  [kafka-service:9092]     Kafka 7.6                 ║  │  │
│  │  ║  [ldap-service:389]       OpenLDAP 1.5              ║  │  │
│  │  ║  [ldap-service:636]       OpenLDAP TLS              ║  │  │
│  │  ╚═════════════════════════════════════════════════════╝  │  │
│  │                           ▲                               │  │
│  │                           │ depende de                    │  │
│  │  ╔══ Capa de Servicios (module: microservice) ═════════╗  │  │
│  │  ║                                                     ║  │  │
│  │  ║  NodePort 30081  auth-service:8180                  ║  │  │
│  │  ║  NodePort 30083  identity-service:8083              ║  │  │
│  │  ║  NodePort 30087  gateway-service:8087               ║  │  │
│  │  ║  NodePort 30082  notification-service:8082          ║  │  │
│  │  ║  NodePort 30084  dashboard-service:8084             ║  │  │
│  │  ║  NodePort 30086  form-service:8086                  ║  │  │
│  │  ║  NodePort 30090  mobile:8081                        ║  │  │
│  │  ║  ClusterIP       promotion-service:8088             ║  │  │
│  │  ╚═════════════════════════════════════════════════════╝  │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────── namespace: ci ───────────────────────────────┐  │
│  │  Jenkins · SonarQube                                      │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘

        ▲ NodePorts
        │
   [Host / Developer]  →  kubectl · curl · Móvil
```

### Flujo de tráfico de usuario (validación de acceso)

```
 Móvil / App
     │
     │  HTTP
     ▼
[NodePort 300xx]
     │
     ▼
gateway-service ──► Redis (user:status:<id>)
     │                    │
     │              HIT → respuesta <1ms
     │              MISS ↓
     └──────────────► promotion-service ──► Neo4j / PostgreSQL
```

---

## 3. Comparación por Ambiente

### Resources por contenedor

| Parámetro | dev | stage | prod |
|---|---|---|---|
| `requests_cpu` | 100m | 200m | 250m |
| `requests_memory` | 256Mi | 384Mi | 512Mi |
| `limits_cpu` | 500m | 800m | 1000m |
| `limits_memory` | 512Mi | 768Mi | 1Gi |
| `replicas` | 1 | 1 | 2 |

### NodePorts por ambiente

| Servicio | dev | stage | prod |
|---|---|---|---|
| auth-service | 30081 | 31081 | 32081 |
| identity-service | 30083 | 31083 | 32083 |
| gateway-service | 30087 | 31087 | 32087 |
| notification-service | 30082 | 31082 | 32082 |
| dashboard-service | 30084 | 31084 | 32084 |
| form-service | 30086 | 31086 | 32086 |
| mobile | 30090 | 31090 | 32090 |
| promotion-service | ClusterIP | ClusterIP | ClusterIP |

### Diagrama comparativo de ambientes

```
           dev                 stage                prod
    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
    │ namespace:   │    │ namespace:   │    │ namespace:   │
    │    dev       │    │    stage     │    │    prod      │
    │              │    │              │    │              │
    │ replicas: 1  │    │ replicas: 1  │    │ replicas: 2  │
    │ cpu: 100m    │    │ cpu: 200m    │    │ cpu: 250m    │
    │ mem: 256Mi   │    │ mem: 384Mi   │    │ mem: 512Mi   │
    │              │    │              │    │              │
    │ Ports: 300xx │    │ Ports: 310xx │    │ Ports: 320xx │
    │              │    │              │    │              │
    │ Pipeline:    │    │ Pipeline:    │    │ Pipeline:    │
    │ Jenkinsfile  │    │ Jenkinsfile  │    │ Jenkinsfile  │
    │              │    │  .stage      │    │  .master     │
    │ Tag:         │    │ Tag:         │    │ Tag:         │
    │ vX.Y.Z-dev.N │    │ vX.Y.Z-rc.N │    │ vX.Y.Z       │
    └──────────────┘    └──────────────┘    └──────────────┘
           │                   │                   │
           └───────────────────┴───────────────────┘
                               │
                    Terraform Cloud (backend)
                    workspaces:
                      circleguard-dev
                      circleguard-stage
                      circleguard-prod
```

---

## 4. Backend Remoto (Terraform Cloud)

El estado de Terraform se almacena remotamente en **Terraform Cloud** (gratuito hasta 500 recursos), lo que permite:

- **Colaboración**: múltiples desarrolladores pueden ejecutar `terraform plan/apply` sin conflictos de state
- **Historial de cambios**: cada `apply` queda registrado con quien lo ejecutó
- **State locking automático**: previene aplicaciones concurrentes que corrompan el estado
- **Secretos seguros**: las variables `sensitive = true` se cifran en reposo

### Configuración

```hcl
# terraform/environments/dev/backend.tf
terraform {
  cloud {
    organization = "circleguard"
    workspaces {
      name = "circleguard-dev"   # circleguard-stage / circleguard-prod
    }
  }
}
```

### Setup inicial (una sola vez por ambiente)

```bash
# 1. Crear cuenta en https://app.terraform.io

# 2. Crear la organización "circleguard"

# 3. Crear los workspaces (modo CLI-driven):
#    circleguard-dev
#    circleguard-stage
#    circleguard-prod

# 4. Autenticar la CLI localmente
terraform login

# 5. Inicializar cada ambiente
cd terraform/environments/dev   && terraform init
cd terraform/environments/stage && terraform init
cd terraform/environments/prod  && terraform init
```

### Diagrama de flujo del estado remoto

```
Developer / Jenkins
       │
       │  terraform apply
       ▼
Terraform CLI ──────────────────────► Terraform Cloud
       │                               ├── State: circleguard-dev
       │  Lee kubeconfig local         ├── State: circleguard-stage
       ▼                               └── State: circleguard-prod
Kubernetes API (Minikube)
       │
       ▼
  Recursos creados/actualizados en el cluster
```

---

## 5. Flujo de Trabajo

### Despliegue de un ambiente desde cero

```bash
cd terraform/environments/dev

# 1. Inicializar (descarga providers y conecta con Terraform Cloud)
terraform init

# 2. Ver qué va a crear (sin aplicar)
terraform plan -var="db_password=secreto" -var="jwt_secret=mi-clave"

# 3. Aplicar
terraform apply -var="db_password=secreto" -var="jwt_secret=mi-clave"

# 4. Ver outputs (NodePorts, namespace, etc.)
terraform output
```

### Actualizar la versión desplegada

```bash
# Cambiar el image_tag en terraform.tfvars y aplicar
echo 'image_tag = "v1.1.0"' >> terraform.tfvars
terraform apply
```

### Destruir un ambiente (limpieza)

```bash
terraform destroy
```

### Diagrama del ciclo completo dev → prod

```
git push (develop)
      │
      ▼
Jenkinsfile (CI dev)
      │
      ├── Build + Test + Trivy
      ├── docker push simongarcia01/*:v1.0.1-dev.47
      │
      ▼
terraform apply (dev)
  image_tag = "v1.0.1-dev.47"
      │
      ▼
QA / Review
      │
      ▼
git push (release/1.0.1)
      │
      ▼
Jenkinsfile.stage (CI stage)
      │
      ├── Build + Test + Trivy (CRITICAL fail)
      ├── docker push simongarcia01/*:v1.0.1-rc.12
      │
      ▼
terraform apply (stage)
  image_tag = "v1.0.1-rc.12"
      │
      ▼
Smoke Tests + E2E en stage
      │
      ▼
git merge → main
      │
      ▼
Jenkinsfile.master (CI prod)
      │
      ├── Build + Test + Trivy (HIGH+CRITICAL fail)
      ├── Aprobación manual
      ├── docker push simongarcia01/*:v1.0.1
      │
      ▼
terraform apply (prod)
  image_tag = "v1.0.1"
      │
      ▼
git tag v1.0.1 + CHANGELOG update
```

---

## 6. Variables y Secretos

### Variables por ambiente (`variables.tf`)

| Variable | Tipo | Sensible | Default (dev) | Descripción |
|---|---|---|---|---|
| `image_tag` | string | no | `"latest"` | Tag de imagen Docker a desplegar |
| `replicas` | number | no | `1` | Réplicas por microservicio |
| `db_password` | string | **sí** | `"password"` | Contraseña PostgreSQL |
| `neo4j_password` | string | **sí** | `"password"` | Contraseña Neo4j |
| `ldap_password` | string | **sí** | `"admin"` | Contraseña LDAP admin |
| `jwt_secret` | string | **sí** | `"my-super-secret..."` | Clave JWT (mínimo 32 chars) |
| `qr_secret` | string | **sí** | `"my-qr-secret..."` | Clave QR tokens |

### Buenas prácticas de secretos

Las variables `sensitive = true` **nunca** deben ir en `terraform.tfvars`. Hay tres formas seguras de pasarlas:

```bash
# Opción 1: Variables de entorno (recomendado en CI/CD)
export TF_VAR_db_password="mi-password-seguro"
export TF_VAR_jwt_secret="clave-jwt-32-caracteres-minimo-prod"
terraform apply

# Opción 2: Flag -var en la línea de comandos
terraform apply \
  -var="db_password=mi-password" \
  -var="jwt_secret=mi-clave"

# Opción 3: Archivo .tfvars separado (NO commitear)
# secrets.tfvars  ← en .gitignore
terraform apply -var-file="secrets.tfvars"
```

### `.gitignore` para Terraform

```gitignore
# Terraform
**/.terraform/
*.tfstate
*.tfstate.backup
*.tfvars.json
secrets.tfvars
.terraform.lock.hcl    # opcional, algunos equipos sí lo commitean
crash.log
override.tf
```

---

## 7. Comandos de Referencia

```bash
# ── Inicialización ──────────────────────────────────────────
terraform init                    # Descarga providers + conecta backend

# ── Planificación ───────────────────────────────────────────
terraform plan                    # Preview de cambios
terraform plan -out=tfplan        # Guarda el plan para aplicarlo después

# ── Aplicación ──────────────────────────────────────────────
terraform apply                   # Aplica cambios (pide confirmación)
terraform apply -auto-approve     # Sin confirmación (usar solo en CI)
terraform apply tfplan            # Aplica el plan guardado

# ── Inspección ──────────────────────────────────────────────
terraform show                    # Muestra el estado actual
terraform output                  # Muestra los outputs del ambiente
terraform state list              # Lista todos los recursos en el estado

# ── Destrucción ─────────────────────────────────────────────
terraform destroy                 # Destruye todos los recursos del ambiente

# ── Formateo y validación ────────────────────────────────────
terraform fmt -recursive          # Formatea todos los .tf
terraform validate                # Valida la sintaxis

# ── Módulos ─────────────────────────────────────────────────
terraform get                     # Descarga módulos referenciados
```

---

*Documentación generada para el Proyecto Final de Ingeniería de Software V — CircleGuard v1.0.0*
