package com.circleguard.promotion.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties(CircleguardProperties.class)
public class PropertiesConfig {
}
