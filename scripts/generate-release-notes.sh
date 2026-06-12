#!/usr/bin/env bash
# Genera release notes en formato markdown a partir de commits convencionales.
# Uso: ./generate-release-notes.sh <VERSION> [PREV_TAG] [OUTPUT_FILE]
#
# Categoriza commits por tipo (feat/fix/ci/docs/chore/BREAKING CHANGE).
# Si no se pasa PREV_TAG, usa el tag anterior al HEAD.

set -euo pipefail

VERSION="${1:?Usage: $0 <VERSION> [PREV_TAG] [OUTPUT_FILE]}"
PREV_TAG="${2:-}"
OUTPUT="${3:-release-notes.md}"

# Determina el tag anterior si no se pasa
if [[ -z "$PREV_TAG" ]]; then
    PREV_TAG=$(git tag --sort=-v:refname | grep '^v' | sed -n '2p' || true)
fi

RANGE="${PREV_TAG:+${PREV_TAG}..HEAD}"
DATE=$(date '+%Y-%m-%d')
COMMIT_SHA=$(git rev-parse --short HEAD)

# ── Colecta commits por tipo ──────────────────────────────────────────────────
get_commits() {
    local pattern="$1"
    git log ${RANGE} --pretty=format:"- %s (%an)" \
        | grep -E "^- ${pattern}" \
        | sed -E "s/^- ${pattern}[:(]?[^)]*[)]?[:!]?\s*//i" \
        | sed 's/^/- /' \
        || true
}

BREAKING=$(git log ${RANGE} --pretty=format:"%s (%an)" \
    | grep -E "BREAKING CHANGE|!:" \
    | sed 's/^/- /' || true)

FEATURES=$(get_commits "feat")
FIXES=$(get_commits "fix")
CI_CHANGES=$(get_commits "ci|build")
DOCS=$(get_commits "docs")
REFACTOR=$(get_commits "refactor")
CHORES=$(get_commits "chore|style|test|perf")

# ── Genera el archivo de release notes ───────────────────────────────────────
cat > "${OUTPUT}" <<EOF
# CircleGuard — Release ${VERSION}

**Fecha:** ${DATE}
**Commit:** \`${COMMIT_SHA}\`
$([ -n "$PREV_TAG" ] && echo "**Tag anterior:** \`${PREV_TAG}\`" || true)

---

$(if [ -n "$BREAKING" ]; then
    echo "## ⚠️  Breaking Changes"
    echo ""
    echo "$BREAKING"
    echo ""
fi)

$(if [ -n "$FEATURES" ]; then
    echo "## ✨ Nuevas Funcionalidades"
    echo ""
    echo "$FEATURES"
    echo ""
fi)

$(if [ -n "$FIXES" ]; then
    echo "## 🐛 Correcciones"
    echo ""
    echo "$FIXES"
    echo ""
fi)

$(if [ -n "$CI_CHANGES" ]; then
    echo "## ⚙️  CI/CD e Infraestructura"
    echo ""
    echo "$CI_CHANGES"
    echo ""
fi)

$(if [ -n "$REFACTOR" ]; then
    echo "## ♻️  Refactoring"
    echo ""
    echo "$REFACTOR"
    echo ""
fi)

$(if [ -n "$DOCS" ]; then
    echo "## 📖 Documentación"
    echo ""
    echo "$DOCS"
    echo ""
fi)

$(if [ -n "$CHORES" ]; then
    echo "## 🔧 Mantenimiento"
    echo ""
    echo "$CHORES"
    echo ""
fi)

---

## 🐳 Imágenes Docker

| Servicio | Tag |
|---|---|
| auth-service | \`${DOCKER_USER:-simongarcia01}/auth-service:${VERSION}\` |
| identity-service | \`${DOCKER_USER:-simongarcia01}/identity-service:${VERSION}\` |
| promotion-service | \`${DOCKER_USER:-simongarcia01}/promotion-service:${VERSION}\` |
| gateway-service | \`${DOCKER_USER:-simongarcia01}/gateway-service:${VERSION}\` |
| notification-service | \`${DOCKER_USER:-simongarcia01}/notification-service:${VERSION}\` |
| dashboard-service | \`${DOCKER_USER:-simongarcia01}/dashboard-service:${VERSION}\` |
| form-service | \`${DOCKER_USER:-simongarcia01}/form-service:${VERSION}\` |

EOF

echo "Release notes generadas en: ${OUTPUT}"
