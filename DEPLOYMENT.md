# Engage — HSEO Deployment

How the HSEO instance of Engage is hosted, how to reach it, and how to operate
it. For local development setup see [RUNNING.md](RUNNING.md).

**Status:** deployed and working. Not yet open to HSEO staff — see
[What's not done yet](#whats-not-done-yet).

---

## Quick reference

| | |
| --- | --- |
| App | http://3.151.238.7:8000 |
| SSH | `ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7` |
| Instance | `i-0c251de2dc1a35767` — t3.large, 60 GB, Ubuntu 26.04 |
| Region | us-east-2 (Ohio) |
| Security group | `sg-0619d031ef5e8a521` |
| Elastic IP | `eipalloc-0452b74f4367843db` → 3.151.238.7 |

Every AWS CLI command needs `--region us-east-2`, or it silently looks
elsewhere and reports nothing.

---

## Networking architecture

One EC2 instance runs the whole stack under Docker Compose. Postgres is a
container on that box rather than RDS, so nothing leaves the instance.

```
                    the internet
                         │
                         ▼
        ┌────────────────────────────────────┐
        │  Elastic IP  3.151.238.7           │
        │  permanent; survives stop/start    │
        └────────────────┬───────────────────┘
                         ▼
        ┌────────────────────────────────────┐
        │  SECURITY GROUP sg-0619d031ef5e8a521│
        │                                    │
        │   22   → allowlisted IPs only      │
        │   8000 → allowlisted IPs only      │
        │   everything else → dropped        │
        └────────────────┬───────────────────┘
                         ▼
  ┌──────────────────────────────────────────────────┐
  │  EC2  i-0c251de2dc1a35767   Ubuntu 26.04         │
  │                                                  │
  │  host loopback 127.0.0.1:5432 ──► postgres       │
  │    (reachable only through an SSH tunnel)        │
  │                                                  │
  │  ┌────────────────────────────────────────────┐  │
  │  │  Docker network  (engage-fork_default)     │  │
  │  │                                            │  │
  │  │   :8000  calliope-app        gunicorn      │  │
  │  │          calliope-postgres   database      │  │
  │  │          calliope-redis      job queue     │  │
  │  │          calliope-short-worker             │  │
  │  │          calliope-long-worker  solver      │  │
  │  │   :5555  calliope-celery-flower (loopback) │  │
  │  │                                            │  │
  │  │   containers reach each other BY NAME,     │  │
  │  │   e.g. POSTGRES_HOST=calliope-postgres     │  │
  │  └────────────────────────────────────────────┘  │
  │                                                  │
  │  volumes on the 60 GB root disk:                 │
  │    ./postgres/data  → database files             │
  │    ./data           → model inputs, timeseries,  │
  │                       run outputs                │
  └──────────────────────────────────────────────────┘
```

### What is exposed, and what is not

| Port | Bound to | Reachable by |
| --- | --- | --- |
| 22 | public interface | allowlisted IPs only |
| 8000 | public interface | allowlisted IPs only |
| 5432 (Postgres) | `127.0.0.1` on the host | SSH tunnel only |
| 5555 (Flower) | `127.0.0.1` on the host | SSH tunnel only, plus basic auth |
| 6379 (Redis) | Docker network only | nothing outside the containers |

Access is currently controlled by **IP allowlist**, not by the application.
Someone not on the list gets a TCP timeout — they never reach a login page.

To add an address:

```bash
aws ec2 authorize-security-group-ingress --region us-east-2 \
  --group-id sg-0619d031ef5e8a521 --ip-permissions \
  'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=X.X.X.X/32,Description="who"}]' \
  'IpProtocol=tcp,FromPort=8000,ToPort=8000,IpRanges=[{CidrIp=X.X.X.X/32,Description="who"}]'
```

`curl -s https://checkip.amazonaws.com` reports your current address. Home and
office addresses differ, and home addresses change — a sudden timeout while AWS
reports the instance `running` almost always means your IP moved.

### Planned: domain and TLS

Traffic is currently plain HTTP. The intended end state:

```
  browser ──https──► ALB (ACM certificate)  ──http──► instance :8000
                     or Caddy on the instance itself
```

Blocked on a domain name — certificates are issued for names, not IP
addresses. Once one exists and points at 3.151.238.7:

1. Issue a certificate (ACM if using an ALB, Let's Encrypt if terminating on the box)
2. Open 443, close public 8000
3. Add the hostname to `DJANGO_ALLOWED_HOSTS`
4. **Set `DJANGO_SESSION_COOKIE_SECURE`, `DJANGO_CSRF_COOKIE_SECURE` and
   `DJANGO_SECURE_SSL_REDIRECT` back to `True`** — they are `False` today
   only because secure cookies are never transmitted over plain HTTP, which
   makes login impossible
5. Set `DJANGO_CSRF_TRUSTED_ORIGINS` to the `https://` origin

`settings/prod.py` already sets `SECURE_PROXY_SSL_HEADER`, so Django reads
`X-Forwarded-Proto` correctly behind a load balancer.

---

## SSH

```bash
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7
```

The key is not recoverable from AWS. Back it up somewhere safe; losing it means
losing access to the instance.

If SSH hangs, check whether your IP is still allowlisted before assuming the
instance is down.

## Port-forwarding Postgres

The database is bound to the host's loopback, so it is reachable over an SSH
tunnel and from nowhere else.

```bash
# leave this running in a terminal
ssh -i ~/.ssh/engage-hseo.pem -L 5433:localhost:5432 -N ubuntu@3.151.238.7
```

Then point any client at `localhost:5433`:

```bash
psql -h localhost -p 5433 -U postgres -d postgres
```

Credentials are in `.envs/.prod` on the instance:

```bash
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 \
  'grep POSTGRES ~/engage-fork/.envs/.prod'
```

Add `-f` to background the tunnel; close it later with
`pkill -f "5433:localhost:5432"`.

### Flower, the same way

```bash
ssh -i ~/.ssh/engage-hseo.pem -L 5555:localhost:5555 -N ubuntu@3.151.238.7
```

Then open http://localhost:5555 and authenticate with `FLOWER_BASIC_AUTH` from
`.envs/.prod`. Flower shows the Celery queues and running model solves.

---

## Operating it

All commands run from `~/engage-fork` on the instance.

```bash
docker compose -f docker-compose.prod.yml ps        # what is running
docker compose -f docker-compose.prod.yml logs -f app
docker compose -f docker-compose.prod.yml restart app
```

### Deploying a code change

The production compose file does **not** mount the source tree — the code lives
inside the image. `git pull` alone changes nothing:

```bash
git pull
docker compose -f docker-compose.prod.yml up -d --build
```

Skip the rebuild and the containers keep running the previous code. (Local
development does bind-mount the source, which is why edits appear immediately
there and not here.)

A change to `.envs/.prod` alone needs no rebuild:

```bash
docker compose -f docker-compose.prod.yml up -d --force-recreate
```

### Starting and stopping

Roughly $60/month running, $8/month stopped. Stop it when idle.

```bash
aws ec2 stop-instances  --region us-east-2 --instance-ids i-0c251de2dc1a35767
aws ec2 start-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767
```

The Elastic IP means the address survives a restart, so nothing needs
reconfiguring afterwards.

### Creating a user

Registration emails require SES, which is not configured. Create accounts
directly:

```bash
docker exec -it calliope-app python3 manage.py createsuperuser
```

---

## Verification performed

Sanity-checked with the sample dataset bundled in `api/fixtures/` — the
national-scale example model, five regions, six technologies, hourly timeseries
for 2005.

| Check | Result |
| --- | --- |
| gunicorn serving (not the dev server) | `Server: gunicorn` |
| `DEBUG` disabled | `False` |
| Static files served by WhiteNoise | HTTP 200, `text/css` |
| Celery workers connected to the broker | both `ready` |
| Postgres requires a password | wrong password rejected |
| Database and broker ports closed | unreachable from outside |
| Reference data seeded | 7 abstract techs, 154 parameters, 12 template types |
| **Model build** | BUILT |
| **Model solve** | SUCCESS in 36s, 55 output files |

The solve produced real optimisation results — installed capacities and system
costs across five regions — matching a local run of the same model.

---

## What's not done yet

| | Why it matters |
| --- | --- |
| **No TLS** | Passwords cross the internet in plaintext. Blocked on a domain name. |
| **No domain** | Raw IP address. Needed before a certificate can be issued. |
| **No backups** | Nothing is backed up. HSEO is starting from scratch, so once model-building begins this instance is the only copy of that work. |
| **IP allowlist only** | HSEO staff cannot reach it. Widening access before TLS would mean staff sending passwords over plain HTTP. |
| **Personal Mapbox token** | Maps run on a token belonging to a personal account. HSEO needs its own. |
| **Instance size is a guess** | `t3.large` chosen without knowing real model sizes. Resizing is a stop, change type, start. |
| **No infrastructure as code** | The instance was created by hand. Recreating it means following this document, not running a script. |

Backups are the highest-stakes item. Suggested minimum: a nightly `pg_dump` to
S3, scheduled snapshots of the volume holding `./data`, and — critically — a
restore that has actually been tested.

---

## Upstream fixes made during deployment

Seven bugs in the inherited codebase, all fixed and committed. Engage could not
run under `settings.prod` without them.

1. **gunicorn** — referenced by `settings/prod.py` but absent from `requirements.txt`
2. **`/opt/python/log`** — the production logging handler writes there; nothing created it, so Django failed at startup
3. **Static files** — with `DEBUG=False` Django stops serving `STATIC_ROOT`; WhiteNoise now does
4. **Broker TLS** — `CELERY_BROKER_USE_SSL` was hardcoded on, so workers could not reach a plain Redis container. Now env-configurable, still defaulting to on
5. **Secure cookies** — `SESSION_COOKIE_SECURE` / `CSRF_COOKIE_SECURE` hardcoded on made login impossible without HTTPS. Now env-configurable, still defaulting to on
6. **Fixture ordering** — `loaddata` ran before `migrate` and failed silently, so reference data never loaded on a fresh install. Seeding now runs through `compose/seed-reference-data.sh`, which only populates an empty database
7. **Race condition in `build_model`** — `run_options` was saved *after* dispatching the Celery task, so a worker that started first read `NULL` and crashed. Timing-dependent: passed on a 4-core laptop, failed consistently on this 2-core instance

Items 1–3 and 6–7 affect anyone deploying Engage, not just HSEO.
