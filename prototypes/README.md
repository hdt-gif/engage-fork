# Add-on prototypes (not part of Engage)

These are standalone design prototypes for possible Engage add-ons. They are
**not** part of the Engage app: nothing here is built into the Docker image
(which builds from `calliope_app/` only) or mounted by `docker-compose.yml`.
Open either file directly in a browser.

They explore one question, *"What is the cheapest way to meet the island's
electricity needs, given the parameters we provide?"*, and what other modeling
tools could add to Engage's answer.

| Prototype | Tool it imitates | Tabs |
| --- | --- | --- |
| [`gridpath/index.html`](gridpath/index.html), "Engage Reliability Planner" | [GridPath](https://github.com/blue-marble/gridpath) | Reserves · Capacity credit (ELCC) · Pathway to 2045 · Retirements |
| [`pypsa/index.html`](pypsa/index.html), "Engage Plan Explorer" | [PyPSA](https://github.com/PyPSA/PyPSA) | Alternatives (MGA) · Grid check (power flow, single line outages) · Uncertain futures (stochastic) |

## Read this before showing them to anyone

- **All data is dummy data.** The island is a made-up O‘ahu-sized system. Some
  inputs are loosely based on real figures (roughly O‘ahu's peak demand,
  Hawai‘i's renewable portfolio standard targets, ballpark build costs), but
  none come from HSEO, Hawaiian Electric or any real dataset. The five-point
  network, the seven oil units, the futures and the pathway settings are
  invented.
- **Some inputs were tuned so each feature has something to show**: line
  ratings were lowered so the grid check finds an overload, old steam units'
  upkeep was raised so the retirement search retires something, and keeping the
  lights on is a hard requirement in the futures tab. Results like "Engage's
  plan is short of reserve 20 hours a year" demonstrate what a feature *can*
  catch. They are not findings about Hawai‘i.
- **Neither GridPath nor PyPSA runs here.** Simplified calculations in the
  browser stand in for them: a grid search over build sizes, five representative
  days, simplified dispatch and DC power flow, a peak-hour capacity-credit
  method, and step-by-step pathway and retirement searches. Each page's "How
  this attaches to Engage" section describes what the real add-on would run.

## How a real add-on would attach

A new Django app would read a run's model from Engage's Postgres database,
translate it to GridPath or PyPSA inputs, solve it on the Celery worker Engage
already uses, and show the results as a new tab on the run, without changing
Engage's own tables.
