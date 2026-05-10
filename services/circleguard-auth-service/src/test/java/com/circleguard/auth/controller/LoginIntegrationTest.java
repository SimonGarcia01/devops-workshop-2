package com.circleguard.auth.controller;

import java.util.UUID;

import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;

import org.springframework.http.MediaType;

import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.core.Authentication;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import com.circleguard.auth.client.IdentityClient;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
public class LoginIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private IdentityClient identityClient;

    @MockBean
    private AuthenticationManager authenticationManager;

    @Test
    void shouldGenerateRealJwtTokenDuringLogin() throws Exception {

        UUID anonymousId = UUID.randomUUID();

        Authentication auth = Mockito.mock(Authentication.class);

        Mockito.when(authenticationManager.authenticate(Mockito.any()))
                .thenReturn(auth);

        Mockito.when(identityClient.getAnonymousId("integration-user"))
                .thenReturn(anonymousId);

        String requestBody = """
        {
            "username":"integration-user",
            "password":"password123"
        }
        """;

        mockMvc.perform(post("/api/v1/auth/login")
                .contentType(MediaType.APPLICATION_JSON)
                .content(requestBody))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").exists())
                .andExpect(jsonPath("$.anonymousId")
                        .value(anonymousId.toString()));
    }
}