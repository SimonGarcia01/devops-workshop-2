package com.circleguard.identity;

import java.util.UUID;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;

import org.springframework.boot.test.context.SpringBootTest;

import org.springframework.test.context.ActiveProfiles;

import com.circleguard.identity.model.IdentityMapping;
import com.circleguard.identity.repository.IdentityMappingRepository;

import static org.junit.jupiter.api.Assertions.*;

@SpringBootTest
@ActiveProfiles("test")
public class IdentityVaultIntegrationTest {

    @Autowired
    private IdentityMappingRepository repository;

    @Test
    void shouldPersistAndRetrieveIdentityMapping() {

        IdentityMapping mapping = IdentityMapping.builder()
                .realIdentity("integration-user@test.com")
                .identityHash("integration-hash")
                .salt("salt123")
                .build();

        IdentityMapping saved = repository.saveAndFlush(mapping);

        IdentityMapping found =
                repository.findById(saved.getAnonymousId())
                        .orElseThrow();

        assertEquals(
                "integration-user@test.com",
                found.getRealIdentity()
        );
    }
}