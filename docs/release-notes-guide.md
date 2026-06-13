# Release Notes — Proceso de Generación y Gestión

## Tabla de contenidos

1. [Fundamento: Conventional Commits](#1-fundamento-conventional-commits)
2. [Script de generación](#2-script-de-generación)
3. [Estructura del archivo generado](#3-estructura-del-archivo-generado)
4. [Integración con el pipeline de producción](#4-integración-con-el-pipeline-de-producción)
5. [Actualización automática del CHANGELOG](#5-actualización-automática-del-changelog)
6. [Etiquetado en Git](#6-etiquetado-en-git)
7. [Notificación por correo](#7-notificación-por-correo)
8. [Ejemplo de release notes generadas](#8-ejemplo-de-release-notes-generadas)

---

## 1. Fundamento: Conventional Commits

Las release notes se generan de forma automática a partir del historial de Git. Para que esta automatización funcione correctamente, todos los commits del proyecto deben seguir la especificación **Conventional Commits**, que establece un formato estructurado para los mensajes de commit:

```
<tipo>(<ámbito opcional>): <descripción>
```

El script de generación reconoce los siguientes tipos y los mapea a secciones del documento:

| Tipo de commit | Sección en las release notes |
|---|---|
| `feat` | Nuevas Funcionalidades |
| `fix` | Correcciones |
| `ci`, `build` | CI/CD e Infraestructura |
| `refactor` | Refactoring |
| `docs` | Documentación |
| `chore`, `style`, `test`, `perf` | Mantenimiento |
| `BREAKING CHANGE` o `!:` en cualquier tipo | Breaking Changes (sección prioritaria) |

Commits que no sigan el formato convencional no aparecen en las release notes. Esto refuerza la disciplina de escritura de commits en el equipo: un cambio que no está correctamente categorizado no queda registrado en el historial de versiones.

---

## 2. Script de generación

El script `scripts/generate-release-notes.sh` es el núcleo del sistema. Recibe hasta tres argumentos:

```
./scripts/generate-release-notes.sh <VERSION> [PREV_TAG] [OUTPUT_FILE]
```

| Argumento | Obligatorio | Descripción |
|---|---|---|
| `VERSION` | Sí | Versión de la release (ej. `v1.2.0`) |
| `PREV_TAG` | No | Tag git desde el cual calcular los cambios. Si se omite, el script detecta automáticamente el tag anterior al HEAD |
| `OUTPUT_FILE` | No | Ruta del archivo de salida. Por defecto: `release-notes.md` |

Adicionalmente, el script lee la variable de entorno `DOCKER_USER` para construir las referencias completas a las imágenes Docker en la tabla de artefactos.

**Funcionamiento interno:**

El script determina primero el rango de commits a analizar. Si se pasa `PREV_TAG`, el rango es `PREV_TAG..HEAD`. Si no se pasa, el script busca automáticamente el segundo tag semver más reciente del repositorio (el más reciente sería la versión actual, el segundo sería la anterior). A partir de ese rango ejecuta `git log` con el formato `%s (%an)` para obtener el asunto del commit y el nombre del autor.

Para cada categoría se aplica un filtro `grep` con el tipo de commit correspondiente, seguido de una transformación `sed` que extrae solo la descripción, eliminando el prefijo del tipo. El resultado de cada categoría se almacena en una variable y luego se incluye condicionalmente en el documento final: una sección solo aparece en las release notes si existe al menos un commit de ese tipo en el rango analizado. Esto evita secciones vacías en versiones donde, por ejemplo, no hubo cambios en la documentación.

---

## 3. Estructura del archivo generado

El archivo de salida sigue siempre la misma estructura:

```
# CircleGuard — Release <VERSION>

Fecha: <fecha de ejecución>
Commit: <SHA corto del HEAD>
Tag anterior: <PREV_TAG>

---

## ⚠️ Breaking Changes          ← solo si existen
## ✨ Nuevas Funcionalidades     ← solo si existen
## 🐛 Correcciones              ← solo si existen
## ⚙️ CI/CD e Infraestructura   ← solo si existen
## ♻️ Refactoring               ← solo si existen
## 📖 Documentación             ← solo si existen
## 🔧 Mantenimiento             ← solo si existen

---

## 🐳 Imágenes Docker

Tabla con el tag exacto de cada una de las 7 imágenes de la release.
```

La sección de imágenes Docker siempre aparece al final, independientemente del contenido del resto del documento. Incluye la referencia completa a cada imagen en Docker Hub con el tag de la versión, lo que permite a cualquier miembro del equipo u operador reproducir exactamente el despliegue de esa versión.

---

## 4. Integración con el pipeline de producción

El script es invocado automáticamente por la etapa `Generate Release Notes` del pipeline `Jenkinsfile.master`, que se ejecuta únicamente en la rama `main`. Esta etapa opera sobre la versión calculada por la etapa `Semantic Version (Stable)` al inicio del pipeline, que construye un tag semver estricto con el formato `vMAJOR.MINOR.PATCH` a partir del último tag existente en el repositorio.

La secuencia dentro del pipeline es:

1. El pipeline calcula `IMAGE_TAG` (ej. `v1.3.0`) en la etapa de versión semántica.
2. Todas las etapas de build, test, análisis de calidad, Docker push, E2E, rendimiento y seguridad se ejecutan con ese tag.
3. La etapa `Generate Release Notes` detecta el tag anterior mediante `git tag --sort=-v:refname`, extrae el segundo resultado de la lista y ejecuta el script con el tag nuevo, el anterior y el nombre de archivo `RELEASE_FILE` definido como variable de entorno en el pipeline.
4. El archivo generado se archiva como artefacto del build en Jenkins, quedando disponible para descarga desde la interfaz del pipeline.
5. El CHANGELOG del repositorio se actualiza en disco (ver sección 5).
6. Se solicita aprobación manual (ver sección siguiente).
7. Tras la aprobación, se despliega en producción.
8. Se crea el tag git y se hace push del CHANGELOG actualizado (ver sección 6).
9. Se envía notificación por correo con las release notes adjuntas (ver sección 7).

---

## 5. Actualización automática del CHANGELOG

El `CHANGELOG.md` del repositorio funciona como registro histórico acumulativo de todas las versiones. El pipeline actualiza este archivo automáticamente dentro de la misma etapa `Generate Release Notes`, sin requerir ninguna acción manual del equipo.

El mecanismo de actualización es el siguiente: el pipeline lee las primeras seis líneas del `CHANGELOG.md` existente, que corresponden al encabezado del archivo con el título, la descripción del formato y la línea separadora. A continuación lee el cuerpo restante del archivo, que contiene todas las versiones anteriores. Luego construye el nuevo archivo interponiendo el contenido de las release notes recién generadas entre el encabezado y el cuerpo histórico. El resultado es que la versión más reciente siempre aparece al inicio del CHANGELOG, seguida de todas las versiones anteriores en orden cronológico inverso.

Este enfoque garantiza que el CHANGELOG sea siempre el reflejo exacto de lo que fue desplegado en producción, dado que se genera a partir del historial de Git real y no de notas escritas manualmente. También garantiza que el archivo sea legible por herramientas externas que lo parseen, como portales de releases de GitHub, porque mantiene el formato estándar de Keep a Changelog.

---

## 6. Etiquetado en Git

La etapa `Tag Release in Git` cierra el ciclo del pipeline de producción. Después de verificar que el despliegue en producción fue exitoso, el pipeline:

1. Configura la identidad de Git con el usuario y correo de Jenkins (`jenkins@circleguard.edu`).
2. Agrega el `CHANGELOG.md` actualizado al área de staging de Git.
3. Crea un commit con el mensaje `chore(release): update CHANGELOG for <VERSION> [skip ci]`. La anotación `[skip ci]` es fundamental: indica a Jenkins que no debe ejecutar el pipeline nuevamente cuando se haga push de este commit, evitando un ciclo infinito de builds.
4. Crea un tag git anotado con el número de versión y un mensaje que incluye el número de build de Jenkins, lo que permite relacionar cualquier tag del repositorio con el build específico que lo produjo.
5. Hace push del tag al repositorio remoto, publicándolo como una release oficial.
6. Hace push del commit del CHANGELOG a la rama `main`.

El tag anotado es la referencia definitiva de una versión productiva. Cualquier rollback a esa versión parte de ese tag, y las imágenes Docker correspondientes a ese tag están disponibles en Docker Hub con exactamente el mismo identificador.

---

## 7. Notificación por correo

Tras un despliegue exitoso a producción, el pipeline envía automáticamente un correo electrónico de notificación a la dirección configurada en la variable `NOTIFY_EMAIL` del pipeline. El correo incluye el número de build, la versión desplegada, el enlace a la consola de Jenkins del build, y el archivo de release notes generado adjunto como archivo Markdown.

En caso de fallo del pipeline, se envía un correo diferente con el asunto marcado como fallido, incluyendo el enlace directo a la consola del build para diagnóstico. Esta notificación opera tanto para fallos en el propio pipeline como para fallos en la aprobación manual si el timeout de treinta minutos se agota sin respuesta.

---

## 8. Ejemplo de release notes generadas

El siguiente es el formato exacto que produce el script para una versión de ejemplo con cambios en múltiples categorías:

```markdown
# CircleGuard — Release v1.2.0

**Fecha:** 2026-06-15
**Commit:** `a3f9c12`
**Tag anterior:** `v1.1.0`

---

## ✨ Nuevas Funcionalidades

- add QR token expiration validation in gateway (Ana Gómez)
- add department-level analytics endpoint in dashboard (Carlos Ruiz)

## 🐛 Correcciones

- correct contact tracing window off-by-one in promotion service (Ana Gómez)
- fix Redis key format for user status lookup (Carlos Ruiz)

## ⚙️ CI/CD e Infraestructura

- add Trivy CronJob for periodic image scanning (Sebastian Poveda)
- add OWASP ZAP baseline scan to production pipeline (Sebastian Poveda)

## 🔧 Mantenimiento

- upgrade Spring Boot to 3.3.1 (Ana Gómez)
- add integration tests for notification dispatcher (Carlos Ruiz)

---

## 🐳 Imágenes Docker

| Servicio | Tag |
|---|---|
| auth-service | `simongarcia01/auth-service:v1.2.0` |
| identity-service | `simongarcia01/identity-service:v1.2.0` |
| promotion-service | `simongarcia01/promotion-service:v1.2.0` |
| gateway-service | `simongarcia01/gateway-service:v1.2.0` |
| notification-service | `simongarcia01/notification-service:v1.2.0` |
| dashboard-service | `simongarcia01/dashboard-service:v1.2.0` |
| form-service | `simongarcia01/form-service:v1.2.0` |
```
