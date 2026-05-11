package com.circleguard.auth.e2e;

import static org.junit.jupiter.api.Assertions.*;

import java.util.Map;

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;

import org.springframework.boot.test.context.SpringBootTest;

import org.springframework.http.*;

import org.springframework.test.context.ActiveProfiles;
import org.springframework.web.client.RestTemplate;

@Disabled("Pending LDAP seeded users for real E2E")
@SpringBootTest
@ActiveProfiles("e2e")
public class LoginFlowE2ETest {

    private final RestTemplate restTemplate = new RestTemplate();

    @Test
    void shouldLoginAndValidateQrSuccessfully() {

        // ---------- LOGIN ----------
        Map<String, String> loginRequest = Map.of(
            "username", "admin",
            "password", "admin"
        );

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);

        HttpEntity<Map<String, String>> request =
                new HttpEntity<>(loginRequest, headers);

        ResponseEntity<Map> loginResponse =
                restTemplate.postForEntity(
                        "http://localhost:8180/api/v1/auth/login",
                        request,
                        Map.class
                );

        assertEquals(HttpStatus.OK, loginResponse.getStatusCode());

        String token = (String) loginResponse.getBody().get("token");

        assertNotNull(token);

        // ---------- GATEWAY VALIDATION ----------

        Map<String, String> validateRequest = Map.of(
                "token", token
        );

        HttpEntity<Map<String, String>> entity =
                new HttpEntity<>(validateRequest, headers);

        ResponseEntity<Map> validationResponse =
                restTemplate.postForEntity(
                        "http://localhost:8087/api/v1/gate/validate",
                        entity,
                        Map.class
                );

        assertEquals(HttpStatus.OK, validationResponse.getStatusCode());

        assertEquals(
                "GREEN",
                validationResponse.getBody().get("status")
        );
    }
}