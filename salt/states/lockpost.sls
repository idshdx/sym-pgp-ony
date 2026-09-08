# Salt state: deploy_lockpost
# Pulls latest code, rebuilds Docker images, restarts containers, warms cache.
# Uses salt-ssh to execute on the Oracle VPS.

deploy_lockpost:
  cmd.run:
    - name: |
        set -e
        cd /opt/lockpost
        git fetch origin
        git reset --hard origin/main
        find docker/ -type f -exec sed -i 's/\r$//' {} +
        docker compose -f docker-compose.prod.yml pull
        docker compose -f docker-compose.prod.yml build --no-cache php nginx
        docker compose -f docker-compose.prod.yml down --remove-orphans
        docker compose -f docker-compose.prod.yml up -d --force-recreate
        docker compose -f docker-compose.prod.yml exec -T php sh -c 'rm -rf /var/www/app/var/cache/prod/* /var/www/app/var/cache/test/*'
        docker compose -f docker-compose.prod.yml exec -T php sh -c 'export APP_ENV=prod APP_DEBUG=0; php bin/console cache:clear --no-debug; php bin/console cache:warmup --no-debug; php bin/console asset-map:compile; chown -R www-data:www-data /var/www/app/var/ /var/www/app/config/pgp/'
        docker compose -f docker-compose.prod.yml restart php nginx
    - shell: /bin/bash
    - cwd: /opt/lockpost

test_lockpost:
  cmd.run:
    - name: |
        cd /opt/lockpost
        docker compose -f docker-compose.prod.yml exec -T php sh -c 'export APP_ENV=test APP_DEBUG=1; php bin/phpunit tests/BootstrapTest.php --no-coverage'
        curl -sI http://127.0.0.1:80/ | head -5
        curl -sI http://127.0.0.1:80/verify | head -5
        curl -sI http://127.0.0.1:80/server-key | head -5
    - shell: /bin/bash
    - cwd: /opt/lockpost
    - require:
      - cmd: deploy_lockpost

verify_deployment:
  cmd.run:
    - name: |
        echo "=== Deployment Verification ==="
        echo "Container status:"
        docker compose -f /opt/lockpost/docker-compose.prod.yml ps
        echo ""
        echo "HTTP endpoints:"
        echo -n "Homepage: " && curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/
        echo ""
        echo -n "Verify:   " && curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/verify
        echo ""
        echo -n "Server Key: " && curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:80/server-key
        echo ""
        echo "=== Deployment Complete ==="
    - shell: /bin/bash
    - cwd: /opt/lockpost
    - require:
      - cmd: test_lockpost
