# Running Engage locally

Quick reference for starting, stopping, and troubleshooting the local Docker stack.
All commands are run from the repo root (`engage-fork/`).

## Open the app

Once the stack is running, just open it in your browser:

- **App:** http://localhost:8000  (redirects to the login page — that's normal)
- **Celery Flower (task dashboard):** http://localhost:5555

## Start / stop

Start everything (builds images the first time, then runs in the background):

```bash
docker compose up -d
```

Stop everything:

```bash
docker compose down
```

Check what's running:

```bash
docker compose ps
```

## The stack

`docker compose` brings up 6 containers:

| Service         | Container                | Port (host) | What it does                        |
| --------------- | ------------------------ | ----------- | ----------------------------------- |
| `app`           | calliope-app             | 8000        | Django web app (the UI)             |
| `postgres`      | calliope-postgres        | 5433        | Database                            |
| `redis`         | calliope-redis           | 6379        | Message broker / cache              |
| `short_worker`  | calliope-short-worker    | —           | Celery worker (fast tasks)          |
| `long_worker`   | calliope-long-worker     | —           | Celery worker (long-running tasks)  |
| `celery_flower` | calliope-celery-flower   | 5555        | Celery monitoring dashboard         |

The `app` container runs `wait-for-postgres` and database migrations before it
starts serving, so give it ~30 seconds after `up` before the page loads.

## Logs

Follow the app logs (Ctrl+C to stop watching — this does **not** stop the app):

```bash
docker compose logs -f app
```

Logs for everything:

```bash
docker compose logs -f
```

## Docker engine (OrbStack)

This machine uses **OrbStack** to provide Docker. If `docker compose` commands
fail with a "cannot connect to the Docker daemon" error, OrbStack isn't running:

```bash
orb start
```

Check its status with `orb status`.

## Troubleshooting: disk full

OrbStack will shut down if the Mac's disk fills up, which takes the whole stack
down with it. Check free space:

```bash
df -h /System/Volumes/Data
```

Reclaim Docker space safely (removes unused build cache and dangling images —
does not touch running containers):

```bash
docker system prune -f
```
