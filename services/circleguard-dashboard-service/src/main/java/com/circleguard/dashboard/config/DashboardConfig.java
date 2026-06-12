package com.circleguard.dashboard.config;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

@Configuration
@EnableConfigurationProperties(DashboardProperties.class)
public class DashboardConfig {

    @Bean
    public RestTemplate restTemplate() {
        return new RestTemplate();
    }
}
