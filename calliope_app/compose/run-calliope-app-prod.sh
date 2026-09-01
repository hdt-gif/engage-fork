#!/usr/bin/env bash
#
# Production entrypoint for the web container.
#
# Differs from run-calliope-app.sh in three ways: static files are collected
# (DEBUG=False stops Django serving them itself), migrations run without
# prompting, and gunicorn serves the app instead of the development server.
#
set -euo pipefail

python3 manage.py migrate --noinput

# Seeds reference data only into an empty database -- see the script for why
# loading these fixtures unconditionally is dangerous.
compose/seed-reference-data.sh

python3 manage.py collectstatic --noinput

# Model solves run in the Celery workers, so the web workers only handle
# ordinary requests. Raise GUNICORN_TIMEOUT if a page ever legitimately
# needs longer than two minutes.
exec gunicorn calliope_app.wsgi:application \
      --bind 0.0.0.0:8000 \
      --workers "${GUNICORN_WORKERS:-3}" \
      --timeout "${GUNICORN_TIMEOUT:-120}" \
      --access-logfile - \
      --error-logfile -
