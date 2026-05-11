package com.circleguard.promotion.controller;

import com.circleguard.promotion.security.SecurityConfig;
import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;

import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import org.springframework.data.redis.core.StringRedisTemplate;

import org.springframework.http.MediaType;

import org.springframework.kafka.core.KafkaTemplate;

import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class HealthStatusControllerIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private KafkaTemplate<String, Object> kafkaTemplate;

    @MockBean
    private StringRedisTemplate redisTemplate;

    @Test
    void confirmedEndpoint_WithoutAuthentication_ReturnsForbidden() throws Exception {

        String json = """
        {
            "anonymousId":"integration-user"
        }
        """;

        mockMvc.perform(post("/api/v1/health/confirmed")
                .contentType(MediaType.APPLICATION_JSON)
                .content(json))
                .andExpect(status().isForbidden());
    }
}