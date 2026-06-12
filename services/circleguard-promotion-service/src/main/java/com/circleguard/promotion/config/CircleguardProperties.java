package com.circleguard.promotion.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * External Configuration Pattern — centraliza la configuración de negocio
 * del promotion-service. Complementa SystemSettings (BD, runtime) con
 * parámetros estáticos de startup que no deben cambiarse sin redespliegue.
 *
 * Valores sobreescribibles via variables de entorno:
 *   CIRCLEGUARD_KAFKA_TOPIC_STATUS_CHANGED
 *   CIRCLEGUARD_FENCE_DEFAULT_MANDATORY_DAYS
 *   etc.
 */
@ConfigurationProperties(prefix = "circleguard")
@Data
public class CircleguardProperties {

    private final Kafka kafka = new Kafka();
    private final Fence fence = new Fence();

    @Data
    public static class Kafka {
        /** Topic para cambios de estado de salud de un usuario. */
        private String topicStatusChanged = "promotion.status.changed";

        /** Topic publicado por form-service al recibir una encuesta. */
        private String topicSurveySubmitted = "survey.submitted";

        /** Topic publicado cuando un certificado es validado. */
        private String topicCertificateValidated = "certificate.validated";
    }

    @Data
    public static class Fence {
        /** Días de cuarentena obligatoria por defecto (overrideable en SystemSettings). */
        private int defaultMandatoryDays = 14;

        /** Ventana de encuentros a considerar para contact tracing (días). */
        private int defaultEncounterWindowDays = 14;

        /** Umbral en segundos para transiciones automáticas de estado. */
        private long defaultAutoThresholdSeconds = 3600L;
    }
}
