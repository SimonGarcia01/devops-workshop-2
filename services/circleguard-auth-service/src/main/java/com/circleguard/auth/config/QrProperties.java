package com.circleguard.auth.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * External Configuration Pattern — parámetros del token QR de acceso al campus.
 */
@ConfigurationProperties(prefix = "qr")
@Data
public class QrProperties {
    private String secret;
    private long expiration = 300000L;
}
