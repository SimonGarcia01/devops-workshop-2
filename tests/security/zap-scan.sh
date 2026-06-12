#!/usr/bin/env bash
# OWASP ZAP Security Scan — CircleGuard
#
# Usage:
#   ./zap-scan.sh              → baseline (passive, safe for CI)
#   ./zap-scan.sh --full       → full active scan (only on non-prod)
#   ./zap-scan.sh --target URL → scan a specific service
#
# Requirements: Docker must be running.
# Reports are written to ./zap-reports/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT_DIR="${SCRIPT_DIR}/zap-reports"
ZAP_IMAGE="ghcr.io/zaproxy/zaproxy:stable"
SCAN_MODE="${1:-baseline}"

mkdir -p "$REPORT_DIR"

AUTH_URL="http://localhost:30081"
GATEWAY_URL="http://localhost:30087"
FORM_URL="http://localhost:30086"
DASHBOARD_URL="http://localhost:30084"

run_baseline_scan() {
    local service_name="$1"
    local target_url="$2"

    echo ""
    echo "▶ Scanning ${service_name} (${target_url}) — baseline mode..."

    docker run --rm \
        --network host \
        -v "${REPORT_DIR}:/zap/wrk:rw" \
        "${ZAP_IMAGE}" \
        zap-baseline.py \
            -t "${target_url}" \
            -r "${service_name}-zap-report.html" \
            -J "${service_name}-zap-report.json" \
            -I \
        || true  # --exit-code 0: report warnings but don't fail pipeline

    echo "  ✔ Report: ${REPORT_DIR}/${service_name}-zap-report.html"
}

run_full_scan() {
    local service_name="$1"
    local target_url="$2"

    echo ""
    echo "▶ Scanning ${service_name} (${target_url}) — FULL active scan..."

    docker run --rm \
        --network host \
        -v "${REPORT_DIR}:/zap/wrk:rw" \
        "${ZAP_IMAGE}" \
        zap-full-scan.py \
            -t "${target_url}" \
            -r "${service_name}-zap-full-report.html" \
            -J "${service_name}-zap-full-report.json" \
            -I \
        || true

    echo "  ✔ Full report: ${REPORT_DIR}/${service_name}-zap-full-report.html"
}

run_api_scan() {
    # Scan OpenAPI/Swagger spec if available
    local service_name="$1"
    local openapi_url="$2"

    echo ""
    echo "▶ API scan for ${service_name} via OpenAPI spec..."

    docker run --rm \
        --network host \
        -v "${REPORT_DIR}:/zap/wrk:rw" \
        "${ZAP_IMAGE}" \
        zap-api-scan.py \
            -t "${openapi_url}" \
            -f openapi \
            -r "${service_name}-api-zap-report.html" \
            -I \
        || true
}

echo "========================================"
echo "  CircleGuard — OWASP ZAP Security Scan"
echo "  Mode: ${SCAN_MODE}"
echo "  Reports → ${REPORT_DIR}"
echo "========================================"

if [[ "${SCAN_MODE}" == "--full" ]]; then
    run_full_scan "auth-service"      "$AUTH_URL"
    run_full_scan "gateway-service"   "$GATEWAY_URL"
    run_full_scan "form-service"      "$FORM_URL"
    run_full_scan "dashboard-service" "$DASHBOARD_URL"
else
    # Default: baseline passive scan (safe for every pipeline run)
    run_baseline_scan "auth-service"      "$AUTH_URL"
    run_baseline_scan "gateway-service"   "$GATEWAY_URL"
    run_baseline_scan "form-service"      "$FORM_URL"
    run_baseline_scan "dashboard-service" "$DASHBOARD_URL"

    # API scans using Swagger endpoints
    run_api_scan "auth-service"    "${AUTH_URL}/v3/api-docs"
    run_api_scan "gateway-service" "${GATEWAY_URL}/v3/api-docs"
fi

echo ""
echo "========================================"
echo "  Scan complete. Reports saved to:"
echo "  ${REPORT_DIR}"
echo "========================================"
