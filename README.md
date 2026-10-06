# Onest Lite

App iOS nativa (SwiftUI, iOS 16+, Swift Concurrency, sin dependencias de terceros) para iniciar sesión, ver préstamos y solicitar uno nuevo contra un backend simulado.

> **Uso de IA:** este proyecto se construyó con ayuda de un asistente de IA (Claude Code). Revisé y entiendo el código; las decisiones de diseño de abajo son defendibles línea por línea.

## Cómo ejecutarlo

```bash
open OnestLite.xcodeproj          # Run en cualquier simulador iOS 16+
xcodebuild test -project OnestLite.xcodeproj -scheme OnestLite \
  -destination 'platform=iOS Simulator,name=iPhone 14'
```

El `.xcodeproj` está versionado; se genera desde `project.yml` con [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`, solo si cambias la estructura).

**Usuario demo:** `demo` / `demo1234`. Variables de entorno opcionales (Edit Scheme › Run) para probar escenarios: `ONEST_ACCESS_LIFETIME=10` (access token de 10 s), `ONEST_REFRESH_LIFETIME=30` (fuerza el re-login rápido), `ONEST_FAST_MOCK=1` (sin latencia).

## Arquitectura y por qué

MVVM con `@MainActor ObservableObject` (iOS 16 no tiene `@Observable`), repositorios detrás de protocolos y composición manual en `AppEnvironment`. Sin frameworks de arquitectura: para 5 pantallas, protocolos + inyección por constructor dan testabilidad sin costo extra.

```
Core/Networking  HTTPTransport (protocolo) · APIClient · Endpoint · APIError
Core/Auth        AuthSession (actor) · TokenStore (Keychain)
Mock/            MockBackend (actor) · MockTransport · LoanCalculator
Data/            LoanRepository
Features/        Login · Loans · LoanDetail · Apply (ViewModel + View)
```

- **El backend simulado vive detrás de `HTTPTransport`**, la misma abstracción que usa `URLSessionTransport`. Pasar a un servidor real = cambiar `MockTransport` por `URLSessionTransport` y la `baseURL` en `AppEnvironment.live()`. Ni repositorios ni ViewModels se enteran.
- **Renovación de token con peticiones concurrentes:** `AuthSession` es un `actor` con una `Task` de refresh compartida. Si N peticiones reciben 401, solo una llama a `/auth/refresh` y las demás esperan el mismo resultado. Esto es obligatorio con refresh tokens rotativos (reusar uno invalida la sesión). Además se renueva de forma proactiva 5 s antes de expirar, y si el token ya cambió mientras esperaba, no hay llamada de red.
- **Dinero en centavos (`Int`)**, nunca `Double`; el formato `RD$25,000.00` sale de `Decimal.formatted(.currency(code: "DOP"))` con locale `es_DO`.
- **Idempotencia:** `POST /loans` lleva `Idempotency-Key`. El ViewModel crea la llave una vez por solicitud y la reusa en cada reintento; si el usuario edita las condiciones es otra solicitud y otra llave. El repositorio reintenta 5xx/red hasta 3 veces con backoff y la misma llave.

## Contrato de la API simulada (JSON, fechas ISO 8601, montos en centavos)

| Ruta | Cuerpo → respuesta |
|---|---|
| `POST /auth/login` | `{username,password}` → `{accessToken,refreshToken,expiresIn}`; 401 credenciales inválidas |
| `POST /auth/refresh` | `{refreshToken}` → tokens nuevos; 401 si el refresh expiró |
| `GET /loans` | `[Loan]`; 401 si el access expiró; latencia 0.5–2 s |
| `GET /loans/{id}` | `{loan, schedule:[{number,dueDate,amountCents,isPaid}]}`; 404 |
| `POST /loans/quote` | `{amountCents,termMonths}` → `{amountCents,termMonths,monthlyPaymentCents,annualRatePercent,totalCostCents}`; 422 fuera de 5,000–100,000 DOP o 3–24 meses |
| `POST /loans` | igual que quote + header `Idempotency-Key` → 201 `Loan` en `EN_REVISION`; 500 el 25 % de las veces; misma llave = mismo préstamo |

`Loan`: `{id, amountCents, outstandingBalanceCents, termMonths, annualRatePercent, nextPaymentDate?, status, createdAt}`. Errores: `{"error":{"code","message","fields?"}}`.

## Seguridad

- Tokens solo en **Keychain** (`WhenUnlockedThisDeviceOnly`: sin respaldo ni migración a otro dispositivo). Nunca en `UserDefaults` ni en logs.
- **Logout** borra el ítem de Keychain, cancela renovaciones en vuelo y descarta todo el estado de UI (cambia el `id` de la vista raíz). Una renovación que termine después del logout no puede reescribir credenciales (contador de época, con prueba).
- Keychain sobrevive a la desinstalación en iOS: en la primera ejecución se limpia.
- Si el refresh token expira, se borra la sesión y se vuelve al login con aviso.
- El mock firma sus tokens con HMAC-SHA256 (stateless), así la sesión sobrevive a reinicios de la app.
- Contraseña se limpia del ViewModel tras cada intento; el formulario valida entrada sin `Double` ni crashes por overflow.

## Pruebas (37)

Renovación concurrente (20 llamadas → 1 refresh; 10 peticiones con 401 → 1 refresh), refresh vencido → re-login, logout durante refresh, validación del formulario, contrato del mock (422/404/idempotencia/500 con reintento), ViewModels de login, lista y solicitud, y Keychain real.

## Qué dejé fuera / con dos semanas más

- Probé la UI en iOS 16.4 solo parcialmente; faltan pruebas de UI (XCUITest) de los flujos completos.
- Sin localización formal (textos en español en el código; usaría String Catalog), sin modo oscuro revisado ni Dynamic Type exhaustivo.
- Revocación real de refresh tokens y detección de reuso (el mock es stateless), `POST /auth/logout`, certificate pinning y bloqueo biométrico al volver de segundo plano.
- Paginación de `/loans`, caché offline y analítica/observabilidad.
- Calendario de pagos y cálculo de cuota hechos por el mock; en producción vendrían del servidor.
