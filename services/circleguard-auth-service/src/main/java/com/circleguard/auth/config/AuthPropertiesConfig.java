package com.circleguard.auth.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
@EnableConfigurationProperties({JwtProperties.class, QrProperties.class})
public class AuthPropertiesConfig {

    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}
