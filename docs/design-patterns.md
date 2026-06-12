# Patrones de Diseño — CircleGuard

**Proyecto:** CircleGuard — Sistema de Control de Acceso y Contact Tracing  
**Versión:** 1.0.0  
**Fecha:** Junio 2026

---

## Índice

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Patrones Existentes en la Arquitectura](#2-patrones-existentes-en-la-arquitectura)
   - [Chain of Responsibility](#21-chain-of-responsibility)
   - [Strategy](#22-strategy)
   - [Facade](#23-facade)
   - [Observer / Event-Driven (Pub-Sub)](#24-observer--event-driven-pub-sub)
   - [Repository](#25-repository)
   - [Cache-Aside](#26-cache-aside)
   - [Feature Toggle](#27-feature-toggle)
   - [API Gateway](#28-api-gateway)
   - [Template Method](#29-template-method)
3. [Patrones Implementados en esta Iteración](#3-patrones-implementados-en-esta-iteración)
   - [Circuit Breaker](#31-circuit-breaker)
   - [External Configuration](#32-external-configuration)
   - [Retry](#33-retry)
4. [Tabla Resumen](#4-tabla-resumen)

---

## 1. Resumen Ejecutivo

CircleGuard utiliza una arquitectura de microservicios compuesta por 8 servicios Spring Boot. A lo largo del desarrollo se identificaron **9 patrones preexistentes** en el código base y se implementaron **3 patrones adicionales** de resiliencia y configuración, para un total de **12 patrones de diseño documentados**.

Los patrones se clasifican en tres categorías:

| Categoría | Patrones |
|---|---|
| **Comportamental** | Chain of Responsibility, Strategy, Facade, Observer, Template Method |
| **Arquitectónico / Cloud** | API Gateway, Cache-Aside, Feature Toggle, Circuit Breaker, External Configuration, Retry, Repository |

---

## 2. Patrones Existentes en la Arquitectura

### 2.1 Chain of Responsibility

**Categoría:** Comportamental  
**Servicio:** `circleguard-auth-service`  
**Archivo:** `auth/security/DualChainAuthenticationProvider.java`

#### Contexto y Problema

El sistema debe autenticar usuarios que pueden estar registrados en dos fuentes distintas: el directorio corporativo LDAP (empleados y docentes) y la base de datos local (visitantes y usuarios de prueba). Se necesita un mecanismo que intente una fuente y, si falla, continúe con la siguiente, sin que el llamador conozca la lógica de fallback.

#### Implementación

```java
@Component
public class DualChainAuthenticationProvider implements AuthenticationProvider {

    private final LdapAuthenticationProvider ldapProvider;
    private final DaoAuthenticationProvider  localProvider;

    @Override
    public Authentication authenticate(Authentication auth) throws AuthenticationException {
        try {
            return ldapProvider.authenticate(auth);   // Eslabón 1: LDAP
        } catch (AuthenticationException e) {
            return localProvider.authenticate(auth);  // Eslabón 2: DB local
        }
    }
}
```

```
LoginController
      │
      ▼
DualChainAuthenticationProvider
      │
      ├─► LdapAuthenticationProvider ──► LDAP Server
      │         (falla?)
      └─► DaoAuthenticationProvider  ──► PostgreSQL (LocalUser)
```

#### Beneficios

- **Transparencia:** `LoginController` invoca un único `AuthenticationManager`; ignora si el usuario está en LDAP o en DB.
- **Extensibilidad:** Añadir un tercer proveedor (OAuth2, SSO) no requiere cambiar la lógica de autenticación del controlador.
- **Tolerancia a fallos:** Si el servidor LDAP no está disponible, el sistema sigue funcionando con cuentas locales.

---

### 2.2 Strategy

**Categoría:** Comportamental  
**Servicio:** `circleguard-notification-service`  
**Archivos:** `service/EmailService.java`, `SmsService.java`, `PushService.java` (interfaces) y sus implementaciones `*Impl.java`

#### Contexto y Problema

El sistema debe enviar notificaciones de salud por múltiples canales (email, SMS, push). Cada canal tiene una implementación diferente, pero el código que decide *cuándo* notificar no debe acoplarse a *cómo* se envía cada canal.

#### Implementación

```java
// Interfaces — definen el contrato
public interface EmailService {
    CompletableFuture<Void> sendAsync(String userId, String message);
}
public interface SmsService {
    CompletableFuture<Void> sendAsync(String userId, String message);
}
public interface PushService {
    CompletableFuture<Void> sendAsync(String userId, String message, Map<String,String> metadata);
}

// NotificationDispatcher inyecta las estrategias por constructor
@Service
@RequiredArgsConstructor
public class NotificationDispatcher {
    private final EmailService emailService;   // estrategia concreta inyectada por Spring
    private final SmsService   smsService;
    private final PushService  pushService;
    ...
}
```

```
NotificationDispatcher
        │
        ├─► EmailService ──► EmailServiceImpl  (SMTP)
        ├─► SmsService   ──► SmsServiceImpl    (SMS gateway)
        └─► PushService  ──► PushServiceImpl   (FCM / APNs)
```

#### Beneficios

- **Intercambiabilidad:** Cambiar el proveedor de SMS (p. ej. Twilio → AWS SNS) sólo requiere reemplazar `SmsServiceImpl`; el dispatcher no cambia.
- **Testabilidad:** Los tests unitarios de `NotificationDispatcher` usan mocks de las interfaces sin necesitar servicios externos.
- **Open/Closed:** Se puede agregar un canal nuevo (WhatsApp, Teams) creando una nueva implementación sin modificar el dispatcher.

---

### 2.3 Facade

**Categoría:** Comportamental  
**Servicio:** `circleguard-notification-service`  
**Archivo:** `service/NotificationDispatcher.java`

#### Contexto y Problema

Enviar una notificación de cambio de estado de salud implica: generar contenido para 3 canales distintos, lanzar 3 llamadas asíncronas en paralelo y manejar errores parciales. Exponer toda esta complejidad a los consumidores (listeners de Kafka) haría el código frágil y difícil de mantener.

#### Implementación

```java
@Service
public class NotificationDispatcher {

    public void dispatch(String userId, String status) {
        // Genera contenido para cada canal
        String emailContent = templateService.generateEmailContent(status, userId);
        String pushContent  = templateService.generatePushContent(status);
        String smsContent   = templateService.generateSmsContent(status);

        // Lanza los 3 envíos en paralelo y maneja errores de forma unificada
        CompletableFuture.allOf(
            emailService.sendAsync(userId, emailContent),
            smsService.sendAsync(userId, smsContent),
            pushService.sendAsync(userId, pushContent, metadata)
        ).handle((result, ex) -> { /* logging centralizado */ return result; });
    }
}
```

```
ExposureNotificationListener (Kafka)
             │
             ▼
    NotificationDispatcher.dispatch()   ◄── Fachada
    ┌──────────────────────────────┐
    │  TemplateService             │
    │  EmailService.sendAsync()    │
    │  SmsService.sendAsync()      │
    │  PushService.sendAsync()     │
    └──────────────────────────────┘
```

#### Beneficios

- **Simplicidad para el cliente:** El listener de Kafka llama a un único método `dispatch(userId, status)`.
- **Encapsulamiento:** La lógica de paralelismo, generación de contenido y manejo de errores está oculta en el dispatcher.
- **Cohesión:** Todos los cambios relacionados con el envío multicanal ocurren en un solo lugar.

---

### 2.4 Observer / Event-Driven (Pub-Sub)

**Categoría:** Comportamental / Arquitectónico  
**Servicios:** `promotion-service`, `notification-service`, `form-service`  
**Archivos:** `SurveyListener.java`, `ExposureNotificationListener.java`, `CircleFencedListener.java`, `PriorityAlertListener.java`

#### Contexto y Problema

Cuando el estado de salud de un usuario cambia (ej. ACTIVE → SUSPECT), múltiples servicios deben reaccionar de forma independiente: el notification-service debe alertar al usuario, otros servicios pueden necesitar actualizar su estado. Un acoplamiento directo entre servicios crearía dependencias circulares y fragilidad.

#### Implementación

```java
// Publicador — promotion-service (StatusLifecycleService)
kafkaTemplate.send("promotion.status.changed", anonymousId, Map.of(
    "anonymousId", id,
    "status",      "ACTIVE",
    "reason",      "AUTO_WINDOW_EXPIRY"
));

// Suscriptor — notification-service (ExposureNotificationListener)
@KafkaListener(topics = "promotion.status.changed", groupId = "notification-group")
public void onStatusChanged(Map<String, Object> event) {
    notificationDispatcher.dispatch(
        event.get("anonymousId").toString(),
        event.get("status").toString()
    );
}
```

```
promotion-service                     Kafka Topics
  StatusLifecycleService  ──────►  promotion.status.changed
  HealthStatusService     ──────►  promotion.status.changed
  SurveyListener          ◄──────  survey.submitted
                                         │
                          ┌──────────────┘
                          ▼
               notification-service
                 ExposureNotificationListener
                 PriorityAlertListener
                 CircleFencedListener
```

#### Beneficios

- **Desacoplamiento total:** Los servicios publicadores no conocen a los suscriptores.
- **Escalabilidad:** Añadir un nuevo suscriptor no requiere cambiar el publicador.
- **Resiliencia:** Si notification-service está caído, los mensajes se retienen en Kafka y se procesan al recuperarse.
- **Auditoría:** El log de Kafka actúa como registro inmutable de todos los cambios de estado.

---

### 2.5 Repository

**Categoría:** Arquitectónico / Acceso a datos  
**Servicios:** Todos  
**Tecnologías:** Spring Data JPA (PostgreSQL), Spring Data Neo4j

#### Contexto y Problema

Los servicios necesitan acceder a múltiples bases de datos (PostgreSQL relacional y Neo4j grafo). La lógica de negocio no debe conocer los detalles de SQL ni de Cypher.

#### Implementación

```java
// JPA Repository — acceso relacional
@Repository
public interface SystemSettingsRepository extends JpaRepository<SystemSettings, Long> {
    @Cacheable(value = "systemSettings")
    default Optional<SystemSettings> getSettings() {
        return findAll().stream().findFirst();
    }
}

// Neo4j Repository — acceso al grafo de contactos
@Repository
public interface UserNodeRepository extends Neo4jRepository<UserNode, Long> {
    void recordEncounter(String userA, String userB, long timestamp, String locationId);
}
```

#### Beneficios

- **Separación de responsabilidades:** La capa de negocio trabaja con objetos de dominio; la capa de datos maneja la persistencia.
- **Intercambiabilidad de BD:** Cambiar PostgreSQL por MySQL solo requiere ajustar la configuración, no la lógica.
- **Testabilidad:** Los tests pueden usar H2 en memoria sustituyendo el repositorio real.

---

### 2.6 Cache-Aside

**Categoría:** Arquitectónico / Rendimiento  
**Servicios:** `promotion-service`, `gateway-service`  
**Tecnologías:** Caffeine (cache en memoria), Redis (cache distribuida)

#### Contexto y Problema

La validación de acceso al campus (`gateway-service`) ocurre miles de veces por minuto. Consultar Neo4j o PostgreSQL en cada validación sería inviable. Los datos de estado de salud cambian con poca frecuencia respecto a la tasa de lectura.

#### Implementación

```java
// Cache en memoria — promotion-service (CacheConfig + HealthStatusService)
@Cacheable(value = "userStatus", key = "#anonymousId")
public String getUserStatus(String anonymousId) { ... }

@CacheEvict(value = "userStatus", allEntries = true)
public void updateStatus(String anonymousId, String status) {
    // 1. Actualiza Neo4j
    // 2. Actualiza Redis (cache distribuida para gateway-service)
    redisTemplate.opsForValue().set("user:status:" + anonymousId, status);
    // 3. Publica en Kafka
}

// Cache distribuida — gateway-service (QrValidationService)
String status = redisTemplate.opsForValue().get("user:status:" + anonymousId);
```

```
gateway-service                promotion-service
QrValidationService            HealthStatusService
        │                              │
        ▼                              ▼
    Redis (L2)  ◄──── escribe ────  Caffeine (L1)
        │                              │
        └──────────────────────────► Neo4j / PostgreSQL
                                    (fuente de verdad)
```

#### Beneficios

- **Rendimiento:** La validación de QR consulta Redis en <1ms vs ~50ms en base de datos.
- **Coherencia eventual:** Al actualizar el estado, se invalida el caché y se propaga vía Kafka.
- **NFR-1 cumplido:** Latencia de validación de acceso <1s definida en los requisitos.

---

### 2.7 Feature Toggle

**Categoría:** Arquitectónico / Configuración  
**Servicio:** `promotion-service`  
**Archivos:** `model/jpa/SystemSettings.java`, `controller/AdminController.java`

#### Contexto y Problema

Las autoridades sanitarias pueden necesitar activar o desactivar el "fencing automático" (cuarentena preventiva de contactos no confirmados) en tiempo real, según la situación epidemiológica, sin necesidad de redesplegar el servicio.

#### Implementación

```java
// Modelo — SystemSettings.java
@Entity
public class SystemSettings {
    private Boolean unconfirmedFencingEnabled;  // Feature toggle principal
    private Long    autoThresholdSeconds;       // Umbral configurable
    private Integer mandatoryFenceDays;
    private Integer encounterWindowDays;
}

// API para toggle en runtime — AdminController.java
@PostMapping("/toggle-unconfirmed-fencing")
@CacheEvict(value = "systemSettings", allEntries = true)
public ResponseEntity<SystemSettings> toggleUnconfirmedFencing(@RequestParam boolean enabled) {
    settings.setUnconfirmedFencingEnabled(enabled);
    settingsRepository.save(settings);
    return ResponseEntity.ok(settings);
}

// Uso en lógica de negocio — HealthStatusService.java
var settings = systemSettingsRepository.getSettings()...;
if (settings.getUnconfirmedFencingEnabled()) {
    // aplicar fencing automático
}
```

#### Beneficios

- **Agilidad operacional:** La autoridad sanitaria activa/desactiva funcionalidades sin intervención del equipo de desarrollo.
- **Reducción de riesgo:** Permite hacer rollback de una feature a nivel de configuración, no de código.
- **Auditoría:** Cada cambio queda registrado en la base de datos con timestamp.

---

### 2.8 API Gateway

**Categoría:** Arquitectónico / Distribución  
**Servicio:** `circleguard-gateway-service`  
**Archivo:** `controller/GateController.java`, `service/QrValidationService.java`

#### Contexto y Problema

La aplicación móvil y los paneles administrativos no deben conocer las URLs internas de cada microservicio. Se necesita un único punto de entrada que centralice la autenticación, la autorización y el enrutamiento.

#### Implementación

```
         Móvil / Web
              │
              ▼
    ┌─────────────────────┐
    │    gateway-service  │  Puerto: 8087 / NodePort 30087
    │    (API Gateway)    │
    └─────────────────────┘
         │         │
         ▼         ▼
    auth-service  promotion-service
    (JWT/QR)      (estado de salud,
                   contact tracing)
```

La validación de QR en el gateway consulta Redis directamente para máximo rendimiento:

```java
public ValidationResult validateToken(String token) {
    Claims claims = Jwts.parserBuilder()...parseClaimsJws(token).getBody();
    String status = redisTemplate.opsForValue().get("user:status:" + anonymousId);
    return "CONTAGIED".equals(status)
        ? new ValidationResult(false, "RED",   "Access Denied")
        : new ValidationResult(true,  "GREEN", "Welcome");
}
```

#### Beneficios

- **Punto único de entrada:** Simplifica la configuración del cliente móvil.
- **Seguridad centralizada:** JWT y validación de estado de salud en un solo lugar.
- **Rendimiento:** Bypasa microservicios internos consultando Redis directamente para la validación de acceso crítica.

---

### 2.9 Template Method

**Categoría:** Comportamental  
**Servicio:** `circleguard-notification-service`  
**Archivo:** `service/TemplateService.java`

#### Contexto y Problema

El contenido de las notificaciones varía por canal (email requiere HTML estructurado, SMS requiere texto corto, push requiere texto + metadata de deeplink), pero la estructura del mensaje sigue siempre el mismo esquema: saludo + estado de salud + URL de acción.

#### Implementación

```java
@Service
public class TemplateService {

    // Método plantilla — define el esqueleto del proceso de generación
    public String generateEmailContent(String status, String userName) {
        // FreeMarker template: health_alert.ftl
        Map<String, Object> model = Map.of(
            "userName",    userName,
            "status",      status,
            "testingUrl",  testingUrl,     // @Value desde application.yml
            "isolationUrl", isolationUrl
        );
        Template t = freemarkerConfig.getTemplate("health_alert.ftl");
        return FreeMarkerTemplateUtils.processTemplateIntoString(t, model);
    }

    public String generateSmsContent(String status) {
        return "CircleGuard Alert: Your status is " + status + ". Check your email.";
    }

    public Map<String, String> generatePushMetadata(String status) {
        return "SUSPECT".equals(status) ? Map.of("url", guidelinesDeepLink) : Map.of();
    }
}
```

#### Beneficios

- **Consistencia:** Todos los mensajes de notificación siguen la misma voz de marca.
- **Mantenibilidad:** Cambiar el contenido de los emails solo requiere editar el archivo `.ftl`, sin tocar código Java.
- **Internacionalización:** El motor FreeMarker permite i18n sin cambiar la clase Java.

---

## 3. Patrones Implementados en esta Iteración

### 3.1 Circuit Breaker

**Categoría:** Resiliencia  
**Librería:** Resilience4j 2.1.0  
**Servicios:** `dashboard-service` → `PromotionClient`, `auth-service` → `IdentityClient`

#### Contexto y Problema

`dashboard-service` llama a `promotion-service` para obtener estadísticas de salud. Si `promotion-service` está caído o lento, sin protección el dashboard fallará con cascada de timeouts, bloqueando threads y degradando toda la plataforma. De forma similar, `auth-service` llama a `identity-service` durante cada login; una caída del servicio de identidad bloquearía todos los accesos al campus.

#### Implementación

**Máquina de estados del Circuit Breaker:**

```
                     falla rate > 50%
    CLOSED ──────────────────────────► OPEN
      ▲                                  │
      │                            wait 30s/20s
      │                                  │
    éxito                           HALF-OPEN
      │                                  │
      └──── 2 llamadas de prueba ────────┘
```

**dashboard-service — PromotionClient.java:**

```java
@Component
@RequiredArgsConstructor
public class PromotionClient {

    private final RestTemplate    restTemplate;
    private final DashboardProperties properties;

    @CircuitBreaker(name = "promotionService", fallbackMethod = "getHealthStatsFallback")
    public Map<String, Object> getHealthStats() {
        return restTemplate.getForObject(
            properties.getPromotionServiceUrl() + "/api/v1/health-status/stats",
            Map.class
        );
    }

    // Fallback — retorna datos degradados cuando el CB está OPEN
    Map<String, Object> getHealthStatsFallback(Exception e) {
        log.warn("[CB:promotionService] degraded — {}", e.getMessage());
        return Map.of("circuit", "OPEN", "error", "promotion-service unavailable");
    }
}
```

**Configuración en `application.yml`:**

```yaml
resilience4j:
  circuitbreaker:
    instances:
      promotionService:
        sliding-window-size: 5
        failure-rate-threshold: 50        # Abre CB con 50% de fallos
        wait-duration-in-open-state: 30s  # Tiempo en OPEN antes de probar
        permitted-number-of-calls-in-half-open-state: 2
        register-health-indicator: true   # Visible en /actuator/health
```

**auth-service — IdentityClient.java:**

```java
@Retry(name = "identityService", fallbackMethod = "getAnonymousIdFallback")
@CircuitBreaker(name = "identityService", fallbackMethod = "getAnonymousIdFallback")
public UUID getAnonymousId(String realIdentity) {
    Map<?, ?> response = restTemplate.postForObject(
        identityServiceUrl + "/api/v1/identities/map",
        Map.of("realIdentity", realIdentity),
        Map.class
    );
    return UUID.fromString(response.get("anonymousId").toString());
}

UUID getAnonymousIdFallback(String realIdentity, Exception e) {
    // UUID determinístico para no romper sesiones existentes
    return UUID.nameUUIDFromBytes(("fallback:" + realIdentity).getBytes());
}
```

#### Beneficios

| Beneficio | Descripción |
|---|---|
| **Prevención de cascada** | Un servicio caído no paraliza a los que dependen de él |
| **Respuesta rápida** | Con el CB en OPEN, el fallback responde en <1ms (sin esperar timeout de red) |
| **Auto-recuperación** | Estado HALF-OPEN prueba automáticamente si el servicio se recuperó |
| **Observabilidad** | Estado del CB visible en `/actuator/health` (integrado con Grafana) |

---

### 3.2 External Configuration

**Categoría:** Configuración  
**Mecanismo:** Spring Boot `@ConfigurationProperties`  
**Servicios:** `auth-service`, `dashboard-service`, `promotion-service`

#### Contexto y Problema

Los parámetros críticos del sistema (secretos JWT, URLs de servicios, nombres de topics Kafka, umbrales de cuarentena) estaban dispersos como anotaciones `@Value("${...}")` en múltiples clases. Esto dificulta la validación en startup, la documentación de la configuración y el sobreescritura por entorno (dev/stage/prod).

#### Problema anterior vs. solución

```java
// ANTES — disperso, sin validación, sin documentación
@Service
public class JwtTokenService {
    public JwtTokenService(
        @Value("${jwt.secret}")     String secret,
        @Value("${jwt.expiration}") long   expiration) { ... }
}

// DESPUÉS — centralizado, tipado, documentado
@ConfigurationProperties(prefix = "jwt")
@Data
public class JwtProperties {
    /** Clave HMAC-256 mínimo 32 chars. Override: JWT_SECRET */
    private String secret;
    /** Expiración en ms. Override: JWT_EXPIRATION */
    private long expiration = 3600000L;
}

@Service
@RequiredArgsConstructor
public class JwtTokenService {
    private final JwtProperties jwtProperties;  // inyectado como bean tipado
}
```

#### Clases de configuración creadas

| Clase | Prefijo | Servicio | Parámetros |
|---|---|---|---|
| `JwtProperties` | `jwt.*` | auth-service | `secret`, `expiration` |
| `QrProperties` | `qr.*` | auth-service | `secret`, `expiration` |
| `DashboardProperties` | `circleguard.*` | dashboard-service | `promotionServiceUrl`, `analyticsKAnonymityThreshold`, `promotionServiceTimeoutMs` |
| `CircleguardProperties` | `circleguard.*` | promotion-service | `kafka.topic-*`, `fence.default-*` |

#### Sobreescritura por entorno

Todos los valores son sobreescribibles mediante variables de entorno siguiendo la convención Spring:

```yaml
# application.yml (valores por defecto para dev)
circleguard:
  promotion-service-url: ${CIRCLEGUARD_PROMOTION_SERVICE_URL:http://promotion-service:8088}
  kafka:
    topic-status-changed: ${CIRCLEGUARD_KAFKA_TOPIC_STATUS_CHANGED:promotion.status.changed}
```

```bash
# K8s Secret/ConfigMap en prod puede sobreescribir sin recompilar:
CIRCLEGUARD_PROMOTION_SERVICE_URL=http://promotion-service-prod.internal:8088
JWT_SECRET=<secret-from-vault>
```

#### Beneficios

| Beneficio | Descripción |
|---|---|
| **Validación en startup** | Spring falla rápido si un parámetro requerido está ausente |
| **Documentación integrada** | Los Javadocs en las clases `*Properties` sirven como documentación viva |
| **Tipo seguro** | `long expiration` vs `String` — errores de tipo detectados en compilación |
| **Sobreescritura por entorno** | dev/stage/prod con diferentes valores sin recompilar |
| **Testabilidad** | Tests pueden instanciar `JwtProperties` directamente con valores de prueba |

---

### 3.3 Retry

**Categoría:** Resiliencia  
**Librería:** Resilience4j 2.1.0  
**Servicio:** `auth-service` → `IdentityClient`  
**Archivo:** `auth/client/IdentityClient.java`

#### Contexto y Problema

La llamada de `auth-service` a `identity-service` durante el login puede fallar por errores transitorios de red (timeout breve, pod reiniciándose en K8s). Un pod de Spring Boot tarda ~1-2 segundos en reiniciarse; con 3 reintentos de 500ms, el login tiene alta probabilidad de éxito sin que el usuario perciba el fallo.

#### Implementación

```java
// Resilience4j aplica las decoraciones de afuera hacia adentro:
// Retry envuelve → CircuitBreaker
@Retry(name = "identityService", fallbackMethod = "getAnonymousIdFallback")
@CircuitBreaker(name = "identityService", fallbackMethod = "getAnonymousIdFallback")
public UUID getAnonymousId(String realIdentity) { ... }
```

**Configuración en `application.yml`:**

```yaml
resilience4j:
  retry:
    instances:
      identityService:
        max-attempts: 3          # Hasta 3 intentos en total
        wait-duration: 500ms     # 500ms entre intentos
        retry-exceptions:
          - org.springframework.web.client.ResourceAccessException   # timeout red
          - org.springframework.web.client.HttpServerErrorException  # 5xx
        ignore-exceptions:
          - io.github.resilience4j.circuitbreaker.CallNotPermittedException  # no reintentar con CB abierto
```

**Flujo de ejecución:**

```
LoginController.login()
        │
        ▼
IdentityClient.getAnonymousId("juan@uni.edu")
        │
        ├── Intento 1 → ResourceAccessException (timeout)
        │       └── espera 500ms
        ├── Intento 2 → ResourceAccessException (pod reiniciando)
        │       └── espera 500ms
        ├── Intento 3 → éxito → retorna UUID real
        │
        │ (si los 3 fallan)
        └── fallback → UUID determinístico basado en username
```

#### Interacción Retry + Circuit Breaker

La combinación de ambos patrones forma una estrategia de resiliencia completa:

| Escenario | Comportamiento |
|---|---|
| Fallo transitorio (1-2 intentos) | Retry lo resuelve, usuario no nota nada |
| Fallo persistente (3 intentos) | Retry agota, CB registra fallo |
| CB en OPEN | `CallNotPermittedException` se ignora en Retry → fallback inmediato |
| Servicio recuperado | CB pasa a HALF-OPEN, primer llamada exitosa lo cierra |

#### Beneficios

| Beneficio | Descripción |
|---|---|
| **Transparencia** | El controller no sabe que hubo reintentos |
| **Tolerancia a fallos de pod** | K8s reinicia pods en ~1s; 3 reintentos de 500ms cubren esa ventana |
| **Complemento al CB** | El Retry trabaja para errores transitorios; el CB para fallos sistémicos |

---

## 4. Tabla Resumen

| # | Patrón | Categoría | Servicio(s) | Archivo(s) Clave | Tipo |
|---|---|---|---|---|---|
| 1 | **Chain of Responsibility** | Comportamental | auth-service | `DualChainAuthenticationProvider.java` | Existente |
| 2 | **Strategy** | Comportamental | notification-service | `EmailService`, `SmsService`, `PushService` + `*Impl` | Existente |
| 3 | **Facade** | Comportamental | notification-service | `NotificationDispatcher.java` | Existente |
| 4 | **Observer / Pub-Sub** | Arquitectónico | promotion, notification | `*Listener.java`, `StatusLifecycleService.java` | Existente |
| 5 | **Repository** | Acceso a datos | Todos | `*Repository.java` (JPA + Neo4j) | Existente |
| 6 | **Cache-Aside** | Rendimiento | promotion, gateway | `CacheConfig.java`, `QrValidationService.java` | Existente |
| 7 | **Feature Toggle** | Configuración | promotion-service | `SystemSettings.java`, `AdminController.java` | Existente |
| 8 | **API Gateway** | Arquitectónico | gateway-service | `GateController.java`, `QrValidationService.java` | Existente |
| 9 | **Template Method** | Comportamental | notification-service | `TemplateService.java` | Existente |
| 10 | **Circuit Breaker** | Resiliencia | dashboard, auth | `PromotionClient.java`, `IdentityClient.java` | **Implementado** |
| 11 | **External Configuration** | Configuración | auth, dashboard, promotion | `JwtProperties`, `DashboardProperties`, `CircleguardProperties` | **Implementado** |
| 12 | **Retry** | Resiliencia | auth-service | `IdentityClient.java` | **Implementado** |

---

*Documentación generada para el Proyecto Final de Ingeniería de Software V — CircleGuard v1.0.0*
