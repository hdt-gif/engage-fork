# Engage — HSEO Deployment

How the HSEO instance of Engage is hosted, how to reach it, and how to operate
it.

**Status:** deployed and working. Not yet open to HSEO staff — see
[What's not done yet](#whats-not-done-yet).

| I want to… | Go to |
| --- | --- |
| **Daily start / stop / connect routine** | [Every day](#every-day) |
| **Just open the app and log in** | [Opening the app](#opening-the-app) |
| Start, stop, restart or deploy the live site | [Running it on the instance](#running-it-on-the-instance) |
| Check whether it's working | [Checking it yourself](#checking-it-yourself) |
| Run Engage on my own laptop instead | [RUNNING.md](RUNNING.md) |

---

## Every day

The whole routine, in order, with every command written out. Nothing here
refers you elsewhere.

### Morning — bring it up

**1. Start the machine.** On your own machine:

```bash
# ON YOUR OWN MACHINE
aws ec2 start-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767
```

**2. Check it worked.** Still on your own machine. Repeat until it says
`running` — takes about a minute:

```bash
# ON YOUR OWN MACHINE
aws ec2 describe-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767 \
  --query 'Reservations[0].Instances[0].State.Name' --output text
```

`pending` means still booting. `running` means the machine is up — though SSH
needs another 15-30 seconds after that before it accepts connections.

**3. SSH in.** On your own machine:

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7
```

Your prompt changes to `ubuntu@ip-172-31-24-158`. You are now on the instance.

**4. Start the containers.** On the instance:

```bash
# ON THE INSTANCE
cd ~/engage-fork
docker compose -f docker-compose.prod.yml up -d
```

**5. Check all six are up.** On the instance:

```bash
# ON THE INSTANCE
docker compose -f docker-compose.prod.yml ps
```

You want six lines, every one saying `Up`: `calliope-app`,
`calliope-postgres`, `calliope-redis`, `calliope-short-worker`,
`calliope-long-worker`, `calliope-celery-flower`.

**6. Open it.** In a browser:

```
http://3.151.238.7:8000/en/login/
```

Note on step 4: it is usually a no-op. Every container is
`restart: unless-stopped`, so Docker brings them back on its own when the
machine boots. Run on an already-running stack, `up -d` prints six `Running`
lines and changes nothing — it is harmless, and running it means you never have
to wonder. If step 5 shows six `Up` without step 4, that is correct and
expected, not a sign you skipped something.

### Morning, as one paste

Steps 1-2 on your own machine:

```bash
# ON YOUR OWN MACHINE
aws ec2 start-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767

for i in $(seq 1 40); do
  STATE=$(aws ec2 describe-instances --region us-east-2 \
    --instance-ids i-0c251de2dc1a35767 \
    --query 'Reservations[0].Instances[0].State.Name' --output text)
  echo "$STATE"
  [ "$STATE" = "running" ] && break
  sleep 5
done
```

The loop gives up after about three minutes rather than spinning forever, so a
start that silently failed shows as a wall of `stopped` instead of hanging.

Then steps 3-5 as a single command, which SSHes in, starts the containers and
prints their status without opening an interactive session:

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 \
  'cd ~/engage-fork && docker compose -f docker-compose.prod.yml up -d \
   && docker compose -f docker-compose.prod.yml ps'
```

### Evening — shut it down

**1. Leave the instance.** If your prompt says `ubuntu@ip-...`:

```bash
# ON THE INSTANCE
exit
```

**2. Stop the machine.** On your own machine. Nothing to stop inside the
instance first — the containers go down with it:

```bash
# ON YOUR OWN MACHINE
aws ec2 stop-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767
```

**3. Confirm it stopped.** On your own machine, so you are not billed for a
machine you thought was off:

```bash
# ON YOUR OWN MACHINE
aws ec2 describe-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767 \
  --query 'Reservations[0].Instances[0].State.Name' --output text
```

`stopping` first, then `stopped` after about a minute. Only `stopped` stops the
hourly charge.

### What you never have to do

- **`docker compose down` before stopping.** The containers stop with the
  machine.
- **Edit `.envs/.prod` afterwards.** An Elastic IP keeps the address at
  3.151.238.7 through any number of stop/starts.
- **Rebuild.** `--build` is only for deploying changed code.

### Cost

| | |
| --- | --- |
| Running 24/7 | ~$60/month |
| Stopped | ~$8/month — the 60 GB disk and the Elastic IP |

Stopping is reversible and instant. **Terminating is not** — it destroys the
disk. Stop = pause, terminate = delete forever.

### Aliases, since this is daily

```bash
# ON YOUR OWN MACHINE  —  add to ~/.zshrc, then run: source ~/.zshrc
alias engage-on='aws ec2 start-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767'
alias engage-off='aws ec2 stop-instances  --region us-east-2 --instance-ids i-0c251de2dc1a35767'
alias engage-state='aws ec2 describe-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767 --query "Reservations[0].Instances[0].State.Name" --output text'
alias engage-ssh='ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7'
alias engage-up='ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 "cd ~/engage-fork && docker compose -f docker-compose.prod.yml up -d && docker compose -f docker-compose.prod.yml ps"'
```

---

## Read this first: two machines, two stacks

There are **two completely separate copies** of Engage, and they share nothing.

| | Your own machine | The instance |
| --- | --- | --- |
| Docker daemon | OrbStack, on your Mac | the instance's own `dockerd` |
| Repo | wherever you cloned it | `~/engage-fork` |
| Compose file | `docker-compose.yml` | `docker-compose.prod.yml` |
| Database | its own `./postgres/data` | its own `./postgres/data` |
| Who can see it | only you | anyone on the IP allowlist |

**`docker compose up -d` on your laptop does not touch the instance.** It never
has. It talks to the Docker daemon on whatever machine you typed it on. To
change the live site you must first `ssh` in — then your shell is *on* the
instance, and the same command means something entirely different.

Consequences worth internalising:

- `git push` does **not** deploy. You have to pull and rebuild on the instance.
- An account you create locally does not exist on the live site, and vice versa.
- Quitting OrbStack, or `docker compose down` locally, has no effect on the live site.
- Conversely, nothing you do on the instance affects your local work.

**How to tell where you are:** the shell prompt. `ubuntu@ip-...` means you are
on the instance. Anything else is your own machine. `exit` comes back.

Throughout this document every command block is tagged with where it runs:

```bash
# ON YOUR OWN MACHINE
```

```bash
# ON THE INSTANCE  —  after ssh, from ~/engage-fork
```

If a block has no tag, it is not meant to be run as-is.

---

## Opening the app

**http://3.151.238.7:8000** — in a browser, from any machine whose IP is
allowlisted. Nothing to start first; the site is served continuously.

| Path | What it is |
| --- | --- |
| `/` | redirects to `/en/`, which redirects to the login page |
| **`/en/login/`** | **the login page — go straight here** |
| `/en/admin/` | Django admin |

Verified 17 Sep 2026: `/` → 302 `/en/` → 302 `/en/login/?next=/en/`, and
`/en/login/` returns 200.

### Does this address change?

**No, and that was deliberate.** An Elastic IP (`eipalloc-0452b74f4367843db`)
is attached to the instance, so 3.151.238.7 survives stop/start. Before it was
attached, every restart handed out a new random address, which broke
`DJANGO_ALLOWED_HOSTS` and produced a `DisallowedHost` error until `.envs/.prod`
was edited by hand.

Only three things would change it:

| | |
| --- | --- |
| Releasing the Elastic IP | only when deliberately tearing the instance down |
| Rebuilding the instance from scratch | a new EIP would be allocated — see [Rebuilding](#rebuilding-the-instance-from-nothing) |
| **Getting a domain and TLS** | the address becomes `https://<name>` and public 8000 closes — see [Planned: domain and TLS](#planned-domain-and-tls) |

What *does* change is **your own** IP address, which is a different problem with
the same symptom. See [Locked out](#locked-out-your-ip-changed).

### Two things that will bite you in a browser

- **It must be `http://`, not `https://`.** There is no TLS on this box. Typing
  `3.151.238.7:8000` bare into the address bar makes Chrome and Safari try
  HTTPS first or treat it as a search, and the connection fails with nothing
  useful on screen. Type the `http://` explicitly.
- **A hang means your IP, not the server.** Access is by IP allowlist, so an
  address that is not on the list gets a TCP timeout — never a login page and
  never an error. If the page spins forever, check the allowlist before
  assuming Engage is down.

### Logging in

The instance has its own database, so a local account does not work here — see
[two machines, two stacks](#read-this-first-two-machines-two-stacks). Accounts
are created by hand because registration email is not configured.

To see which accounts exist, see
[Seeing which accounts exist](#7-seeing-which-accounts-exist). To make one, see
[Creating a user account](#6-creating-a-user-account).

If a password is lost, reset it without needing the old one:

```bash
# ON THE INSTANCE
docker exec -it calliope-app python3 manage.py changepassword <email>
```

Keep the two copies straight:

| | |
| --- | --- |
| http://localhost:8000 | your laptop's copy |
| http://3.151.238.7:8000 | the live one |

Same app, same container names, different databases.

---

## Running it on the instance

### The main command

Start to finish — get on the instance and bring Engage up:

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7
```

```bash
# ON THE INSTANCE  —  now that you're in
cd ~/engage-fork
docker compose -f docker-compose.prod.yml up -d
```

Or as a single line from your own machine, without an interactive session:

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 \
  'cd ~/engage-fork && docker compose -f docker-compose.prod.yml up -d'
```

Two things to know before reaching for it:

- **You rarely need it.** Every container is `restart: unless-stopped`, so
  Engage comes back by itself after a reboot or an instance start. `up -d` on an
  already-running stack prints six `Running` lines and changes nothing — it is
  safe, just usually unnecessary.
- **It won't help if the machine is off.** A stopped instance refuses SSH, so
  step 1 below comes first.

Add `--build` only when the code changed — see
[Deploying a code change](#5-deploying-a-code-change).

The rest of this section is the same path, one step at a time, with what goes
wrong at each.

### 1. Make sure the machine is switched on

The instance is often stopped to save money, and a stopped instance answers
nothing — SSH hangs and the site times out.

```bash
# ON YOUR OWN MACHINE
aws ec2 describe-instances --region us-east-2 \
  --instance-ids i-0c251de2dc1a35767 \
  --query 'Reservations[0].Instances[0].State.Name' --output text
```

If that says `stopped`:

```bash
# ON YOUR OWN MACHINE
aws ec2 start-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767
```

Give it a minute. The containers all have `restart: unless-stopped`, so Engage
comes back by itself — you do not have to start it after a reboot.

### 2. Connect

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7
```

Your prompt changes to `ubuntu@ip-...`. You are now on the instance.

If this hangs, it is almost always your IP rather than the server — see
[Locked out](#locked-out-your-ip-changed).

### 3. Go to the repo

Compose looks for the file relative to wherever you are, so every command in
the next step fails with
`open docker-compose.prod.yml: no such file or directory` without this:

```bash
# ON THE INSTANCE
cd ~/engage-fork
```

### 4. The four commands you actually need

Note the `-f docker-compose.prod.yml` on every one. Leaving it off silently
uses the *development* compose file, which publishes the database and broker
ports to the internet — so it matters.

```bash
# ON THE INSTANCE  —  from ~/engage-fork

docker compose -f docker-compose.prod.yml ps          # what is running
docker compose -f docker-compose.prod.yml logs -f app # watch the app log
docker compose -f docker-compose.prod.yml restart app # restart just the app
docker compose -f docker-compose.prod.yml up -d       # bring anything missing up
```

To stop Engage without stopping the machine:

```bash
# ON THE INSTANCE  —  from ~/engage-fork
docker compose -f docker-compose.prod.yml down         # stop all six containers
docker compose -f docker-compose.prod.yml up -d        # and back up again
```

`down` removes the containers but **not** the data — the database and `data/`
tree are bind mounts on the host disk, so they outlive it. Note that `down`
leaves the instance running and still billing; to actually save money, stop the
machine ([step 8](#8-stopping-the-machine-when-youre-done)).

`ps` should show six containers, all `Up`:

| Container | Role |
| --- | --- |
| `calliope-app` | Django / gunicorn — serves port 8000 |
| `calliope-postgres` | database |
| `calliope-redis` | job queue |
| `calliope-short-worker` | fast Celery tasks |
| `calliope-long-worker` | model solves |
| `calliope-celery-flower` | task dashboard |

`Ctrl+C` out of `logs -f` stops *watching*; it does not stop the app.

### 5. Deploying a code change

The production compose file does **not** mount the source tree — the code lives
inside the image. So `git pull` on its own changes nothing you can see:

```bash
# ON THE INSTANCE  —  from ~/engage-fork
git pull
docker compose -f docker-compose.prod.yml up -d --build
```

Skip the `--build` and the containers keep serving the previous code. (The local
development stack *does* bind-mount the source, which is why edits appear
instantly there and not here. That difference is deliberate.)

A change to `.envs/.prod` alone needs no rebuild — just new containers:

```bash
# ON THE INSTANCE  —  from ~/engage-fork
docker compose -f docker-compose.prod.yml up -d --force-recreate
```

Rebuilding takes ~8 minutes on the instance. The app is down for the last few
seconds of it.

### 6. Creating a user account

Registration emails require SES, which is not configured, so accounts are made
by hand. Engage uses the email address as the username:

```bash
# ON THE INSTANCE
docker exec -it calliope-app python3 manage.py createsuperuser
```

### 7. Seeing which accounts exist

```bash
# ON THE INSTANCE
docker exec calliope-postgres psql -U postgres -d postgres \
  -c "select id, username, email, is_superuser, date_joined, last_login
        from auth_user order by date_joined;"
```

Or in one shot without logging in first:

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 \
  "docker exec calliope-postgres psql -U postgres -d postgres \
   -c \"select username, email, date_joined from auth_user order by date_joined;\""
```

Remember this reads the *instance's* database. The same query on your laptop
reads a different one with different rows.

### 8. Stopping the machine when you're done

```bash
# ON YOUR OWN MACHINE  —  exit the instance first
aws ec2 stop-instances  --region us-east-2 --instance-ids i-0c251de2dc1a35767
```

This is the one thing you **cannot** do from the instance — you are asking
Amazon to switch off the computer you would be typing on, and the AWS CLI is
deliberately not installed there.

Full details, costs and the shell aliases are in
[Every day](#every-day).

### Where to run what — the short version

| Command | Runs | Controls |
| --- | --- | --- |
| `docker compose -f docker-compose.prod.yml ...` | **on the instance**, from `~/engage-fork` | the containers |
| `docker exec ...` | **on the instance** | inside a container |
| `aws ec2 ...` | **on your own machine** | the machine itself |
| `scripts/status.sh` | **on your own machine** | nothing — it only reports |

---

## Quick reference

| | |
| --- | --- |
| App | http://3.151.238.7:8000 — login at `/en/login/`, admin at `/en/admin/` |
| SSH | `ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7` |
| Repo on the instance | `~/engage-fork` |
| Compose file on the instance | `docker-compose.prod.yml` |
| Instance | `i-0c251de2dc1a35767` — t3.large, 60 GB, Ubuntu 26.04 |
| Region | us-east-2 (Ohio) |
| Security group | `sg-0619d031ef5e8a521` |
| Elastic IP | `eipalloc-0452b74f4367843db` → 3.151.238.7 |
| Secrets on the instance | `~/engage-fork/.envs/.prod` (not in git) |

Every AWS CLI command needs `--region us-east-2`, or it silently looks
elsewhere and reports nothing.

---

## Checking it yourself

```bash
# ON YOUR OWN MACHINE
scripts/status.sh
```

It answers, with a real command behind each line rather than an assertion:

- **Whose infrastructure is this?** — which AWS account and identity
- **Is the server on?** — instance state, and what it costs while running
- **Can you reach it?** — your current IP against the firewall allowlist, plus
  whether the app actually answers
- **Is every part running?** — all six containers
- **Is it doing its job?** — users, models, and how many solves succeeded
- **Are backups happening?** — latest local copy, latest in S3, and whether the
  nightly job is still scheduled
- **What is connected?** — which integrations have credentials and which are
  dark, including whether HTTPS exists
- **Is anything broken?** — server errors in the last 24 hours

A failing line prints the command to investigate further. If the instance is
stopped it says so and stops, since nothing else can be checked.

---

## Getting in

### SSH

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7
```

`ubuntu` because the OS is Ubuntu (Amazon Linux would be `ec2-user`).

The key is **not recoverable from AWS** — Amazon keeps no copy. Back it up
somewhere safe; losing it means losing access to the instance. It must also be
`chmod 400`, or `ssh` refuses to use it.

### Locked out: your IP changed

Access is controlled by **IP allowlist**, not by the application. Someone not on
the list gets a TCP timeout — they never reach a login page. So a sudden hang
while AWS reports the instance `running` almost always means your address moved.
Home addresses change; home and office differ.

```bash
# ON YOUR OWN MACHINE
curl -s https://checkip.amazonaws.com        # what is my IP now?

aws ec2 authorize-security-group-ingress --region us-east-2 \
  --group-id sg-0619d031ef5e8a521 --ip-permissions \
  'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=X.X.X.X/32,Description="who"}]' \
  'IpProtocol=tcp,FromPort=8000,ToPort=8000,IpRanges=[{CidrIp=X.X.X.X/32,Description="who"}]'
```

`scripts/status.sh` checks your current IP against the allowlist for you.

### Port-forwarding Postgres

Postgres is bound to `127.0.0.1:5432` on the instance, so it only accepts
connections that originate on that machine. There is no security group rule for
it and nothing on the internet can reach it.

An SSH tunnel gets you in anyway, without opening anything. It makes a port on
your own machine behave as though it were a port on the server, carrying the
traffic through the SSH connection that already exists:

```
   your machine                                the instance
  ┌──────────────┐                          ┌──────────────┐
  │ client  →    │                          │              │
  │ localhost:   │  ═══ encrypted SSH ═══►  │ localhost:   │
  │   5433       │      (port 22)           │   5432       │
  │              │                          │      │       │
  │              │                          │      ▼       │
  │              │                          │  postgres    │
  └──────────────┘                          └──────────────┘
```

As far as Postgres is concerned the connection is local — it arrives from the
SSH daemon on the same host. So you get full database access with no additional
exposure. The alternative, opening 5432 in the security group, would put the
database on the public internet.

```bash
# ON YOUR OWN MACHINE  —  leave this running in a terminal
ssh -i ~/.ssh/engage-hseo.pem -L 5433:localhost:5432 -N ubuntu@3.151.238.7
#                                │      │         │
#                                │      │         └ destination, as seen FROM the instance
#                                │      └─────────── port opened on your machine
#                                └────────────────── "local forward"
# -N means "forward only, do not open a shell"
```

Note the `localhost` in the middle is the *instance's* localhost, not yours.

Then point any client at `localhost:5433`:

```bash
# ON YOUR OWN MACHINE  —  in a second terminal
psql -h localhost -p 5433 -U postgres -d postgres
```

Credentials are in `.envs/.prod` on the instance:

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 \
  'grep POSTGRES ~/engage-fork/.envs/.prod'
```

Add `-f` to background the tunnel; close it later with
`pkill -f "5433:localhost:5432"`.

### Flower, the same way

```bash
# ON YOUR OWN MACHINE
ssh -i ~/.ssh/engage-hseo.pem -L 5555:localhost:5555 -N ubuntu@3.151.238.7
```

Then open http://localhost:5555 and authenticate with `FLOWER_BASIC_AUTH` from
`.envs/.prod`. Flower shows the Celery queues and running model solves.

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

The containers are disposable; those two directories are not. They are bind
mounts onto the instance's root disk, which is why rebuilding the whole stack
does not lose the database or anyone's models.

Not in Docker: the nightly backup job (a plain host crontab entry) and nothing
else. There is no reverse proxy — gunicorn is published directly on 8000.

### What is exposed, and what is not

| Port | Bound to | Reachable by |
| --- | --- | --- |
| 22 | public interface | allowlisted IPs only |
| 8000 | public interface | allowlisted IPs only |
| 5432 (Postgres) | `127.0.0.1` on the host | SSH tunnel only |
| 5555 (Flower) | `127.0.0.1` on the host | SSH tunnel only, plus basic auth |
| 6379 (Redis) | Docker network only | nothing outside the containers |

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

## Backups

### What runs automatically

`~/backup-engage.sh` on the instance, nightly at 09:15 UTC (23:15 Hawai'i),
via cron. It writes to `~/backups` and keeps the last 14 of each:

- `engage-db-<timestamp>.sql.gz` — `pg_dump` of the whole database
- `engage-data-<timestamp>.tar.gz` — the `data/` tree: model inputs,
  uploaded timeseries, run outputs

```bash
# ON THE INSTANCE
~/backup-engage.sh          # run one now
tail ~/backups/backup.log   # what cron did
ls -lht ~/backups           # what exists
```

**These land on the same disk as the database.** They protect against a bad
migration, an accidental delete, or corruption. They do **not** protect against
losing the volume or the instance — for that they have to leave the box.

### Getting backups off the instance

An S3 bucket exists and is correctly configured:

```
s3://hseo-engage-backups-699752150149      us-east-2
  public access blocked · AES256 encryption · versioning on
  postgres/ expires after 90 days, old versions after 30
```

The instance **cannot write to it yet** — see the blocker below. Until that is
resolved, copy backups up from a workstation that has AWS credentials:

```bash
# ON YOUR OWN MACHINE
LATEST=$(ssh -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7 \
  'ls -1t ~/backups/engage-db-*.sql.gz | head -1')

scp -i ~/.ssh/engage-hseo.pem ubuntu@3.151.238.7:"$LATEST" .
aws s3 cp "$(basename $LATEST)" s3://hseo-engage-backups-699752150149/postgres/
```

### Blocker: the instance needs an IAM instance profile

For the nightly job to upload by itself, the instance needs an IAM role
attached. The role already exists and is scoped to this bucket alone:

```
role:   engage-backup-role
policy: engage-backup-s3-write  (s3:PutObject, s3:GetObject, s3:ListBucket
                                 on hseo-engage-backups-699752150149 only)
```

What is missing is the instance profile that binds the role to the instance.
Creating one requires `iam:CreateInstanceProfile` and
`iam:AddRoleToInstanceProfile`, which the current user does not have. Someone
with IAM administration needs to run:

```bash
# ON YOUR OWN MACHINE  —  requires IAM admin rights
aws iam create-instance-profile --instance-profile-name engage-backup-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name engage-backup-profile --role-name engage-backup-role

aws ec2 associate-iam-instance-profile --region us-east-2 \
  --instance-id i-0c251de2dc1a35767 \
  --iam-instance-profile Name=engage-backup-profile
```

After that, add the upload to `backup-engage.sh` — no credentials needed on the
instance, since boto3 and the AWS CLI pick up the role automatically:

```bash
# lines to ADD to ~/backup-engage.sh on the instance -- not to run by hand
aws s3 cp "$DIR/engage-db-$STAMP.sql.gz"   s3://hseo-engage-backups-699752150149/postgres/
aws s3 cp "$DIR/engage-data-$STAMP.tar.gz" s3://hseo-engage-backups-699752150149/data/
```

Using a long-lived access key on the instance instead would work but is worse:
keys sit on disk, do not rotate, and belong to a person rather than the machine.

### Snapshots — the off-instance copy that works today

Until the instance can upload to S3 itself, an EBS snapshot is the way to get a
copy off the machine. AWS stores snapshots separately from the instance, so one
survives the volume being destroyed, and it captures the nightly dumps in
`~/backups` along with everything else.

```bash
# ON YOUR OWN MACHINE
scripts/snapshot-engage.sh
```

It creates a snapshot, keeps the most recent 10, and deletes older ones.

Automating it inside AWS needs Data Lifecycle Manager, which the deploying user
cannot access. Until then this is manual — worth running before any risky
change, and on a regular cadence once real data exists.

A snapshot of a running database is crash-consistent, not clean. That is fine
here: **restore from the `pg_dump` inside the snapshot, not from the raw
database files.** The dump was written by Postgres itself and is internally
consistent.

### Restoring

Tested 7 Sep 2026 — a dump was restored into a scratch database and the row
counts matched the live one exactly.

```bash
# ON THE INSTANCE
PW=$(grep '^POSTGRES_PASSWORD=' ~/engage-fork/.envs/.prod | cut -d= -f2-)

# restore into a scratch database first, always
docker exec -e PGPASSWORD="$PW" calliope-postgres \
  psql -U postgres -d postgres -c "create database restoretest;"

gunzip -c ~/backups/engage-db-<timestamp>.sql.gz \
  | docker exec -i -e PGPASSWORD="$PW" calliope-postgres psql -U postgres -d restoretest

# check it looks right
docker exec -e PGPASSWORD="$PW" calliope-postgres psql -U postgres -d restoretest \
  -c "select count(*) from auth_user;"
```

To restore over the live database, stop the app and workers first so nothing
writes during the load:

```bash
# ON THE INSTANCE  —  from ~/engage-fork
docker compose -f docker-compose.prod.yml stop app short_worker long_worker
# drop and recreate `postgres`, load the dump, then:
docker compose -f docker-compose.prod.yml start app short_worker long_worker
```

Restore the `data/` archive alongside it — the database stores file *paths*, so
a database restored without its files has broken references.

---

## Rebuilding the instance from nothing

There is no infrastructure as code, so recreating this means following these
steps. Recorded here because it is the only copy.

**Launch the instance** through the EC2 console wizard. The non-default choices
all matter:

| Setting | Value | Why |
| --- | --- | --- |
| AMI | Ubuntu Server 26.04 LTS, **x86_64** | the images are `linux/x86_64`; ARM would emulate everything |
| Instance type | `t3.large` | `t3.micro`'s 1 GB RAM cannot build the image — it dies partway |
| Storage | **60 GiB** gp3 | the default 8 GB is too small to build the image; this is the trap that kills the build halfway |
| Key pair | RSA, `.pem` | downloads **once**, and AWS keeps no copy |
| Firewall | SSH source = **My IP**, not Anywhere | an earlier box had SSH open to the internet for five months |

Then, from your own machine:

```bash
# ON YOUR OWN MACHINE
chmod 400 ~/.ssh/engage-hseo.pem     # it downloads world-readable; ssh refuses those

# the wizard only adds the SSH rule — add the app port too
aws ec2 authorize-security-group-ingress --region us-east-2 \
  --group-id <new-sg-id> --ip-permissions \
  'IpProtocol=tcp,FromPort=8000,ToPort=8000,IpRanges=[{CidrIp=YOUR.IP/32}]'
```

Then on the box itself:

```bash
# ON THE INSTANCE
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2
sudo usermod -aG docker ubuntu
exit    # log out and back in, or every docker command says "permission denied"
        # — group membership only takes effect at login
```

```bash
# ON THE INSTANCE
git clone https://github.com/hdt-gif/engage-fork.git
cd engage-fork

cp prod.env.example .envs/.prod
chmod 600 .envs/.prod
# then fill it in: a fresh DJANGO_SECRET_KEY, a fresh POSTGRES_PASSWORD,
# FLOWER_BASIC_AUTH, MAPBOX_TOKEN, and DJANGO_ALLOWED_HOSTS /
# DJANGO_CSRF_TRUSTED_ORIGINS pointing at this instance's address.
# See prod.env.example — every variable is commented with what breaks without it.

docker compose -f docker-compose.prod.yml up -d --build   # ~8 minutes
```

Finally, attach an Elastic IP so the address survives stop/start — without one
it changes on every restart and `DJANGO_ALLOWED_HOSTS` breaks each time:

```bash
# ON YOUR OWN MACHINE
aws ec2 allocate-address --region us-east-2 --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=engage-hseo}]'

aws ec2 associate-address --region us-east-2 \
  --instance-id <instance-id> --allocation-id <eipalloc-...>
```

An Elastic IP belongs to the AWS **account**, not to a person, so it transfers
with the account. An *unreleased* one keeps costing money forever, so release it
if the instance is ever destroyed:
`aws ec2 release-address --region us-east-2 --allocation-id <eipalloc-...>`.

### Deleting it permanently

Stopping is reversible and instant. **Terminating is permanent and destroys the
disk.** Stop = pause; terminate = delete forever.

```bash
# ON YOUR OWN MACHINE
aws ec2 terminate-instances --region us-east-2 --instance-ids i-0c251de2dc1a35767

# then check nothing is left billing you — an orphaned disk costs money forever
aws ec2 describe-volumes --region us-east-2 --query 'Volumes[].VolumeId'
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
| **Backups do not leave the instance** | Nightly dumps run and restore correctly, but they sit on the same disk as the database. Off-instance upload is blocked on an IAM instance profile — see [Backups](#backups). |
| **IP allowlist only** | HSEO staff cannot reach it. Widening access before TLS would mean staff sending passwords over plain HTTP. |
| **Personal Mapbox token** | Maps run on a token belonging to a personal account. HSEO needs its own. |
| **Instance size is a guess** | `t3.large` chosen without knowing real model sizes. Resizing is a stop, change type, start. |
| **No infrastructure as code** | The instance was created by hand. Recreating it means following [Rebuilding the instance from nothing](#rebuilding-the-instance-from-nothing), not running a script. |

Backups are the highest-stakes item. HSEO decided to start from scratch rather
than migrate, so once they begin building models the instance is the **only**
copy of their work. Suggested minimum: a nightly `pg_dump` to S3, scheduled
snapshots of the volume holding `./data`, and — critically — a restore that has
actually been tested.

---

## Upstream fixes made during deployment

Seven bugs in the inherited codebase, all fixed and committed. Engage could not
run under `settings.prod` without them.

1. **gunicorn** — referenced by `settings/prod.py` but missing from `requirements.txt`
2. **`/opt/python/log`** — the production logging handler writes there; nothing created it, so Django failed at startup
3. **Static files** — with `DEBUG=False` Django stops serving `STATIC_ROOT`; WhiteNoise now does
4. **Broker TLS** — `CELERY_BROKER_USE_SSL` was hardcoded on, so workers could not reach a plain Redis container. Now env-configurable, still defaulting to on
5. **Secure cookies** — `SESSION_COOKIE_SECURE` / `CSRF_COOKIE_SECURE` hardcoded on made login impossible without HTTPS. Now env-configurable, still defaulting to on
6. **Fixture ordering** — `loaddata` ran before `migrate` and failed silently, so reference data never loaded on a fresh install. Seeding now runs through `compose/seed-reference-data.sh`, which only populates an empty database
7. **Race condition in `build_model`** — `run_options` was saved *after* dispatching the Celery task, so a worker that started first read `NULL` and crashed. Timing-dependent: passed on a 4-core laptop, failed consistently on this 2-core instance

Items 1–3 and 6–7 affect anyone deploying Engage, not just HSEO.
