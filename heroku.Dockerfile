# =============================================================================
# Stage 1a - Install frontend dependencies.
#
# Dependencies are installed with ONLY package.json/yarn.lock present (no app
# source). The package's `postinstall` runs `nuxt prepare`, which fails if the
# full source tree is present before node_modules are fully resolved, so we keep
# this step source-free (mirroring the upstream web-frontend Dockerfile).
# NODE_ENV is intentionally left unset so devDependencies (the build toolchain)
# are installed.
# =============================================================================
ARG NODE_BASE_IMAGE="node:24.14.0-trixie-slim"
# hadolint ignore=DL3006
FROM ${NODE_BASE_IMAGE} AS frontend-deps

ENV NUXT_TELEMETRY_DISABLED=1 \
    YARN_CACHE_FOLDER=/tmp/.yarn-cache

WORKDIR /baserow/web-frontend
COPY web-frontend/package.json /baserow/web-frontend/package.json
COPY web-frontend/yarn.lock /baserow/web-frontend/yarn.lock
RUN yarn install --pure-lockfile --cache-folder "$YARN_CACHE_FOLDER"


# =============================================================================
# Stage 1b - Rebuild the web-frontend (Nuxt) bundle from source.
#
# The published base image used in stage 2 ships a pre-compiled web-frontend, so
# local changes under web-frontend/, premium/web-frontend/ or
# enterprise/web-frontend/ are only picked up if we recompile the bundle here and
# overlay it. The repo VERSION matches the pinned base image version, so the
# rebuilt frontend stays API-compatible with the backend in the base image.
# =============================================================================
# hadolint ignore=DL3006
FROM ${NODE_BASE_IMAGE} AS frontend-builder

ENV NUXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production \
    YARN_CACHE_FOLDER=/tmp/.yarn-cache

RUN mkdir -p /baserow/web-frontend /baserow/premium/web-frontend /baserow/enterprise/web-frontend

# Copy source (node_modules/.output/.nuxt are excluded via .dockerignore).
COPY web-frontend /baserow/web-frontend/
COPY premium/web-frontend /baserow/premium/web-frontend/
COPY enterprise/web-frontend /baserow/enterprise/web-frontend/

# Reuse the dependencies installed in the deps stage.
COPY --from=frontend-deps /baserow/web-frontend/node_modules /baserow/web-frontend/node_modules

# premium and enterprise are sibling node packages that resolve their deps
# through the main web-frontend node_modules.
RUN ln -s /baserow/web-frontend/node_modules/ /baserow/premium/web-frontend/node_modules && \
    ln -s /baserow/web-frontend/node_modules/ /baserow/enterprise/web-frontend/node_modules

WORKDIR /baserow/web-frontend
RUN yarn run build


# =============================================================================
# Stage 2 - Heroku runtime image, based on the published all-in-one image with
# the rebuilt frontend bundle and the modified backend source overlaid on top.
# =============================================================================
ARG FROM_IMAGE=baserow/baserow:2.2.2
# This is pinned as version pinning is done by the CI setting FROM_IMAGE.
# hadolint ignore=DL3006
FROM $FROM_IMAGE AS image_base

RUN apt-get remove -y "postgresql-$POSTGRES_VERSION" redis-server

ENV DATA_DIR=/baserow/data
# We have to build the data dir in the docker image as Caddy does not allow it in their
# runtime filesystem. We chown to their www-data user's uid and gid at the end.
RUN mkdir -p "$DATA_DIR" && \
    chown -R 9999:9999 "$DATA_DIR"

COPY deploy/heroku/heroku_env.sh /baserow/supervisor/env/heroku_env.sh

# Overlay the freshly built Nuxt bundle so the premium/enterprise frontend
# changes (unlocked features + Licenses in the main sidebar) are actually served.
# The all-in-one runtime serves the web-frontend from this .output directory via
# `node --import ./env-remap.mjs .output/server/index.mjs`.
COPY --from=frontend-builder --chown=9999:9999 /baserow/web-frontend/.output /baserow/web-frontend/.output

# Overlay the modified premium backend source (license feature unlock). PYTHONPATH
# already includes /baserow/premium/backend/src, so replacing this module is enough.
COPY --chown=9999:9999 premium/backend/src/baserow_premium/license/plugin.py /baserow/premium/backend/src/baserow_premium/license/plugin.py

# IMPORTANT: do not remove these. Heroku wraps the release/run commands in a /bin/sh
# log-streaming script and passes it as arguments to the image. The base baserow image's
# ENTRYPOINT is ./baserow.sh, which would then receive that wrapper as its first argument
# and merely print its usage text (release fails with exit 1). Clearing ENTRYPOINT and CMD
# makes Heroku's release/run commands execute as a plain shell command.
ENTRYPOINT []
CMD []
