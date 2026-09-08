# Lockpost — Oracle VPS Deployment Checklist

**Project:** sym-pgp-ony  
**Target:** Oracle Cloud VPS, Ubuntu  
**Network:** host networking, port `80/443`  
**Data:** `../config/pgp` + `../.env` bind-mounted from host

---

## Preflight

- [ ] VPS subnet Security List allows inbound TCP `80,443` from `0.0.0.0/0`
- [ ] You have shell access and sudo rights
- [ ] Domain `yourdomain.com` points to the VPS public IP

---

## 1) Base System

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y git curl ca-certificates gnupg ufw
```

- [ ] Base packages installed

---

## 2) Firewall

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
echo "y" | sudo ufw enable
sudo ufw status
```

- [ ] `ufw` enabled
- [ ] `80/tcp` and `443/tcp` allowed

---

## 3) Docker

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
docker --version && docker compose version
```

- [ ] Docker Engine `24+` installed
- [ ] Docker Compose v2 installed
- [ ] Docker service active

---

## 4) App Code

```bash
sudo mkdir -p /opt/lockpost
sudo chown -R "$(whoami)":"$(whoami)" /opt/lockpost
git clone <repo-url> /opt/lockpost
cd /opt/lockpost
```

- [ ] Repo cloned to `/opt/lockpost`
- [ ] Working directory is `/opt/lockpost`

---

## 5) Environment

```bash
cp .env.production.example .env
```

Edit `../.env`:
- [ ] `APP_SECRET` = output of `openssl rand -hex 32`
- [ ] `APP_MAIL_FROM` = real sender at your domain
- [ ] `PGP_PRIVATE_KEY_PASSPHRASE` = strong secret
- [ ] `MAILER_DSN` = `smtp://127.0.0.1:25`

> `../.env` is gitignored. Do not commit it.

---

## 6) Postfix

```bash
sudo apt-get install -y postfix
sudo postconf -e "inet_interfaces = loopback-only"
sudo postconf -e "mynetworks = 127.0.0.0/8"
sudo systemctl restart postfix
sudo systemctl enable postfix
telnet 127.0.0.1 25
```

- [ ] Postfix installed
- [ ] Listening on loopback only
- [ ] SMTP banner confirmed (`220 ... ESMTP Postfix`)

---

## 7) PGP Keys

```bash
docker compose -f docker-compose.prod.yml up -d php
docker exec php bash /var/www/app/scripts/init-pgp.sh
docker exec php bash -c "chown -R www-data:www-data /var/www/app/config/pgp /var/www/app/var"
docker exec php bash /var/www/app/scripts/validate-pgp.sh
```

- [ ] `php` container running
- [ ] Key pair generated
- [ ] Ownership/permissions correct
- [ ] Validation script passed

---

## 8) Build and Start

```bash
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
docker compose -f docker-compose.prod.yml ps
```

- [ ] Images built
- [ ] `nginx` and `php` containers `running`
- [ ] `restart: unless-stopped` set

---

## 9) Cache Warmup

```bash
docker exec php php bin/console cache:clear --no-debug
docker exec php php bin/console cache:warmup --no-debug
docker exec php php bin/console asset-map:compile
docker exec php chown -R www-data:www-data /var/www/app/var/ /var/www/app/config/pgp/
```

- [ ] Cache warmup complete
- [ ] `/var/www/app/var/` and `/var/www/app/config/pgp/` owned by `www-data`

---

## 10) Smoke Tests

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost/   # expect 200
curl -s http://localhost/server-key | grep "BEGIN PGP PUBLIC KEY BLOCK"
docker exec php sh -c 'export APP_ENV=test APP_DEBUG=1; php bin/phpunit tests/BootstrapTest.php --no-coverage'
```

- [ ] NGINX returns `200`
- [ ] `/server-key` returns armored public key
- [ ] Bootstrap smoke test passes


---

## 11) TLS (Optional but Recommended)

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
sudo certbot renew --dry-run
```

- [ ] Certificate obtained
- [ ] HTTP→HTTPS redirect active
- [ ] Auto-renewal dry-run passes

---

## 12) Redeployment

```bash
cd /opt/lockpost
git pull
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
docker exec php php bin/console cache:clear --no-debug
docker exec php php bin/console cache:warmup --no-debug
docker exec php php bin/console asset-map:compile
docker exec php chown -R www-data:www-data /var/www/app/var/ /var/www/app/config/pgp/
curl -s -o /dev/null -w "%{http_code}" http://localhost/
```

- [ ] Code pulled
- [ ] Containers recreated
- [ ] Cache warmed
- [ ] Smoke test passes

### Automated Option (Salt)

```bash
salt-ssh -i ~/.ssh/ssh-key-oracle.key -c salt/ lockpost state.apply lockpost
```

- [ ] Salt deployment executed (`lockpost.sls` applies all stages)


---

## Troubleshooting

| Symptom | Check |
|---|---|
| `connection refused` on port 80 | Security List + `ufw` rules |
| Postfix refused from container | `inet_interfaces = loopback-only` and `mynetworks` |
| PGP validation fails | `../config/pgp` permissions, AppArmor `:Z` mount |
| 502 from NGINX | `docker compose ps`, PHP-FPM logs |
| `/server-key` 404 | `../config/pgp/public.key` present in bind mount |

---

**Done when:** homepage returns `200`, `/server-key` returns the public key, and PHPUnit is green.
