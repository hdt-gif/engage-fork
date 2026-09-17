# Running Engage on your own machine

Starting, stopping and troubleshooting the **local** Docker stack — the copy on
your laptop, for development.

> **This is not the live site.** Nothing in this document affects the HSEO
> instance. `docker compose up -d` here talks to Docker on *your* machine; the
> server has its own Docker, its own repo and its own database. To operate the
> live site, see [DEPLOYMENT.md → Running it on the instance](DEPLOYMENT.md#running-it-on-the-instance).

| | Your own machine (this doc) | The instance ([DEPLOYMENT.md](DEPLOYMENT.md)) |
| --- | --- | --- |
| Reached at | http://localhost:8000 | http://3.151.238.7:8000 |
| Compose file | `docker-compose.yml` (the default) | `docker-compose.prod.yml`, passed with `-f` |
| Source code | bind-mounted — edits appear immediately | baked into the image — needs `--build` |
| Database | yours alone | shared, and the one that matters |

All commands below are run **on your own machine**, from the repo root.

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

No `-f` flag here — Compose picks up `docker-compose.yml` on its own. That file
is the *development* stack; `docker-compose.prod.yml` is a standalone production
file and is only ever used on the instance.

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

The container names are the same as on the instance, which is convenient but
also a trap: `docker exec calliope-app ...` hits whichever machine you typed it
on. Check your shell prompt if in doubt.

The `app` container runs `wait-for-postgres` and database migrations before it
starts serving, so give it ~30 seconds after `up` before the page loads.

## Accounts

Registration emails aren't configured locally either, so create accounts by
hand. Engage uses the email address as the username:

```bash
docker exec -it calliope-app python3 manage.py createsuperuser
```

To see which accounts exist in your local database:

```bash
docker exec calliope-postgres psql -U postgres -d postgres \
  -c "select id, username, email, is_superuser, date_joined, last_login
        from auth_user order by date_joined;"
```

These are yours alone — an account here does not exist on the live site, and
vice versa.

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

`docker context ls` confirms which daemon you're pointed at — it should be
`orbstack`, on a local socket. If you ever add a remote context for the
instance, remember that it changes what every subsequent `docker compose`
command touches.

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
