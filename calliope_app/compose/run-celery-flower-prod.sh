#!/usr/bin/env bash
#
# Production entrypoint for the Flower dashboard.
#
# Flower exposes queue contents and lets you revoke tasks, so it must not be
# reachable without credentials. Set FLOWER_BASIC_AUTH as user:password.
#
set -euo pipefail

if [ -z "${FLOWER_BASIC_AUTH:-}" ]; then
  echo "FLOWER_BASIC_AUTH is not set. Refusing to start an unauthenticated dashboard." >&2
  exit 1
fi

exec celery -A calliope_app flower \
      --port=5555 \
      --basic_auth="${FLOWER_BASIC_AUTH}"
