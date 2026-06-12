package com.circleguard.form.integration;

import com.circleguard.form.model.HealthSurvey;
import com.circleguard.form.model.Questionnaire;
import com.circleguard.form.model.ValidationStatus;
import com.circleguard.form.repository.HealthSurveyRepository;
import com.circleguard.form.service.HealthSurveyService;
import com.circleguard.form.service.QuestionnaireService;
import com.circleguard.form.service.SymptomMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.test.context.ActiveProfiles;

import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

/**
 * Cross-service integration test: verifies that form-service emits the correct
 * Kafka event on survey.submitted so that promotion-service can update health status.
 */
@SpringBootTest
@ActiveProfiles("test")
class SurveyKafkaIntegrationTest {

    @Autowired
    private HealthSurveyService surveyService;

    @Autowired
    private HealthSurveyRepository surveyRepository;

    @MockBean
    private KafkaTemplate<String, Object> kafkaTemplate;

    @MockBean
    private QuestionnaireService questionnaireService;

    @MockBean
    private SymptomMapper symptomMapper;

    @BeforeEach
    void setUp() {
        surveyRepository.deleteAll();
        Questionnaire activeQ = Questionnaire.builder()
                .id(UUID.randomUUID())
                .title("Daily Check")
                .isActive(true)
                .version(1)
                .build();
        when(questionnaireService.getActiveQuestionnaire()).thenReturn(Optional.of(activeQ));
    }

    @Test
    void shouldPublishSurveySubmittedEventWhenSymptomsDetected() {
        UUID anonymousId = UUID.randomUUID();
        HealthSurvey survey = HealthSurvey.builder()
                .anonymousId(anonymousId)
                .hasFever(true)
                .hasCough(true)
                .build();

        when(symptomMapper.hasSymptoms(any(), any())).thenReturn(true);

        surveyService.submitSurvey(survey);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> eventCaptor = ArgumentCaptor.forClass(Map.class);
        verify(kafkaTemplate).send(eq("survey.submitted"), eq(anonymousId.toString()), eventCaptor.capture());

        Map<String, Object> event = eventCaptor.getValue();
        assertThat(event).containsKey("anonymousId");
        assertThat(event).containsKey("hasSymptoms");
        assertThat(event.get("hasSymptoms")).isEqualTo(true);
    }

    @Test
    void shouldPublishSurveySubmittedEventWithNoSymptomsFlag() {
        UUID anonymousId = UUID.randomUUID();
        HealthSurvey survey = HealthSurvey.builder()
                .anonymousId(anonymousId)
                .hasFever(false)
                .hasCough(false)
                .build();

        when(symptomMapper.hasSymptoms(any(), any())).thenReturn(false);

        surveyService.submitSurvey(survey);

        @SuppressWarnings("unchecked")
        ArgumentCaptor<Map<String, Object>> eventCaptor = ArgumentCaptor.forClass(Map.class);
        verify(kafkaTemplate).send(eq("survey.submitted"), eq(anonymousId.toString()), eventCaptor.capture());

        assertThat(eventCaptor.getValue().get("hasSymptoms")).isEqualTo(false);
    }

    @Test
    void shouldPublishCertificateValidatedEventOnApproval() {
        UUID anonymousId = UUID.randomUUID();
        UUID adminId = UUID.randomUUID();

        HealthSurvey survey = HealthSurvey.builder()
                .anonymousId(anonymousId)
                .hasFever(false)
                .hasCough(false)
                .attachmentPath("/uploads/cert.pdf")
                .validationStatus(ValidationStatus.PENDING)
                .build();
        when(symptomMapper.hasSymptoms(any(), any())).thenReturn(false);

        HealthSurvey saved = surveyService.submitSurvey(survey);
        surveyService.validateSurvey(saved.getId(), ValidationStatus.APPROVED, adminId);

        verify(kafkaTemplate).send(eq("certificate.validated"), eq(anonymousId.toString()), any());
    }

    @Test
    void shouldNotPublishCertificateEventOnRejection() {
        UUID anonymousId = UUID.randomUUID();
        UUID adminId = UUID.randomUUID();

        HealthSurvey survey = HealthSurvey.builder()
                .anonymousId(anonymousId)
                .hasFever(false)
                .hasCough(false)
                .attachmentPath("/uploads/cert.pdf")
                .validationStatus(ValidationStatus.PENDING)
                .build();
        when(symptomMapper.hasSymptoms(any(), any())).thenReturn(false);

        HealthSurvey saved = surveyService.submitSurvey(survey);
        surveyService.validateSurvey(saved.getId(), ValidationStatus.REJECTED, adminId);

        verify(kafkaTemplate, never()).send(eq("certificate.validated"), any(), any());
    }
}
