package com.circleguard.notification;

import java.util.concurrent.CompletableFuture;

import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;

import org.springframework.boot.test.context.SpringBootTest;

import org.springframework.boot.test.mock.mockito.MockBean;

import org.springframework.test.context.ActiveProfiles;

import com.circleguard.notification.service.EmailService;
import com.circleguard.notification.service.NotificationDispatcher;
import com.circleguard.notification.service.PushService;
import com.circleguard.notification.service.SmsService;

import static org.mockito.ArgumentMatchers.any;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SpringBootTest
@ActiveProfiles("test")
public class NotificationDispatcherIntegrationTest {

    @Autowired
    private NotificationDispatcher dispatcher;

    @MockBean
    private EmailService emailService;

    @MockBean
    private SmsService smsService;

    @MockBean
    private PushService pushService;

    @Test
    void shouldDispatchNotificationToEveryChannel() {

        when(emailService.sendAsync(any(), any()))
                .thenReturn(CompletableFuture.completedFuture(null));

        when(smsService.sendAsync(any(), any()))
                .thenReturn(CompletableFuture.completedFuture(null));

        when(pushService.sendAsync(any(), any(), any()))
                .thenReturn(CompletableFuture.completedFuture(null));

        dispatcher.dispatch(
                "integration-user",
                "Integration notification message"
        );

        verify(emailService)
                .sendAsync(any(), any());

        verify(smsService)
                .sendAsync(any(), any());

        verify(pushService)
                .sendAsync(any(), any(), any());
    }
}