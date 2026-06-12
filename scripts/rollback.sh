#!/usr/bin/env bash
# Rollback de servicios CircleGuard en un namespace de Kubernetes.
#
# Modos de uso:
#   rollback.sh <NAMESPACE>                       # rollback de todos los servicios (revision anterior)
#   rollback.sh <NAMESPACE> <SERVICE>             # rollback de un servicio específico
#   rollback.sh <NAMESPACE> <SERVICE> <VERSION>   # rollback a una imagen Docker específica
#
# Ejemplos:
#   ./rollback.sh prod
#   ./rollback.sh prod auth-service
#   ./rollback.sh prod auth-service v1.2.3

set -euo pipefail

NAMESPACE="${1:?Uso: $0 <NAMESPACE> [SERVICE] [VERSION]}"
SERVICE="${2:-all}"
VERSION="${3:-}"
DOCKER_USER="${DOCKER_USER:-simongarcia01}"

SERVICES=(
    auth-service
    identity-service
    promotion-service
    gateway-service
    notification-service
    dashboard-service
    form-service
)

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
ok()   { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
fail() { echo "[$(date '+%H:%M:%S')] ✗ $*" >&2; exit 1; }

# ── Valida que el namespace existe ───────────────────────────────────────────
kubectl get namespace "${NAMESPACE}" > /dev/null 2>&1 \
    || fail "Namespace '${NAMESPACE}' no existe."

# ── Función de rollback de un único servicio ─────────────────────────────────
rollback_service() {
    local svc="$1"

    if [[ -n "$VERSION" ]]; then
        # Rollback a versión específica via set image
        log "Rollback ${svc} → ${DOCKER_USER}/${svc}:${VERSION} en ${NAMESPACE}"
        kubectl set image deployment/"${svc}" \
            "${svc}=${DOCKER_USER}/${svc}:${VERSION}" \
            -n "${NAMESPACE}"
    else
        # Rollback a la revisión anterior (historial de Kubernetes)
        log "Rollback ${svc} → revisión anterior en ${NAMESPACE}"
        kubectl rollout undo deployment/"${svc}" -n "${NAMESPACE}"
    fi

    # Espera a que el rollback termine
    kubectl rollout status deployment/"${svc}" \
        -n "${NAMESPACE}" \
        --timeout=120s \
        && ok "${svc} rolled back exitosamente" \
        || fail "${svc} rollback falló — revisar: kubectl describe deployment/${svc} -n ${NAMESPACE}"
}

# ── Función de verificación post-rollback ────────────────────────────────────
verify_service() {
    local svc="$1"
    local current_image
    current_image=$(kubectl get deployment/"${svc}" -n "${NAMESPACE}" \
        -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "unknown")
    ok "${svc} — imagen activa: ${current_image}"
}

# ── Ejecución ────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
echo "  CircleGuard Rollback"
echo "  Namespace : ${NAMESPACE}"
echo "  Servicio  : ${SERVICE}"
echo "  Versión   : ${VERSION:-<anterior>}"
echo "══════════════════════════════════════════════"
echo ""

if [[ "$SERVICE" == "all" ]]; then
    for svc in "${SERVICES[@]}"; do
        rollback_service "$svc" || true
    done
else
    # Valida que el servicio existe en la lista conocida
    if ! printf '%s\n' "${SERVICES[@]}" | grep -qx "$SERVICE"; then
        fail "Servicio desconocido: '${SERVICE}'. Servicios válidos: ${SERVICES[*]}"
    fi
    rollback_service "$SERVICE"
fi

echo ""
echo "── Estado post-rollback ──────────────────────"
if [[ "$SERVICE" == "all" ]]; then
    for svc in "${SERVICES[@]}"; do
        verify_service "$svc" 2>/dev/null || true
    done
else
    verify_service "$SERVICE"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "  Rollback completado."
echo "  Para ver el historial: kubectl rollout history deployment/<svc> -n ${NAMESPACE}"
echo "══════════════════════════════════════════════"
