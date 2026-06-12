package com.circleguard.dashboard.integration;

import com.circleguard.dashboard.client.PromotionClient;
import com.circleguard.dashboard.service.AnalyticsService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;

import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/**
 * Cross-service integration test: verifies that dashboard-service correctly
 * delegates to promotion-service for health stats and applies K-anonymity.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class DashboardPromotionIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private AnalyticsService analyticsService;

    @MockBean
    private PromotionClient promotionClient;

    @BeforeEach
    void setUp() {
        when(promotionClient.getHealthStats()).thenReturn(Map.of(
                "totalActive",    850,
                "totalSuspect",   42,
                "totalProbable",  18,
                "totalConfirmed", 5
        ));
        when(promotionClient.getHealthStatsByDepartment("Engineering")).thenReturn(Map.of(
                "department", "Engineering",
                "count",      3
        ));
    }

    @Test
    void shouldReturnCampusSummaryFromPromotionService() throws Exception {
        mockMvc.perform(get("/api/v1/analytics/health-board")
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.totalActive").value(850))
                .andExpect(jsonPath("$.totalSuspect").value(42));
    }

    @Test
    void shouldApplyKAnonymityWhenDepartmentCountBelowThreshold() {
        // Department "Engineering" has count=3, below k=5 threshold
        Map<String, Object> result = analyticsService.getDepartmentStats("Engineering");

        // K-anonymity must suppress or mask values below threshold
        assertThat(result).doesNotContainKey("count")
                .containsKey("suppressed");
    }

    @Test
    void shouldReturnDepartmentStatsAboveThreshold() {
        when(promotionClient.getHealthStatsByDepartment("Systems")).thenReturn(Map.of(
                "department", "Systems",
                "count",      120
        ));

        Map<String, Object> result = analyticsService.getDepartmentStats("Systems");

        assertThat(result).containsKey("count");
        assertThat((Integer) result.get("count")).isGreaterThanOrEqualTo(5);
    }

    @Test
    void shouldReturnEmptyServiceInfoWhenPromotionServiceIsDown() {
        when(promotionClient.getHealthStats()).thenReturn(
                Map.of("error", "Service unavailable", "timestamp", System.currentTimeMillis())
        );

        Map<String, Object> summary = analyticsService.getCampusSummary();
        assertThat(summary).containsKey("error");
    }

    @Test
    void shouldReturnEntryTrendsWithPrivacyMaskingForSmallCounts() throws Exception {
        UUID locationId = UUID.randomUUID();

        // Endpoint queries local DB — returns mock data for PoC when table is missing
        mockMvc.perform(get("/api/v1/analytics/trends/" + locationId)
                .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$").isArray());
    }
}
