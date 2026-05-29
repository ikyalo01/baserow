#!/bin/bash

set -euo pipefail

export BASEROW_PUBLIC_URL=${BASEROW_PUBLIC_URL:-https://$HEROKU_APP_NAME.herokuapp.com}
export BASEROW_CADDY_ADDRESSES=":$PORT"
# Heroku injects $PORT and Caddy binds it as the public entrypoint. Nuxt's Nitro
# server, however, also auto-binds to $PORT when it is set, which collides with Caddy
# (EADDRINUSE) and crashes the web-frontend. Pin the frontend to the internal port
# 3000 that Caddy proxies to. NITRO_PORT takes precedence over PORT in Nitro.
export NITRO_PORT=3000
export REDIS_URL=${REDIS_TLS_URL:-${REDIS_URL:-}}
# Heroku's Redis / Key-Value Store hands out a rediss:// URL backed by a self-signed
# certificate. Celery (broker, result backend and the redbeat scheduler) refuses to
# start on a rediss:// URL unless `ssl_cert_reqs` is present, so ensure it is set to
# `none` (the cert cannot be verified). Without this the web dyno boots and then
# crashes when beat/celery come up.
if [[ "${REDIS_URL:-}" == rediss://* && "${REDIS_URL}" != *ssl_cert_reqs=* ]]; then
  if [[ "${REDIS_URL}" == *\?* ]]; then
    export REDIS_URL="${REDIS_URL}&ssl_cert_reqs=none"
  else
    export REDIS_URL="${REDIS_URL}?ssl_cert_reqs=none"
  fi
fi
export DJANGO_SETTINGS_MODULE='baserow.config.settings.heroku'
export BASEROW_RUN_MINIMAL=yes
export DISABLE_EMBEDDED_PSQL=yes
export DISABLE_EMBEDDED_REDIS=yes
export SYNC_TEMPLATES_ON_STARTUP="${SYNC_TEMPLATES_ON_STARTUP:-false}"
export BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION=${BASEROW_TRIGGER_SYNC_TEMPLATES_AFTER_MIGRATION:-$SYNC_TEMPLATES_ON_STARTUP}
export MIGRATE_ON_STARTUP="${MIGRATE_ON_STARTUP:-false}"
# Heroku does not support mounting volumes!
export DISABLE_VOLUME_CHECK=yes

export BASEROW_AMOUNT_OF_WORKERS=${BASEROW_AMOUNT_OF_WORKERS:-1}
export BASEROW_AMOUNT_OF_GUNICORN_WORKERS=${BASEROW_AMOUNT_OF_GUNICORN_WORKERS:-$BASEROW_AMOUNT_OF_WORKERS}

# Heroku dynos report the underlying host's full CPU count, so glibc's malloc creates
# a large number of per-thread arenas (up to 8 x nCPU), each of which can grow to tens
# of MB. Across the multi-threaded backend (gunicorn/uvicorn), Celery worker and beat
# processes this bloats resident memory by hundreds of MB and triggers Heroku's R14
# "Memory quota exceeded", which in turn destabilises the long-lived WebSocket used for
# real-time updates. Capping the arenas keeps the all-in-one stack within a 1GB dyno.
export MALLOC_ARENA_MAX=${MALLOC_ARENA_MAX:-2}

# Disable auto https redirect because otherwise it will make Caddy bind on port 80.
# This is not allowed by Heroku, and will prevent it from starting.
export BASEROW_CADDY_GLOBAL_CONF="auto_https disable_redirects
http_port $PORT"

# Only configure SMTP email when the Mailgun add-on has actually been provisioned.
# If the add-on failed to attach (e.g. an unverified Heroku account), these vars are
# unset and we must not let `set -u` abort the whole release/start with email broken.
if [ -n "${MAILGUN_DOMAIN:-}" ] && [ -n "${MAILGUN_SMTP_SERVER:-}" ]; then
  export EMAIL_SMTP="true"
  export EMAIL_SMTP_USE_TLS=""
  export FROM_EMAIL="no-reply@$MAILGUN_DOMAIN"

  export EMAIL_SMTP_HOST=$MAILGUN_SMTP_SERVER
  export EMAIL_SMTP_PORT=$MAILGUN_SMTP_PORT
  export EMAIL_SMTP_USER=$MAILGUN_SMTP_LOGIN
  export EMAIL_SMTP_PASSWORD=$MAILGUN_SMTP_PASSWORD
fi
# Heroku generates a random user who runs this container, set DOCKER_USER to that user
# so we can setup the DATA_DIR.
DOCKER_USER=$(whoami)
export DOCKER_USER

# We must run the caddy user as the docker user to prevent supervisord errors
export BASEROW_CADDY_USER="${BASEROW_CADDY_USER:-$DOCKER_USER}"
