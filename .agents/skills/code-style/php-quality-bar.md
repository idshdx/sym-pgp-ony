---
skill: php-quality-bar
domain: sym-pgp-ony/code-style
title: PHP Quality Gate
description: Maintaining modern PHP code quality, architecture, and security standards for the Lockpost Symfony project.
---

# PHP Quality Gate

**Use when:** Writing or reviewing PHP code in the Lockpost Symfony project. Enforces architectural invariants, security boundaries, and quality standards.

## Stack
- **PHP 8.4** (platform pinned in `composer.json` config.platform.php)
- **Symfony 7.4** (FrameworkBundle, Form, HttpKernel, Mailer, Validator, RateLimiter, CSRF)
- **PHPUnit 12** (via plain PHPUnit, not Symfony PHPUnit Bridge)

## 1. Constructor Property Promotion
All service classes must use PHP 8 promoted readonly constructor parameters:
```php
public function __construct(
    private readonly HttpClientInterface $httpClient
) {}
```
No manual property declarations + assignment in constructor body. No public properties.

## 2. Exception Chaining
Every `catch` block that wraps an exception must pass `$previous` as the third argument:
```php
throw new AppException('User-facing message', 0, $e);
```
This preserves the full stack trace for production debugging.

## 3. Namespaces Must Import Caught Exception Types
**Always** import `Exception` (or `\Exception`) in any namespaced PHP file that uses `catch (Exception $e)`:
```php
namespace App\Controller;

use Exception;  // ← REQUIRED in PHP 8.x
```
Without this import, PHP 8.x resolves the bare `Exception` in the catch clause to the current namespace (`App\Controller\Exception`) — a class that does not exist. Unlike PHP 7.x, PHP 8.x does **not** fall back to the global `\Exception` for class references in catch clauses. This causes the catch block to silently not match any exception, so uncaught exceptions propagate to Symfony's ExceptionListener and produce HTTP 500 errors instead of the intended redirect/error handling. The bug passes PHP linting (no syntax error) but breaks runtime exception handling.

**Affected patterns:**
- `catch (Exception $e)` in controllers → install `use Exception;`
- `catch (\Throwable $e)` is always safe (FQCN, no import needed)
- `catch (AppException $e)` requires `use App\Exception\AppException;` (or FQCN)

## 4. No Information Leaks to Users
- **Never** return `$e->getMessage()` to the client (HTML, JSON, flash, session).
- Use generic messages: "An internal error occurred while sending the message."
- Always log the full exception via `LoggerInterface`.
- `ErrorHandler::handleControllerException()`: AppException → HTTP 400, generic Exception → HTTP 500.

## 5. CSRF Protection on JSON Endpoints
All POST endpoints that accept JSON (not Symfony Forms) must validate CSRF tokens:
```php
$token = new CsrfToken('submit_message', $data['_csrf_token'] ?? '');
if (!$this->csrfTokenManager->isTokenValid($token)) {
    return $this->json(['success' => false, 'error' => 'Invalid or missing CSRF token'], Response::HTTP_BAD_REQUEST);
}
```
Stimulus controllers must pass `data-controller-csrf-token-value="{{ csrf_token('submit_message') }}"`.

## 6. Rate Limiting on Abuse-Prone Endpoints
Email-sending and key-lookup endpoints must have both IP and token rate limiting:
- `submit_ip`: `fixed_window`, limit=5, interval=1 minute (requires `symfony/lock`)
- `submit_token`: `sliding_window`, limit=10, interval=1 hour
Both must be consumed before processing; return HTTP 429 with `Retry-After` header on rejection.

## 7. PGP/GnuPG Security
- **Passphrase enforcement**: `PgpSigningService::__construct()` must throw `AppException` if passphrase is empty in `prod`/`test` environments.
- **No keyring pollution**: `verifySignature()` must create an isolated temp GnuPG home per call (never import untrusted keys into server keyring).
- **Signer caching**: `PgpSigningService` must cache a single `gnupg` instance initialized once in constructor. `signMessage()` must NOT call `putenv()` or re-import the key on every call.
- **Verify API**: Use `$gpg->verify($signedMessage, false)` for combined cleartext-signed blocks. Check `($sig['summary'] & GNUPG_SIGSUM_RED) === 0` for validity.
- **GNUPGHOME consistency**: `docker-compose.yml` env var must match `services.yaml` `app.pgp.key_config_path` parameter.

## 8. HTTP Client Usage (PgpKeyService)
- Fire all key-server requests concurrently
- Use `'http_errors' => false` to prevent exceptions on 4xx/5xx during streaming
- Short-circuit on first valid 2xx response with PGP key block
- Cancel remaining responses in a `finally` block
- `MockHttpClient` in tests must delegate `cancel()` and `stream()` to Symfony's `MockHttpClient`

## 9. Docker/Infrastructure Security
- **PHP-FPM**: Use `expose` (not `ports`) for internal services. Only nginx publishes ports.
- **Process user & permissions**: PHP-FPM worker pools run as `www-data:www-data` (`uid=33`). Runtime directories (`var/`, `config/pgp/`) must be owned by `www-data:www-data`. Never use or reference non-existent users like `appuser` in deploy scripts, Salt states, or Docker entrypoints.
- **Production asset compilation**: Symfony AssetMapper requires `php bin/console asset-map:compile` during production cache warmup.
- **Headless container execution**: In automated CI/CD scripts, orchestration (Salt), or non-interactive shells, always pass `-T` to `docker compose exec` (`docker compose exec -T php ...`) to avoid pseudo-TTY allocation failures.
- **Extensions**: Only install what the app needs. No `pdo_mysql`, `redis`, `gd`.
- **Xdebug**: Only in dev build stage (`target: dev`). Production uses `target: final`.
- **Status endpoints**: `/nginx_status`, `/status`, `/ping` restricted to `127.0.0.1` via `allow/deny`.
- **Body size**: `client_max_body_size 1M` (PGP text is small).
- **Networking**: Use bridge network with named networks in prod. Avoid `network_mode: host`.
- **Composer**: Install from official `composer:2` image, not `curl installer | php`.

## 10. Email Template Standards
- Single `<!DOCTYPE html>` — never duplicate documents.
- No `<script>`, `onclick`, or `display:none` — email clients strip JavaScript.
- All sections always visible using `<table>` layout with inline CSS.
- All user content escaped via `| e` filter.

## 11. Environment & Config Hygiene
- `ext-opcache` not `ext-zend-opcache` in `composer.json`.
- `composer.json` config: `platform: { php: "8.4", ext-opcache: "8.3" }` and `platform-check: false` (OPcache loads as Zend extension; Composer can't detect it in CLI mode).
- `MESSENGER_TRANSPORT_DSN=sync://` (not `doctrine://`).
- Delete dead config files (`config/packages/gpg.yaml`) and dead assets (`public/jquery.min.js`).
- `framework.yaml` session: `cookie_samesite: lax` explicit.
- `importmap.php` must be committed — it registers `@hotwired/stimulus` and `openpgp` for asset mapper.

## 12. Testing Standards
- TDD: add tests before modifying code when test gaps exist.
- Tests must not make real network calls — use `MockHttpClient` for `PgpKeyService`.
- Fix test naming typos (e.g., `testInvalidSighing` → `testInvalidSigning`).
- `TokenLinkServiceTest` covers: roundtrip, case-insensitive email, tamper detection, expired token, garbage token.
- **PHPUnit 12 metadata**: Use PHP 8 attributes (`#[DataProvider('method')]`, `#[Test]`, etc.) — PHPUnit 12 dropped support for annotation-based metadata (`@dataProvider`, `@test`, etc.).
- **Catch clause imports**: See Section 3 — any controller/service using `catch (Exception $e)` must import `use Exception;` or the catch silently fails in PHP 8.4.
- **`use Exception;` import**: In namespaced PHP files (controllers, services), always add `use Exception;` at the top if the file uses `catch (Exception $e)`. Without the import, PHP 8.4 resolves `Exception` to `App\Controller\Exception` (which doesn't exist), causing catch blocks to silently fail — exceptions propagate as 500 errors with no redirect handling. The global `\Exception` fallback for built-in classes does NOT apply to catch clauses in PHP 8.x.

## References
- See `references/` directory for session-specific debugging notes, error transcripts, and domain notes.
  - `references/debugging-notes-aug2026.md` — debugging notes for PHP 8.4/ PHPUnit 12 deployment issues: `use Exception;` import, `#[DataProvider]` attributes, MockHttpClient UID, passphrase-protected key tests, git safe.directory
  - `references/crlf-line-endings-fix.md` — CRLF fix for shell scripts in Docker
