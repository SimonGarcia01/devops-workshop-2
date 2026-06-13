# Change Management — CircleGuard

**Proyecto:** CircleGuard — Sistema de Control de Acceso y Contact Tracing  
**Versión:** 1.0.0  
**Fecha:** Junio 2026

---

## Índice

1. [Proceso Formal de Change Management](#1-proceso-formal-de-change-management)
2. [Estrategia de Branching y Promoción](#2-estrategia-de-branching-y-promoción)
3. [Versionado Semántico](#3-versionado-semántico)
4. [Conventional Commits](#4-conventional-commits)
5. [Release Notes Automáticas](#5-release-notes-automáticas)
6. [Sistema de Etiquetado de Releases](#6-sistema-de-etiquetado-de-releases)
7. [Planes de Rollback](#7-planes-de-rollback)

---

## 1. Proceso Formal de Change Management

### 1.1 Tipos de Cambio

| Tipo | Descripción | Tiempo de aprobación | Ambiente destino |
|---|---|---|---|
| **Standard** | Cambios rutinarios de bajo riesgo (fix de bug, actualización de dependencia) | Automático (CI pasa) | dev → stage → prod |
| **Normal** | Nueva funcionalidad, cambio de arquitectura | Revisión de código + aprobación manual | dev → stage → prod |
| **Emergency** | Parche crítico de seguridad o outage en producción | Aprobación de tech lead en <1h | Hotfix directo a prod |

### 1.2 Flujo de Aprobación

```
Developer
    │
    ├─► [Standard Change]
    │        │
    │        ▼
    │   feature/* branch
    │        │
    │        ▼
    │   PR a develop ──► CI (Jenkinsfile) ──► Auto-merge si pasa
    │
    ├─► [Normal Change]
    │        │
    │        ▼
    │   feature/* branch
    │        │
    │        ▼
    │   PR a develop ──► CI Dev ──► Code Review (≥1 aprobación) ──► merge
    │        │
    │        ▼
    │   release/* branch ──► CI Stage (Jenkinsfile.stage) ──► QA Validation
    │        │
    │        ▼
    │   PR a main ──► CI Prod (Jenkinsfile.master) ──► Aprobación Manual ──► Deploy
    │
    └─► [Emergency Change]
             │
             ▼
        hotfix/* branch desde main
             │
             ▼
        CI Prod ──► Aprobación Tech Lead ──► Deploy prod
             │
             ▼
        Back-merge a develop
```

### 1.3 Criterios de Aprobación para Producción

Para que un cambio pueda desplegarse a producción, debe cumplir **todos** los siguientes criterios:

- [ ] Build exitoso en CI (gradle build, npm test)
- [ ] Cobertura de tests ≥ umbral definido en SonarQube
- [ ] Quality Gate de SonarQube: PASSED
- [ ] Trivy scan: 0 vulnerabilidades CRITICAL o HIGH
- [ ] Smoke tests en stage exitosos (health checks + validación de token)
- [ ] E2E tests pasando
- [ ] Performance tests dentro de umbral (p95 < 2s bajo 20 usuarios concurrentes)
- [ ] Aprobación manual en Jenkins (`admin` o `lead-dev`)

### 1.4 Ventanas de Despliegue

| Ambiente | Ventana permitida | Restricciones |
|---|---|---|
| **dev** | Cualquier hora | Sin restricciones |
| **stage** | Lunes–Viernes 07:00–20:00 | Solo si CI dev pasa |
| **prod** | Martes y Jueves 09:00–12:00 | Requiere aprobación manual + ventana de cambio |

### 1.5 Notificaciones

El pipeline notifica automáticamente por email a `claudiaoponia@gmail.com` en los siguientes eventos:

| Evento | Asunto del email | Adjunto |
|---|---|---|
| Pipeline dev falla | ` FAILED: <job> #<build>` | — |
| Stage deploy exitoso | ` STAGE OK: <version> listo para prod` | — |
| Prod deploy exitoso | ` DEPLOYED: CircleGuard <version> en PRODUCCIÓN` | `release-notes.md` |
| Prod pipeline falla | ` FAILED: Pipeline PROD <job>` | — |

---

## 2. Estrategia de Branching y Promoción

CircleGuard usa **GitFlow** adaptado a 3 ambientes:

```
main ─────────────────────────────────────────── v1.0.0 ─── v1.0.1 ─►
          ▲                                         ▲
          │ merge + tag                             │ merge + tag
          │                                         │
release/1.0 ──────────────────────────────────────┘
          ▲
          │ branch desde develop
          │
develop ──┬──────────────────────────────────────────────────────────►
          │         │           │
          ▼         ▼           ▼
      feature/  feature/    hotfix/
      auth-cb   dashboard   sec-patch
          │         │           │
          └────────►│           └── PR directo a main (emergency)
                    └────────────► PR a develop
```

### Ramas y Pipelines

| Rama | Pipeline | Namespace K8s | Tag Docker |
|---|---|---|---|
| `feature/*`, `develop` | `Jenkinsfile` | `dev` | `v{semver}-dev.{build}` |
| `release/*` | `Jenkinsfile.stage` | `stage` | `v{semver}-rc.{build}` |
| `main` | `Jenkinsfile.master` | `prod` | `v{semver}` (estable) |

---

## 3. Versionado Semántico

CircleGuard sigue [SemVer 2.0.0](https://semver.org/):

```
v MAJOR . MINOR . PATCH  [-rc.N | -dev.N]
  ─────   ─────   ─────
    │       │       │
    │       │       └─ Correcciones de bug, cambios no funcionales
    │       └───────── Nueva funcionalidad retrocompatible
    └───────────────── Cambio incompatible (breaking change)
```

### Ejemplos

| Situación | Versión anterior | Nueva versión |
|---|---|---|
| Fix de bug en auth-service | v1.0.3 | v1.0.4 |
| Nueva API de formularios | v1.0.4 | v1.1.0 |
| Cambio de contrato en gateway | v1.1.2 | v2.0.0 |

### Automatización en CI

El pipeline `Jenkinsfile.master` auto-incrementa el PATCH en cada build de main:

```groovy
def patch = (parts[2] ?: '0').replaceAll('-.*', '').toInteger() + 1
env.IMAGE_TAG = "v${major}.${minor}.${patch}"
```

Para incrementar MINOR o MAJOR, el developer crea manualmente un tag en git antes de hacer merge a main:

```bash
git tag v2.0.0
git push origin v2.0.0
```

---

## 4. Conventional Commits

Todos los commits en CircleGuard siguen la especificación [Conventional Commits 1.0.0](https://www.conventionalcommits.org/):

```
<tipo>[ámbito opcional][!]: <descripción>

[cuerpo opcional]

[notas de pie opcionales]
```

### Tipos Válidos

| Tipo | Descripción | Impacto en versión |
|---|---|---|
| `feat` | Nueva funcionalidad | MINOR |
| `fix` | Corrección de bug | PATCH |
| `ci` | Cambios en pipeline CI/CD | ninguno |
| `build` | Cambios en el sistema de build | ninguno |
| `docs` | Solo documentación | ninguno |
| `refactor` | Refactoring sin cambio funcional | ninguno |
| `test` | Agrega o corrige tests | ninguno |
| `chore` | Mantenimiento general | ninguno |
| `perf` | Mejora de rendimiento | PATCH |
| `style` | Formato de código (sin cambio lógico) | ninguno |
| `BREAKING CHANGE` | En el pie del commit o `!` en el tipo | MAJOR |

### Ejemplos

```bash
# Nueva funcionalidad
git commit -m "feat(auth): add circuit breaker to identity-service client"

# Corrección de bug  
git commit -m "fix(gateway): return 401 instead of 500 for expired QR tokens"

# Breaking change
git commit -m "feat(api)!: rename /gate/validate to /gate/access

BREAKING CHANGE: endpoint /api/v1/gate/validate renombrado a /api/v1/gate/access
para consistencia con la nomenclatura REST"

# CI / infraestructura
git commit -m "ci: add Trivy scan to stage pipeline"
```

---

## 5. Release Notes Automáticas

### 5.1 Script de Generación

El archivo `scripts/generate-release-notes.sh` genera release notes estructuradas en markdown a partir de los commits convencionales entre el tag anterior y HEAD:

```bash
# Uso
./scripts/generate-release-notes.sh <VERSION> [PREV_TAG] [OUTPUT_FILE]

# Ejemplo
./scripts/generate-release-notes.sh v1.1.0 v1.0.5 release-notes.md
```

El script categoriza automáticamente los commits por tipo:

```
# CircleGuard — Release v1.1.0

## ✨ Nuevas Funcionalidades
- add circuit breaker to identity-service client (developer, 2026-06-10)

## 🐛 Correcciones  
- return 401 instead of 500 for expired QR tokens (developer, 2026-06-09)

## ⚙️ CI/CD e Infraestructura
- add Trivy scan to stage pipeline (developer, 2026-06-08)

## 🐳 Imágenes Docker
| Servicio | Tag |
| auth-service | simongarcia01/auth-service:v1.1.0 |
...
```

### 5.2 Integración en Pipeline

El `Jenkinsfile.master` invoca el script en el stage `Generate Release Notes` y adjunta el resultado al email de notificación de producción:

```groovy
stage('Generate Release Notes') {
    steps {
        sh """
            chmod +x scripts/generate-release-notes.sh
            PREV_TAG=\$(git tag --sort=-v:refname | grep '^v' | sed -n '2p' || true)
            ./scripts/generate-release-notes.sh ${IMAGE_TAG} "\${PREV_TAG}" release-notes.md

            # Antepone la nueva entrada al CHANGELOG.md del repositorio
            TEMP=\$(cat release-notes.md)
            HEADER=\$(head -6 CHANGELOG.md)
            BODY=\$(tail -n +7 CHANGELOG.md)
            printf '%s\n\n%s\n\n%s' "\$HEADER" "\$TEMP" "\$BODY" > CHANGELOG.md
        """
        archiveArtifacts artifacts: 'release-notes.md'
    }
}
```

### 5.3 Actualización del CHANGELOG

Después de generar las release notes, el pipeline hace commit del `CHANGELOG.md` actualizado al repositorio:

```groovy
stage('Tag Release in Git') {
    steps {
        sh """
            git config user.email "jenkins@circleguard.edu"
            git config user.name  "Jenkins CI"
            git add CHANGELOG.md
            git commit -m "chore(release): update CHANGELOG for ${IMAGE_TAG}" || true
            git tag -a ${IMAGE_TAG} -m "Release ${IMAGE_TAG} — build #${env.BUILD_NUMBER}"
            git push origin ${IMAGE_TAG}
            git push origin HEAD:main
        """
    }
}
```

---

## 6. Sistema de Etiquetado de Releases

### 6.1 Convención de Tags

| Ambiente | Formato | Ejemplo | Pipeline |
|---|---|---|---|
| Desarrollo | `v{semver}-dev.{build}` | `v1.0.1-dev.47` | Jenkinsfile |
| Stage (RC) | `v{semver}-rc.{build}` | `v1.0.1-rc.12` | Jenkinsfile.stage |
| Producción | `v{semver}` | `v1.0.1` | Jenkinsfile.master |

### 6.2 Tags en Docker Hub

Cada imagen en Docker Hub recibe dos tags en producción:
- El tag estable `v{semver}` (inmutable, para rollbacks)
- `latest` (siempre apunta a la última versión de producción)

```bash
docker pull simongarcia01/auth-service:v1.0.1   # versión específica
docker pull simongarcia01/auth-service:latest    # última estable
```

### 6.3 Creación Manual de Tags

Para iniciar un nuevo ciclo MINOR o MAJOR:

```bash
# Incrementar MINOR (nueva funcionalidad)
git tag v1.1.0
git push origin v1.1.0

# Incrementar MAJOR (breaking change)
git tag v2.0.0
git push origin v2.0.0
```

El pipeline de producción respetará el tag más reciente como base y auto-incrementará el PATCH a partir de él.

### 6.4 Listar Releases

```bash
# Todos los tags estables de producción
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'

# Ver los 5 últimos releases
git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -5
```

---

## 7. Planes de Rollback

### 7.1 Script Automatizado

El archivo `scripts/rollback.sh` permite revertir servicios de forma rápida y segura:

```bash
# Sintaxis
./scripts/rollback.sh <NAMESPACE> [SERVICE] [VERSION]

# Rollback de TODOS los servicios a la revisión anterior en producción
./scripts/rollback.sh prod

# Rollback de un servicio específico a la revisión anterior
./scripts/rollback.sh prod auth-service

# Rollback de un servicio a una versión concreta
./scripts/rollback.sh prod auth-service v1.0.3
```

El script:
1. Valida que el namespace existe
2. Ejecuta `kubectl rollout undo` o `kubectl set image` según el caso
3. Espera a que el rollout complete con timeout de 120s
4. Verifica e imprime la imagen activa post-rollback

### 7.2 Procedimiento Manual de Rollback

Para rollbacks de emergencia sin el script:

```bash
# 1. Identificar el deployment con problemas
kubectl rollout history deployment/auth-service -n prod

# 2. Ver detalles de una revisión específica
kubectl rollout history deployment/auth-service -n prod --revision=3

# 3. Rollback a la revisión anterior
kubectl rollout undo deployment/auth-service -n prod

# 4. Rollback a una revisión específica
kubectl rollout undo deployment/auth-service -n prod --to-revision=3

# 5. Monitorear el rollback
kubectl rollout status deployment/auth-service -n prod --timeout=120s

# 6. Verificar la imagen activa
kubectl get deployment auth-service -n prod \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### 7.3 Rollback Completo de Ambiente

```bash
# Rollback completo de producción a una versión específica
PREV_VERSION="v1.0.3"
NAMESPACE="prod"
DOCKER_USER="simongarcia01"

for svc in auth-service identity-service promotion-service gateway-service \
           notification-service dashboard-service form-service; do
    kubectl set image deployment/${svc} \
        ${svc}=${DOCKER_USER}/${svc}:${PREV_VERSION} \
        -n ${NAMESPACE}
done

# Esperar a que todos los deployments terminen
for svc in auth-service identity-service promotion-service gateway-service \
           notification-service dashboard-service form-service; do
    kubectl rollout status deployment/${svc} -n ${NAMESPACE} --timeout=120s
done
```

### 7.4 Matriz de Decisión de Rollback

| Síntoma | Causa probable | Acción |
|---|---|---|
| 5xx en `/actuator/health` post-deploy | Bug en código nuevo | `rollback.sh prod <svc>` |
| Latencia p95 > 5s en Grafana | Regresión de rendimiento | `rollback.sh prod <svc>` |
| Pods en `CrashLoopBackOff` | Error de configuración | `kubectl logs`, luego rollback |
| Circuit Breaker OPEN en Grafana | Servicio dependiente caído | Rollback del dependiente |
| Error de schema en BD | Migración Flyway incompatible | Rollback + script de DB reversa |

### 7.5 Post-Rollback

Después de ejecutar un rollback:

1. **Notificar** al equipo vía email/Slack con la versión revertida y el motivo
2. **Abrir issue** en el repositorio con label `type: rollback` describiendo el problema
3. **Analizar** el fallo en un ambiente aislado (dev) antes de reintentar el despliegue
4. **Documentar** en el CHANGELOG como:
   ```
   ## [1.0.4] — 2026-06-15
   ### 🔧 Mantenimiento
   - revert: rollback de v1.0.4 a v1.0.3 por regresión en validación QR (#issue-42)
   ```
5. **Verificar** métricas en Grafana (latencia, error rate, CB state) durante 15 minutos post-rollback

---

*Documentación generada para el Proyecto Final de Ingeniería de Software V — CircleGuard v1.0.0*
