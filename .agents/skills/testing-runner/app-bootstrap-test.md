---
name: app-bootstrap-test
description: Verify the Lockpost Symfony application can bootstrap successfully by running its bootstrap smoke tests.
---

# App Bootstrap Test

**Use when:** Checking whether the application boots and basic core services/route are available. This is a smoke test, not a full functional verification.

## What it checks

- Symfony kernel boots in the `test` environment.
- Core services (`router`, `request_stack`, `event_dispatcher`) are available in the container.
- The default route responds successfully.

## Prerequisites

- Containers built and started: `docker compose up --build -d`
- PHP dependencies installed: `docker compose exec php composer install --no-scripts`
- PGP keys generated if you also want to validate signing-related bundles: `docker compose exec php bash /var/www/app/scripts/init-pgp.sh --with-passphrase your-secure-passphrase`
- File permissions fixed: `docker compose exec php bash -c "chown -R www-data:www-data /var/www/app/var/ /var/www/app/config/pgp/"`
- Git safe directory configured: `docker compose exec php bash -c "git config --global --add safe.directory /var/www/app"`

## Commands

### Local Dev Environment

```bash
docker compose exec php php bin/phpunit tests/BootstrapTest.php --no-coverage
```

### Production Environment / Headless Runners

> **Important:** In production containers (`docker-compose.prod.yml`), `APP_ENV=prod` is set by default. Functional tests extending `WebTestCase` will throw `LogicException: You cannot create the client used in functional tests if the "framework.test" config is not set to true` unless `APP_ENV=test` is explicitly exported.
> 
> Also use `-T` to disable pseudo-TTY allocation when running through automated deployment tools or non-interactive shells.

```bash
# In production containers or automated deployment scripts:
docker compose -f docker-compose.prod.yml exec -T php sh -c 'export APP_ENV=test APP_DEBUG=1; php bin/phpunit tests/BootstrapTest.php --no-coverage'
```

### Post-Bootstrap Smoke Checks

After the bootstrap test passes, verify key HTTP endpoints return `200 OK`:

```bash
curl -sI http://127.0.0.1:80/ | head -5
curl -sI http://127.0.0.1:80/verify | head -5
curl -sI http://127.0.0.1:80/server-key | head -5
```

## Notes

- `tests/BootstrapTest.php` is the project bootstrap smoke test.
- If this test fails, the app is not ready for broader test execution or deployment.
- `--no-coverage` keeps this check fast; coverage is not the goal here.

