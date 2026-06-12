package com.circleguard.dashboard.client;

import com.circleguard.dashboard.config.DashboardProperties;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Date;
import java.util.Map;

/**
 * Circuit Breaker Pattern — protege al dashboard-service de fallos en cascada
 * cuando promotion-service no está disponible.
 *
 * Estados del Circuit Breaker:
 *   CLOSED   → flujo normal, todas las llamadas pasan
 *   OPEN     → promotion-service fallando, retorna fallback inmediatamente
 *   HALF-OPEN → prueba si el servicio se recuperó (2 llamadas de prueba)
 *
 * Config: resilience4j.circuitbreaker.instances.promotionService en application.yml
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class PromotionClient {

    private final RestTemplate restTemplate;
    private final DashboardProperties properties;

    private static final String CB_NAME = "promotionService";

    @CircuitBreaker(name = CB_NAME, fallbackMethod = "getHealthStatsFallback")
    public Map<String, Object> getHealthStats() {
        return restTemplate.getForObject(
                properties.getPromotionServiceUrl() + "/api/v1/health-status/stats",
                Map.class
        );
    }

    @CircuitBreaker(name = CB_NAME, fallbackMethod = "getHealthStatsByDepartmentFallback")
    public Map<String, Object> getHealthStatsByDepartment(String department) {
        return restTemplate.getForObject(
                properties.getPromotionServiceUrl() + "/api/v1/health-status/stats/department/" + department,
                Map.class
        );
    }

    // ── Fallbacks ────────────────────────────────────────────────────────────

    @SuppressWarnings("unused")
    Map<String, Object> getHealthStatsFallback(Exception e) {
        log.warn("[CircuitBreaker:{}] getHealthStats degraded — {}: {}",
                CB_NAME, e.getClass().getSimpleName(), e.getMessage());
        return Map.of(
                "error",     "promotion-service temporarily unavailable",
                "circuit",   "OPEN",
                "timestamp", new Date().toInstant().toString()
        );
    }

    @SuppressWarnings("unused")
    Map<String, Object> getHealthStatsByDepartmentFallback(String department, Exception e) {
        log.warn("[CircuitBreaker:{}] getHealthStatsByDepartment({}) degraded — {}",
                CB_NAME, department, e.getMessage());
        return Map.of(
                "error",      "promotion-service temporarily unavailable",
                "department", department,
                "circuit",    "OPEN",
                "timestamp",  new Date().toInstant().toString()
        );
    }
}
