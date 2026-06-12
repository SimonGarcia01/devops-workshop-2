package com.circleguard.auth.client;

import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Map;
import java.util.UUID;

/**
 * Circuit Breaker + Retry Pattern — protege el flujo de login ante fallos
 * del identity-service (responsable de la anonimización de identidades).
 *
 * Retry: hasta 3 intentos con 500 ms de espera (errores transitorios de red).
 * Circuit Breaker: se abre si >50% de las llamadas fallan en una ventana de 5.
 * Fallback: genera un UUID determinístico temporal para no bloquear el login
 *           (aceptable solo en dev; en prod se podría rechazar con 503).
 *
 * Config: resilience4j.circuitbreaker/retry.instances.identityService en application.yml
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class IdentityClient {

    private final RestTemplate restTemplate;

    @Value("${identity.service.url:http://identity-service:8083}")
    private String identityServiceUrl;

    private static final String CB_NAME = "identityService";
    private static final String RETRY_NAME = "identityService";

    @Retry(name = RETRY_NAME, fallbackMethod = "getAnonymousIdFallback")
    @CircuitBreaker(name = CB_NAME, fallbackMethod = "getAnonymousIdFallback")
    public UUID getAnonymousId(String realIdentity) {
        Map<String, String> request = Map.of("realIdentity", realIdentity);
        Map<?, ?> response = restTemplate.postForObject(
                identityServiceUrl + "/api/v1/identities/map",
                request,
                Map.class
        );
        if (response == null || !response.containsKey("anonymousId")) {
            throw new IllegalStateException("identity-service returned empty response");
        }
        return UUID.fromString(response.get("anonymousId").toString());
    }

    // ── Fallback ─────────────────────────────────────────────────────────────

    @SuppressWarnings("unused")
    UUID getAnonymousIdFallback(String realIdentity, Exception e) {
        log.warn("[CircuitBreaker:{}] getAnonymousId('{}') degraded after retries — {}: {}",
                CB_NAME, realIdentity, e.getClass().getSimpleName(), e.getMessage());
        // UUID v5-like: determinístico por usuario para no romper sesiones existentes
        return UUID.nameUUIDFromBytes(("fallback:" + realIdentity).getBytes());
    }
}
