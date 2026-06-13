# Guía de Operación y Desarrollo — CircleGuard

## Tabla de contenidos

1. [Visión general](#1-visión-general)
2. [Prerrequisitos](#2-prerrequisitos)
3. [Entorno local con Minikube](#3-entorno-local-con-minikube)
4. [Entorno en máquina virtual con k3s](#4-entorno-en-máquina-virtual-con-k3s)
5. [Construcción del proyecto](#5-construcción-del-proyecto)
6. [Despliegue de infraestructura con Terraform](#6-despliegue-de-infraestructura-con-terraform)
7. [Despliegue manual con kubectl](#7-despliegue-manual-con-kubectl)
8. [Pipelines CI/CD en Jenkins](#8-pipelines-cicd-en-jenkins)
9. [Gestión de cambios](#9-gestión-de-cambios)
10. [Observabilidad](#10-observabilidad)
11. [Seguridad](#11-seguridad)
12. [Referencia de puertos y endpoints](#12-referencia-de-puertos-y-endpoints)
13. [Solución de problemas comunes](#13-solución-de-problemas-comunes)

---

## 1. Visión general

CircleGuard es una plataforma de rastreo de contactos y control de acceso para campus universitarios. El sistema está compuesto por ocho microservicios Spring Boot, una aplicación móvil React Native y una infraestructura Kubernetes gestionada con Terraform y automatizada con Jenkins.

**Microservicios:**

| Servicio | Puerto interno | Responsabilidad |
|---|---|---|
| auth-service | 8180 | Autenticación JWT + LDAP, emisión de tokens QR |
| identity-service | 8083 | Anonimización de identidades (UUID ↔ identidad real) |
| promotion-service | 8088 | Motor de estados sanitarios, contact tracing en Neo4j |
| gateway-service | 8087 | Validación de tokens QR, control de acceso físico |
| notification-service | 8082 | Alertas por email, SMS y push (multi-canal asíncrono) |
| dashboard-service | 8084 | Panel de administración, estadísticas agregadas |
| form-service | 8086 | Recepción de encuestas de síntomas |
| file-service | 8085 | Gestión de certificados y archivos |

**Infraestructura de soporte:** PostgreSQL, Neo4j, Redis, Kafka + Zookeeper, OpenLDAP.

---

## 2. Prerrequisitos

### Para desarrollo local

- **JDK 21** — compilación y ejecución de servicios
- **Docker Desktop** (o Docker Engine en Linux) — imágenes y docker-compose
- **kubectl** — interacción con el cluster Kubernetes
- **Minikube** ≥ 1.32 — cluster local
- **Terraform** ≥ 1.6 — despliegue de infraestructura como código
- **Gradle** — el proyecto incluye el wrapper `./gradlew`, no se requiere instalación

### Para entorno en VM (k3s)

Ejecutar el script de configuración automática incluido en el repositorio:

```
bash scripts/setup-gcp-vm.sh
```

El script instala: Docker, k3s, kubectl, Terraform, Trivy, Java 21, Node.js 20 y Jenkins en contenedor.

### Para Windows

Se recomienda usar **WSL2** con Ubuntu 22.04. Todos los scripts de shell y los Jenkinsfiles funcionan sin modificación dentro de WSL2. Docker Desktop en Windows puede configurarse para usar el backend WSL2.

---

## 3. Entorno local con Minikube

### 3.1 Iniciar el cluster

```bash
minikube start --cpus=4 --memory=8192 --disk-size=30g
minikube addons enable ingress
minikube addons enable metrics-server
```

### 3.2 Levantar las bases de datos con Docker Compose

Los servicios de infraestructura (PostgreSQL, Neo4j, Redis, Kafka, LDAP) se ejecutan localmente vía Docker Compose para desarrollo:

```bash
docker-compose -f docker-compose.dev.yml up -d
```

Puertos expuestos por docker-compose:

| Servicio | Puerto local |
|---|---|
| PostgreSQL | 5432 |
| Neo4j (bolt) | 7687 |
| Neo4j (browser) | 7474 |
| Kafka | 9092 |
| Redis | 6379 |
| OpenLDAP | 389 |

### 3.3 Crear los namespaces

```bash
kubectl apply -f k8s/dev/security/secrets.yaml
kubectl create namespace dev    --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ci     --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace stage  --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace prod   --dry-run=client -o yaml | kubectl apply -f -
```

### 3.4 Aplicar secretos y RBAC

```bash
kubectl apply -f k8s/dev/security/secrets.yaml
kubectl apply -f k8s/dev/security/rbac.yaml
kubectl apply -f k8s/ci/jenkins-rbac.yaml
```

### 3.5 Construir y cargar imágenes en Minikube

```bash
# Apuntar el Docker daemon al registro interno de Minikube
eval $(minikube docker-env)

# Construir todas las imágenes (sustituir <TAG> por la versión deseada)
./gradlew clean build -x test

docker build -t simongarcia01/circleguard-auth-service:<TAG>         services/circleguard-auth-service/
docker build -t simongarcia01/circleguard-identity-service:<TAG>     services/circleguard-identity-service/
docker build -t simongarcia01/circleguard-promotion-service:<TAG>    services/circleguard-promotion-service/
docker build -t simongarcia01/circleguard-gateway-service:<TAG>      services/circleguard-gateway-service/
docker build -t simongarcia01/circleguard-notification-service:<TAG> services/circleguard-notification-service/
docker build -t simongarcia01/circleguard-dashboard-service:<TAG>    services/circleguard-dashboard-service/
docker build -t simongarcia01/circleguard-form-service:<TAG>         services/circleguard-form-service/
docker build -t simongarcia01/circleguard-file-service:<TAG>         services/circleguard-file-service/
```

### 3.6 Desplegar servicios

```bash
kubectl apply -f k8s/dev/postgres/
kubectl apply -f k8s/dev/neo4j/
kubectl apply -f k8s/dev/redis/
kubectl apply -f k8s/dev/kafka/
kubectl apply -f k8s/dev/zookeeper/
kubectl apply -f k8s/dev/ldap/

# Esperar a que las bases de datos estén listas
kubectl wait --for=condition=ready pod -l app=postgres    -n dev --timeout=120s
kubectl wait --for=condition=ready pod -l app=neo4j       -n dev --timeout=120s

kubectl apply -f k8s/dev/identity/
kubectl apply -f k8s/dev/auth/
kubectl apply -f k8s/dev/promotion/
kubectl apply -f k8s/dev/gateway/
kubectl apply -f k8s/dev/notification/
kubectl apply -f k8s/dev/dashboard/
kubectl apply -f k8s/dev/form/
```

### 3.7 Obtener la IP de acceso

```bash
minikube ip
# Usar esa IP con los NodePorts de la sección 12
```

---

## 4. Entorno en máquina virtual con k3s

### 4.1 Requisitos de la VM

- Ubuntu 22.04 LTS
- Mínimo 10 GB de RAM (recomendado 12 GB)
- Mínimo 4 vCPU
- 40 GB de disco

### 4.2 Instalación del entorno

```bash
bash scripts/setup-gcp-vm.sh
```

El script configura k3s y escribe el kubeconfig en `~/.kube/config` con el contexto llamado `default`.

### 4.3 Diferencias respecto a Minikube

Con k3s no se usa `minikube docker-env`. Las imágenes deben estar disponibles en Docker Hub o en un registro accesible desde la VM. El pipeline de Jenkins se encarga del push automático.

Al usar Terraform con k3s, pasar el contexto correcto:

```bash
terraform -chdir=terraform/environments/dev apply \
  -var="kube_context=default" \
  -var="image_tag=<TAG>"
```

---

## 5. Construcción del proyecto

El proyecto usa Gradle multi-módulo. El wrapper `./gradlew` está incluido y no requiere instalación de Gradle.

### Compilar todos los servicios

```bash
./gradlew clean build -x test
```

### Compilar un servicio específico

```bash
./gradlew :services:circleguard-auth-service:build -x test
```

### Ejecutar tests unitarios

```bash
./gradlew test
```

### Ejecutar tests de integración

```bash
./gradlew integrationTest
```

### Generar reporte de cobertura

```bash
./gradlew jacocoTestReport
# Reporte en build/reports/jacoco/
```

### Construir la app móvil

```bash
cd mobile
npm install
npm test
npm run build   # o npx expo build según el entorno
```

---

## 6. Despliegue de infraestructura con Terraform

Terraform gestiona los namespaces de Kubernetes y los recursos base de cada ambiente.

### Estructura

```
terraform/
  environments/
    dev/      # namespace dev, 1 réplica, secretos con defaults
    stage/    # namespace stage, 1 réplica, secretos sin defaults
    prod/     # namespace prod, 2 réplicas, secretos obligatorios
  modules/
    namespace/       # crea y etiqueta el namespace
    infrastructure/  # bases de datos, Kafka, Redis, LDAP
    microservice/    # Deployment + Service por servicio
```

### Inicializar

```bash
cd terraform/environments/dev
terraform init
```

### Planificar

```bash
terraform plan \
  -var="image_tag=latest"
```

### Aplicar (dev)

```bash
terraform apply \
  -var="image_tag=latest" \
  -auto-approve
```

### Aplicar (stage / prod con k3s)

```bash
terraform apply \
  -var="kube_context=default" \
  -var="image_tag=v1.2.0-rc1" \
  -var="db_password=VALOR_SEGURO" \
  -var="neo4j_password=VALOR_SEGURO" \
  -var="ldap_password=VALOR_SEGURO" \
  -var="jwt_secret=VALOR_SEGURO" \
  -var="qr_secret=VALOR_SEGURO"
```

### Variables principales

| Variable | Descripción | Default dev |
|---|---|---|
| `kube_context` | Contexto kubectl (`minikube` o `default`) | `minikube` |
| `image_tag` | Tag de las imágenes Docker | `latest` |
| `replicas` | Réplicas por microservicio | `1` (dev), `2` (prod) |
| `db_password` | Contraseña PostgreSQL | `password` (dev) |
| `jwt_secret` | Secreto de firma JWT | valor de prueba (dev) |
| `qr_secret` | Secreto de firma QR | valor de prueba (dev) |

---

## 7. Despliegue manual con kubectl

Para aplicar cambios puntuales sin pasar por el pipeline completo.

### Actualizar la imagen de un servicio

```bash
kubectl set image deployment/auth-service \
  auth-service=simongarcia01/circleguard-auth-service:<NUEVO_TAG> \
  -n dev
```

### Verificar el estado del rollout

```bash
kubectl rollout status deployment/auth-service -n dev
```

### Rollback de un servicio

```bash
# Rollback a la versión anterior
bash scripts/rollback.sh dev auth-service

# Rollback a una versión específica
bash scripts/rollback.sh dev auth-service v1.1.0
```

### Rollback de todo el namespace

```bash
bash scripts/rollback.sh dev
```

### Ver logs de un servicio

```bash
kubectl logs -l app=auth-service -n dev --tail=100 -f
```

### Ver todos los pods del namespace

```bash
kubectl get pods -n dev -o wide
```

### Ver eventos del namespace (útil para diagnosticar fallos)

```bash
kubectl get events -n dev --sort-by='.lastTimestamp'
```

---

## 8. Pipelines CI/CD en Jenkins

El proyecto tiene tres pipelines Jenkinsfile correspondientes a las tres ramas principales.

### 8.1 Pipeline de desarrollo — `Jenkinsfile`

**Rama:** `develop` / `feature/*`  
**Namespace destino:** `dev`  
**Tag generado:** `v{mayor}.{menor}.{patch}-dev.{BUILD_NUMBER}`

| Etapa | Descripción |
|---|---|
| Checkout | Clona el repositorio |
| Semantic Version | Calcula el tag a partir del último tag git |
| Build | `./gradlew clean build -x test` |
| Test | Tests unitarios e integración |
| Frontend Build & Test | `npm install && npm test` en el directorio mobile |
| SonarQube Analysis | Análisis de calidad de código |
| Quality Gate | Falla el pipeline si el Quality Gate de SonarQube no pasa |
| Docker Build | Construye las 8 imágenes con el tag calculado |
| Trivy Security Scan | Escaneo de vulnerabilidades en cada imagen |
| Docker Push | Sube las imágenes a Docker Hub |
| Deploy Infra (Dev) | `terraform apply` en `terraform/environments/dev` |
| Deploy Services (Dev) | `kubectl set image` para actualizar cada Deployment |
| Smoke Tests (Dev) | Pruebas básicas de disponibilidad en el namespace dev |

### 8.2 Pipeline de staging — `Jenkinsfile.stage`

**Rama:** `release/*`  
**Namespace destino:** `stage`  
**Tag generado:** `v{mayor}.{menor}.{patch}-rc{BUILD_NUMBER}`

Igual al pipeline de desarrollo pero despliega en el namespace `stage` con imágenes RC.

### 8.3 Pipeline de producción — `Jenkinsfile.master`

**Rama:** `main` / `master`  
**Namespace destino:** `prod`  
**Tag generado:** `v{mayor}.{menor}.{patch}` (versión estable semver)

| Etapa adicional respecto a dev | Descripción |
|---|---|
| E2E Tests | Pruebas end-to-end completas |
| Performance Tests (Locust) | Pruebas de carga con Locust |
| Security Tests (OWASP ZAP) | Análisis de vulnerabilidades DAST |
| Generate Release Notes | Genera `CHANGELOG.md` con `scripts/generate-release-notes.sh` |
| **Approval: Deploy to Production** | **Pausa manual — requiere aprobación en Jenkins** |
| Deploy Services (Prod) | Despliega en namespace prod tras la aprobación |
| Verify Production | Verifica que todos los pods estén Ready |
| Tag Release in Git | Crea el tag git y hace commit del CHANGELOG actualizado |

### 8.4 Configurar Jenkins

1. Instalar Jenkins en Docker (incluido en `scripts/setup-gcp-vm.sh`) o apuntar a una instancia existente.
2. Crear las credenciales en Jenkins:
   - `docker-hub-credentials` — usuario/contraseña de Docker Hub
   - `sonarqube-token` — token de SonarQube
   - `kubeconfig` — archivo kubeconfig del cluster
3. Crear tres pipelines apuntando a los Jenkinsfiles correspondientes.
4. Aplicar el RBAC de Jenkins en el cluster: `kubectl apply -f k8s/ci/jenkins-rbac.yaml`

---

## 9. Gestión de cambios

### 9.1 Convención de commits

El proyecto usa **Conventional Commits**. Todos los mensajes de commit deben seguir el formato:

```
<tipo>(<ámbito>): <descripción corta>

[cuerpo opcional]

[pie opcional]
```

**Tipos permitidos:**

| Tipo | Uso |
|---|---|
| `feat` | Nueva funcionalidad |
| `fix` | Corrección de bug |
| `perf` | Mejora de rendimiento |
| `refactor` | Refactorización sin cambio de comportamiento |
| `test` | Adición o corrección de tests |
| `docs` | Cambios en documentación |
| `chore` | Cambios de build, dependencias, configuración |
| `ci` | Cambios en pipelines CI/CD |

**Ejemplos:**

```
feat(auth): add QR token expiration validation
fix(promotion): correct contact tracing window calculation
perf(gateway): bypass internal services for Redis direct lookup
```

### 9.2 Generación de release notes

El script `scripts/generate-release-notes.sh` parsea los commits desde el tag anterior y genera las notas categorizadas:

```bash
# Generar notas para v1.2.0 desde v1.1.0
bash scripts/generate-release-notes.sh v1.2.0 v1.1.0 RELEASE_NOTES.md
```

El pipeline master llama a este script automáticamente antes de cada despliegue a producción y actualiza `CHANGELOG.md`.

### 9.3 Procedimiento de rollback

El script `scripts/rollback.sh` soporta tres modos:

```bash
# Rollback de un servicio a la versión anterior
bash scripts/rollback.sh <NAMESPACE> <SERVICIO>

# Rollback de un servicio a una versión específica
bash scripts/rollback.sh <NAMESPACE> <SERVICIO> <VERSION>

# Rollback de todos los servicios del namespace
bash scripts/rollback.sh <NAMESPACE>
```

**Criterios para decidir rollback:**

- Tasa de error HTTP > 5% durante más de 5 minutos en producción
- Latencia p99 > 2 segundos sostenida
- Circuit breaker abierto en más de un servicio simultáneamente
- Fallo en las sondas de disponibilidad de Kubernetes

### 9.4 Clasificación de cambios

| Tipo de cambio | Aprobación requerida | Ventana de despliegue |
|---|---|---|
| Cambio estándar (config, docs, refactor) | Revisión por pares (PR) | Cualquier momento |
| Cambio normal (feat, fix, perf) | PR + pipeline verde | Martes y jueves |
| Cambio de emergencia (hotfix crítico) | Líder técnico | Cualquier momento con rollback listo |

---

## 10. Observabilidad

### 10.1 Métricas con Prometheus y Grafana

Todos los servicios exponen métricas en `/actuator/prometheus`. Prometheus las recoge automáticamente desde el namespace de observabilidad.

```bash
# Aplicar stack de observabilidad
kubectl apply -f k8s/dev/observability/prometheus/
kubectl apply -f k8s/dev/observability/grafana/
```

- **Prometheus:** `http://<IP_CLUSTER>:30900`
- **Grafana:** `http://<IP_CLUSTER>:30300` (credenciales por defecto: admin / admin)

En Grafana, importar los dashboards de Spring Boot Actuator (ID 12900 en Grafana Hub) y JVM Micrometer (ID 4701).

**Métricas clave a monitorear:**

- `http_server_requests_seconds` — latencia por endpoint
- `resilience4j_circuitbreaker_state` — estado de los circuit breakers
- `jvm_memory_used_bytes` — uso de memoria por servicio
- `kafka_consumer_records_lag` — retraso en consumo de tópicos

### 10.2 Trazas distribuidas con Jaeger

Todos los servicios envían trazas OTLP al colector Jaeger en `http://jaeger-service:4318/v1/traces`.

```bash
kubectl apply -f k8s/dev/observability/jaeger/
```

- **Jaeger UI:** `http://<IP_CLUSTER>:30686`

Buscar trazas por servicio de origen para seguir el flujo completo de una solicitud a través de múltiples microservicios. Especialmente útil para diagnosticar latencia en el flujo de validación de QR: gateway → Redis.

### 10.3 Logs centralizados con ELK Stack

```bash
kubectl apply -f k8s/dev/observability/elk/elasticsearch.yaml
kubectl apply -f k8s/dev/observability/elk/logstash.yaml
kubectl apply -f k8s/dev/observability/elk/kibana.yaml
```

- **Kibana:** `http://<IP_CLUSTER>:30561`

Logstash recibe logs de los contenedores en el puerto 5000 y los indexa en Elasticsearch. En Kibana, crear un index pattern `circleguard-*` para consultar todos los logs del sistema.

### 10.4 Health checks

Todos los servicios exponen tres endpoints de salud:

```
GET /actuator/health           # salud general (incluye DB, Redis, Kafka)
GET /actuator/health/liveness  # sonda de liveness para Kubernetes
GET /actuator/health/readiness # sonda de readiness para Kubernetes
```

Los estados de los circuit breakers de Resilience4j están integrados en `/actuator/health` y son visibles por Kubernetes para decidir si sacar un pod de rotación.

---

## 11. Seguridad

### 11.1 Secretos de Kubernetes

Los secretos se gestionan en `k8s/dev/security/secrets.yaml`. En producción, migrar a **HashiCorp Vault** o **Sealed Secrets de Bitnami**.

```bash
# Aplicar secretos en el namespace dev
kubectl apply -f k8s/dev/security/secrets.yaml

# Verificar que están creados
kubectl get secrets -n dev
```

Los secretos disponibles son:

| Nombre del Secret | Contenido |
|---|---|
| `circleguard-db-credentials` | Usuario y contraseña de PostgreSQL |
| `circleguard-ldap-credentials` | Credenciales LDAP |
| `circleguard-auth-keys` | JWT_SECRET y QR_SECRET |
| `circleguard-neo4j-credentials` | Credenciales Neo4j |

### 11.2 RBAC

El archivo `k8s/dev/security/rbac.yaml` define los roles y bindings para el namespace dev. Jenkins tiene su propio ServiceAccount con permisos limitados en `k8s/ci/jenkins-rbac.yaml`.

```bash
kubectl apply -f k8s/dev/security/rbac.yaml
kubectl apply -f k8s/ci/jenkins-rbac.yaml
```

### 11.3 TLS

El archivo `k8s/dev/security/tls.yaml` configura el Ingress NGINX con terminación TLS. Para generar un certificado autofirmado de prueba:

```bash
bash k8s/dev/security/generate-tls.sh
kubectl apply -f k8s/dev/security/tls.yaml
```

En producción usar `cert-manager` con Let's Encrypt.

### 11.4 Análisis de vulnerabilidades con Trivy

Trivy se ejecuta en el pipeline como etapa obligatoria antes de cada push a Docker Hub. También está configurado como CronJob en Kubernetes para escaneos periódicos:

```bash
kubectl apply -f k8s/dev/security/trivy-cronjob.yaml

# Ejecutar escaneo manual de una imagen
trivy image simongarcia01/circleguard-auth-service:latest
```

---

## 12. Referencia de puertos y endpoints

### Namespace dev (Minikube / k3s)

Obtener la IP del cluster:
- **Minikube:** `minikube ip`
- **k3s:** IP de la VM o `hostname -I | awk '{print $1}'`

| Servicio | Puerto interno | NodePort dev | NodePort stage | NodePort prod |
|---|---|---|---|---|
| auth-service | 8180 | 30081 | 31081 | 32081 |
| gateway-service | 8087 | 30087 | 31087 | 32087 |
| notification-service | 8082 | 30082 | — | — |
| identity-service | 8083 | 30083 | — | — |
| dashboard-service | 8084 | 30084 | — | — |
| form-service | 8086 | 30086 | — | — |
| Prometheus | 9090 | 30900 | — | — |
| Grafana | 3000 | 30300 | — | — |
| Jaeger UI | 16686 | 30686 | — | — |
| Kibana | 5601 | 30561 | — | — |

### Endpoints principales

| Endpoint | Método | Descripción |
|---|---|---|
| `/api/v1/auth/login` | POST | Autenticación con usuario y contraseña LDAP |
| `/api/v1/auth/qr` | GET | Genera token QR de acceso al campus |
| `/api/v1/gate/validate` | POST | Valida token QR en torniquete (gateway-service) |
| `/api/v1/health-status/promote` | POST | Actualiza estado sanitario de un usuario |
| `/api/v1/dashboard/stats` | GET | Estadísticas agregadas de salud del campus |
| `/api/v1/form/submit` | POST | Envía encuesta de síntomas |
| `/actuator/health` | GET | Estado de salud de cualquier servicio |

---

## 13. Solución de problemas comunes

### Los pods quedan en estado `Pending`

```bash
kubectl describe pod <NOMBRE_POD> -n dev
```

Causas frecuentes: recursos insuficientes (CPU/RAM), PersistentVolumeClaim no satisfecho, imagen no encontrada.

### Los pods quedan en `CrashLoopBackOff`

```bash
kubectl logs <NOMBRE_POD> -n dev --previous
```

Verificar que los Secrets existan y tengan las claves correctas. Verificar que las bases de datos estén accesibles desde el cluster.

### El circuit breaker está abierto

```bash
# Ver el estado de salud del servicio afectado
curl http://<IP>:<NODEPORT>/actuator/health | jq '.components.circuitBreakers'
```

El circuito se cerrará automáticamente tras el tiempo de espera configurado (20-30 segundos). Si persiste, verificar que el servicio dependiente esté corriendo y responda correctamente.

### Falla la Quality Gate de SonarQube

Revisar el reporte en la interfaz de SonarQube. Los umbrales configurados son: cobertura mínima de código, ausencia de bloqueantes y críticos nuevos. Corregir los hallazgos antes de volver a ejecutar el pipeline.

### Terraform falla al conectar con el cluster

```bash
kubectl config current-context
kubectl config get-contexts
```

Asegurarse de pasar el valor correcto de `kube_context`: `minikube` para entorno local, `default` para k3s.

### Las imágenes no se actualizan en Minikube

Al usar `imagePullPolicy: IfNotPresent`, si la imagen ya existe en el daemon de Minikube con ese tag no se descargará de nuevo. Usar un tag diferente o `imagePullPolicy: Always` durante el desarrollo activo.

### El pipeline de producción no avanza tras "Generate Release Notes"

El stage de aprobación manual en Jenkins espera una acción humana. Navegar al pipeline en ejecución en la interfaz de Jenkins y hacer clic en "Proceed" para aprobar el despliegue a producción.
