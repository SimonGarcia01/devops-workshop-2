package com.circleguard.auth.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * External Configuration Pattern — agrupa los parámetros JWT en un objeto tipado.
 * Sustituye los @Value("${jwt.*}") dispersos en JwtTokenService y QrValidationService.
 * Permite validación en startup y sobreescritura por entorno (JWT_SECRET, JWT_EXPIRATION).
 */
@ConfigurationProperties(prefix = "jwt")
@Data
public class JwtProperties {
    private String secret;
    private long expiration = 3600000L;
}
