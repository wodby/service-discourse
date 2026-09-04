# syntax=docker/dockerfile:1

ARG WODBY_BASE_IMAGE
FROM ${WODBY_BASE_IMAGE}

ARG COPY_FROM=.
ARG DISCOURSE_GIT_VERSION=unknown

ENV RAILS_ENV=production \
    UNICORN_WORKERS=3 \
    UNICORN_SIDEKIQS=1 \
    RUBY_GC_HEAP_GROWTH_MAX_SLOTS=40000 \
    RUBY_GC_HEAP_INIT_SLOTS=400000 \
    RUBY_GC_HEAP_OLDOBJECT_LIMIT_FACTOR=1.5 \
    RUBY_GC_HEAP_FREE_SLOTS_MIN_RATIO=0.11 \
    RUBY_GC_HEAP_FREE_SLOTS_GOAL_RATIO=0.22 \
    MIGRATE_ON_BOOT=1 \
    PRECOMPILE_ON_BOOT=1

USER root

# Keep the dependency layers supplied by the official web-only base while
# replacing its checkout with the source selected for this Wodby build.
COPY --chown=discourse:discourse ${COPY_FROM} /tmp/discourse-source

RUN set -e; \
    find /var/www/discourse -mindepth 1 -maxdepth 1 \
      ! -name vendor \
      ! -name node_modules \
      -exec rm -rf {} +; \
    cp -a /tmp/discourse-source/. /var/www/discourse/; \
    rm -rf /tmp/discourse-source /var/www/discourse/.git; \
    chown -R discourse:discourse /var/www/discourse; \
    cd /var/www/discourse; \
    sudo -H -E -u discourse git init -q; \
    sudo -H -E -u discourse git add frontend package.json pnpm-lock.yaml; \
    discourse_version="$(sudo -H -E -u discourse /usr/local/bin/ruby -Ilib -r version -e 'print Discourse::VERSION::STRING')"; \
    printf '{"git_version":"%s","git_branch":"build","full_version":"v%s"}\n' \
      "${DISCOURSE_GIT_VERSION}" "${discourse_version}" \
      > config/git-utils-overrides.json; \
    chown discourse:discourse config/git-utils-overrides.json; \
    sudo -H -E -u discourse bundle config set --local deployment true; \
    sudo -H -E -u discourse bundle config set --local path ./vendor/bundle; \
    sudo -H -E -u discourse bundle config set --local without 'test development'; \
    sudo -H -E -u discourse bundle install --jobs "$(nproc --ignore=1)" --retry 3; \
    sudo -H -E -u discourse bundle clean; \
    sudo -H -E -u discourse /bin/bash -c 'CI=1 pnpm install --frozen-lockfile && pnpm prune'; \
    sudo -H -E -u discourse env DISCOURSE_DOWNLOAD_PRE_BUILT_ASSETS=0 bundle exec rake assets:precompile:build; \
    rm -rf .git

RUN set -e; \
    cd /var/www/discourse; \
    mkdir -p tmp/pids tmp/sockets log public \
      /shared/log/rails /shared/uploads /shared/backups \
      /shared/tmp/backups /shared/tmp/restores; \
    touch /shared/log/rails/production.log \
      /shared/log/rails/production_errors.log \
      /shared/log/rails/unicorn.stdout.log \
      /shared/log/rails/unicorn.stderr.log \
      /shared/log/rails/sidekiq.log; \
    rm -rf public/uploads public/backups tmp/backups tmp/restores; \
    ln -s /shared/uploads public/uploads; \
    ln -s /shared/backups public/backups; \
    ln -s /shared/tmp/backups tmp/backups; \
    ln -s /shared/tmp/restores tmp/restores; \
    for logfile in production production_errors unicorn.stdout unicorn.stderr sidekiq; do \
      rm -f "log/${logfile}.log"; \
      ln -s "/shared/log/rails/${logfile}.log" "log/${logfile}.log"; \
    done; \
    chown -R discourse:www-data tmp /shared; \
    cp config/nginx.sample.conf /etc/nginx/conf.d/discourse.conf; \
    rm -f /etc/nginx/sites-enabled/default; \
    mkdir -p /var/nginx/cache \
      /etc/nginx/conf.d/outlets/before-server \
      /etc/nginx/conf.d/outlets/server \
      /etc/nginx/conf.d/outlets/discourse; \
    touch /etc/nginx/conf.d/outlets/before-server/20-redirect-http-to-https.conf \
      /etc/nginx/conf.d/outlets/before-server/30-ratelimited.conf \
      /etc/nginx/conf.d/outlets/server/20-https.conf \
      /etc/nginx/conf.d/outlets/server/30-offline-page.conf \
      /etc/nginx/conf.d/outlets/discourse/20-https.conf \
      /etc/nginx/conf.d/outlets/discourse/30-ratelimited.conf; \
    grep -q 'outlets/before-server' /etc/nginx/conf.d/discourse.conf; \
    grep -q 'outlets/server' /etc/nginx/conf.d/discourse.conf; \
    grep -q 'outlets/discourse' /etc/nginx/conf.d/discourse.conf; \
    sed -i 's#listen 80;##g' /etc/nginx/conf.d/discourse.conf; \
    printf 'listen 80;\nlisten [::]:80;\n' > /etc/nginx/conf.d/outlets/server/10-http.conf; \
    sed -i 's/pid \/run\/nginx.pid;/daemon off;/' /etc/nginx/nginx.conf; \
    sed -i -E 's/client_max_body_size.+$/client_max_body_size 35m;/' /etc/nginx/conf.d/discourse.conf

RUN <<'EOF'
set -eu

mkdir -p /etc/runit/1.d /etc/runit/3.d /etc/service/nginx /etc/service/unicorn /usr/local/bin

cat > /etc/runit/1.d/10-copy-env <<'SCRIPT'
#!/usr/bin/env bash
set -e
env > /root/boot_env
conf=/var/www/discourse/config/discourse.conf
/usr/local/bin/ruby -e 'ENV.sort.each { |key, value| puts "#{$1.downcase} = #{value.dump}" if key =~ /^DISCOURSE_(.*)/ }' \
  | install -m 600 -o discourse -g discourse /dev/stdin "${conf}"
SCRIPT

cat > /etc/runit/1.d/20-prepare-shared <<'SCRIPT'
#!/usr/bin/env bash
set -e
mkdir -p \
  /shared/log/rails \
  /shared/uploads \
  /shared/backups \
  /shared/tmp/backups \
  /shared/tmp/restores \
  /shared/state/logrotate \
  /shared/state/anacron-spool
touch \
  /shared/log/rails/production.log \
  /shared/log/rails/production_errors.log \
  /shared/log/rails/unicorn.stdout.log \
  /shared/log/rails/unicorn.stderr.log \
  /shared/log/rails/sidekiq.log
find /shared ! \( -user discourse -group www-data \) -exec chown discourse:www-data {} +
rm -rf /var/lib/logrotate /var/spool/anacron
ln -s /shared/state/logrotate /var/lib/logrotate
ln -s /shared/state/anacron-spool /var/spool/anacron
rm -rf /shared/tmp/backups /shared/tmp/restores
mkdir -p /shared/tmp/backups /shared/tmp/restores
chown -R discourse:www-data /shared/tmp
rm -f /var/www/discourse/tmp/pids/*.pid
SCRIPT

cat > /etc/runit/1.d/30-wait-for-dependencies <<'SCRIPT'
#!/usr/bin/env bash
set -e
wait_for_tcp "${DISCOURSE_DB_HOST}" "${DISCOURSE_DB_PORT:-5432}" 120 2
wait_for_tcp "${DISCOURSE_REDIS_HOST}" "${DISCOURSE_REDIS_PORT:-6379}" 120 2
SCRIPT

cat > /etc/runit/3.d/10-nginx <<'SCRIPT'
#!/usr/bin/env bash
sv stop nginx || true
SCRIPT

cat > /etc/runit/3.d/20-unicorn <<'SCRIPT'
#!/usr/bin/env bash
sv stop unicorn || true
SCRIPT

cat > /etc/service/nginx/run <<'SCRIPT'
#!/usr/bin/env sh
exec 2>&1
exec /usr/sbin/nginx
SCRIPT

cat > /etc/service/unicorn/run <<'SCRIPT'
#!/usr/bin/env bash
set -e
exec 2>&1
cd /var/www/discourse
chown -R discourse:www-data /shared/log/rails
if [[ "${MIGRATE_ON_BOOT:-1}" == "1" ]]; then
  sudo -H -E -u discourse bundle exec rake db:migrate
fi
if [[ "${PRECOMPILE_ON_BOOT:-1}" == "1" ]]; then
  sudo -H -E -u discourse env SKIP_EMBER_CLI_COMPILE=1 bundle exec rake themes:update assets:precompile
fi
export HOME=/home/discourse
export USER=discourse
export LD_PRELOAD="${RUBY_ALLOCATOR}"
exec thpoff chpst -u discourse:www-data -U discourse:www-data \
  bundle exec config/unicorn_launcher -E production -c config/unicorn.conf.rb
SCRIPT

cat > /usr/local/bin/discourse <<'SCRIPT'
#!/usr/bin/env bash
set -e
cd /var/www/discourse
exec sudo -H -E -u discourse env RAILS_ENV=production bundle exec script/discourse "$@"
SCRIPT

cat > /usr/local/bin/health <<'SCRIPT'
#!/usr/bin/env bash
set -e
host="${1:-127.0.0.1}"
port="${2:-80}"
max_try="${3:-1}"
wait_seconds="${4:-1}"
delay_seconds="${5:-0}"
sleep "${delay_seconds}"
for ((attempt = 1; attempt <= max_try; attempt++)); do
  if curl --fail --silent --show-error --max-time 5 "http://${host}:${port}/srv/status" >/dev/null; then
    exit 0
  fi
  sleep "${wait_seconds}"
done
exit 1
SCRIPT

cat > /usr/local/bin/wait_for_tcp <<'SCRIPT'
#!/usr/bin/env bash
set -e
host="${1:?host is required}"
port="${2:?port is required}"
max_try="${3:-1}"
wait_seconds="${4:-1}"
for ((attempt = 1; attempt <= max_try; attempt++)); do
  if timeout 3 bash -c "</dev/tcp/${host}/${port}" 2>/dev/null; then
    exit 0
  fi
  sleep "${wait_seconds}"
done
echo "Timed out waiting for ${host}:${port}" >&2
exit 1
SCRIPT

cat > /usr/local/bin/actions.mk <<'MAKEFILE'
.PHONY: backup check-live check-ready

host ?= 127.0.0.1
port ?= 80
max_try ?= 1
wait_seconds ?= 1
delay_seconds ?= 0

check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Required parameter is missing: $1$(if $2, ($2))))

default: check-ready

check-ready:
	health $(host) $(port) $(max_try) $(wait_seconds) $(delay_seconds)

check-live:
	health $(host) $(port) $(max_try) $(wait_seconds) $(delay_seconds)

backup:
	$(call check_defined, filepath)
	rm -f "$(filepath)"
	@workdir="$$(mktemp -d "$(filepath).tmp.XXXXXX")"; \
		trap 'rm -rf "$${workdir}"' EXIT; \
		chown discourse:www-data "$${workdir}"; \
		discourse backup "$${workdir}/$$(basename "$(filepath)")"; \
		archive="$$(find "$${workdir}" -maxdepth 1 -type f -name '*.tar.gz' -print -quit)"; \
		test -n "$${archive}"; \
		mv "$${archive}" "$(filepath)"; \
		test -f "$(filepath)"
MAKEFILE

cat > /etc/logrotate.d/discourse-rails <<'CONFIG'
/shared/log/rails/*.log {
  daily
  rotate 7
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
}
CONFIG

chmod +x \
  /etc/runit/1.d/10-copy-env \
  /etc/runit/1.d/20-prepare-shared \
  /etc/runit/1.d/30-wait-for-dependencies \
  /etc/runit/3.d/10-nginx \
  /etc/runit/3.d/20-unicorn \
  /etc/service/nginx/run \
  /etc/service/unicorn/run \
  /usr/local/bin/discourse \
  /usr/local/bin/health \
  /usr/local/bin/wait_for_tcp
EOF

WORKDIR /var/www/discourse

EXPOSE 80
VOLUME /shared

ENTRYPOINT ["/sbin/boot"]
