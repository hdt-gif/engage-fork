# NLR Engage: A [Calliope](https://github.com/calliope-project/calliope) Web Environment for Collaborative Energy Systems Modeling and Planning

Engage is a free, open-access energy system planning tool that allows multiple users/stakeholders to develop and collaborate on capacity expansion models. The tool, developed at the National Laboratory of the Rockies (NLR), provides a collaborative and easy-to-use interface built on Calliope, a multi-scale energy systems modeling framework.

- Visit the NLR hosted webtool at https://engage.nrel.gov/

---

## HSEO fork

This fork hosts Engage for the **Hawai'i State Energy Office**, ahead of NREL
ending its hosted service.

There are two separate copies of Engage, and the docs are split the same way.
Pick by *which machine you mean*:

| | Doc |
| --- | --- |
| **Daily start / stop / connect routine** (saves ~$50/month) | [Every day](DEPLOYMENT.md#every-day) |
| **Open the live HSEO site** | http://3.151.238.7:8000 — login at `/en/login/` |
| **Operate it** — start/stop, deploy a change, create accounts, backups, SSH, database access | [DEPLOYMENT.md](DEPLOYMENT.md) |
| ↳ just the commands, in order | [Running it on the instance](DEPLOYMENT.md#running-it-on-the-instance) |
| ↳ is it working right now? | `scripts/status.sh`, from your own machine |
| **Run it on your own laptop** for development | [RUNNING.md](RUNNING.md) |

`docker compose up -d` on your laptop does **not** touch the live site — it
talks to the Docker daemon on whichever machine you typed it on. Changing the
live site means `ssh`-ing in first. [DEPLOYMENT.md](DEPLOYMENT.md#read-this-first-two-machines-two-stacks)
opens with this distinction because it is the easiest thing here to get wrong.

The deployment guide also records the upstream bugs fixed to get Engage running
under `settings.prod` — it could not start in production without them.

---

## Requirements
- Docker (https://www.docker.com/get-started)
- Docker Compose (e.g. ```brew install docker-compose```)


## Development

Please refer to the documentation to setup development environment,

https://nrel.github.io/engage

and the developer guide to contribute to Enage project.

## License
BSD 3-Clause License
https://github.com/NREL/engage/blob/master/LICENSE