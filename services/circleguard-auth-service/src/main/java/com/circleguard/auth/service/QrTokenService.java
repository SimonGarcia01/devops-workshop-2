package com.circleguard.auth.service;

import com.circleguard.auth.config.QrProperties;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.security.Key;
import java.util.Date;
import java.util.UUID;

/**
 * Usa QrProperties (External Configuration Pattern) en lugar de @Value dispersos.
 */
@Service
@RequiredArgsConstructor
public class QrTokenService {

    private final QrProperties qrProperties;

    private Key signingKey() {
        return Keys.hmacShaKeyFor(qrProperties.getSecret().getBytes());
    }

    public String generateQrToken(UUID anonymousId) {
        return Jwts.builder()
                .setSubject(anonymousId.toString())
                .setIssuedAt(new Date())
                .setExpiration(new Date(System.currentTimeMillis() + qrProperties.getExpiration()))
                .signWith(signingKey(), SignatureAlgorithm.HS256)
                .compact();
    }
}
