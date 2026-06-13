# Changelog — CircleGuard

Todos los cambios notables del proyecto se documentan aquí.
Formato basado en [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versionado siguiendo [Semantic Versioning](https://semver.org/).

---

<!-- El pipeline de producción (Jenkinsfile.master) antepone nuevas entradas aquí automáticamente. -->

## [1.0.0] — 2026-06-12

### Nuevas Funcionalidades
- Arquitectura completa de microservicios: auth, identity, promotion, gateway, notification, dashboard, form
- Contact tracing con grafo de contactos en Neo4j
- Control de acceso por QR con validación en tiempo real (Redis)
- Autenticación dual LDAP + DB local (Chain of Responsibility)
- Sistema de notificaciones multicanal: email, SMS, push
- Dashboard de salud con k-anonimato para privacidad diferencial
- Formularios de autocertificación con flujo de cuarentena automático

### CI/CD e Infraestructura
- Pipeline Jenkins para dev (Jenkinsfile), stage (Jenkinsfile.stage) y prod (Jenkinsfile.master)
- Kubernetes multi-ambiente: namespaces dev / stage / prod / ci
- Observabilidad: Prometheus + Grafana + ELK + Jaeger
- Seguridad: RBAC, K8s Secrets, TLS/Ingress, Trivy CronJob

### Patrones de Diseño Implementados
- Circuit Breaker + Retry (Resilience4j) en auth-service y dashboard-service
- External Configuration (@ConfigurationProperties) en auth, dashboard y promotion-service

---

*Próximas entradas generadas automáticamente por el pipeline de producción.*
