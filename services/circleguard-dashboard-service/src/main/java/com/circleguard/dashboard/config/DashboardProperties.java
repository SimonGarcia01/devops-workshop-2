package com.circleguard.dashboard.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * External Configuration Pattern — centraliza todos los parámetros configurables
 * del dashboard-service en un objeto tipado, evitando @Value dispersos.
 * Los valores se inyectan desde application.yml y se pueden sobreescribir
 * con variables de entorno (CIRCLEGUARD_PROMOTION_SERVICE_URL, etc.).
 */
@ConfigurationProperties(prefix = "circleguard")
@Data
public class DashboardProperties {

    /** URL base del promotion-service para llamadas REST. */
    private String promotionServiceUrl = "http://promotion-service:8088";

    /** Umbral mínimo de k-anonimato: oculta grupos menores a este valor. */
    private int analyticsKAnonymityThreshold = 5;

    /** Tiempo máximo de espera (ms) para llamadas al promotion-service. */
    private int promotionServiceTimeoutMs = 3000;
}
