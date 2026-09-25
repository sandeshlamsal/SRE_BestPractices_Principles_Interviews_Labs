# SRE Best Practices, Principles, Interviews & Labs

A hands-on lab for learning Site Reliability Engineering by **running a real
microservices e-commerce app** and operating it the way production SRE teams do:
SLOs, error budgets, alerting, incident response, postmortems, chaos, and toil reduction.

**Lab app:** [OpenTelemetry Astronomy Shop](https://opentelemetry.io/docs/demo/), a
CNCF e-commerce demo with 15+ services in 10+ languages, a load generator, and
built-in failure injection via feature flags. The reasons for this choice are in
[ADR-0001](docs/adr/0001-lab-application.md).

## Quick start

Prerequisites: Docker (give it **12 GB RAM, 8 CPUs**; see [sizing](docs/environments-and-sizing.md)), kind, kubectl, helm.

```bash
make cluster-up   # 3-node kind cluster
make deploy       # install the Astronomy Shop (~5-10 min first time)
make status
make open         # http://localhost:8080
```

## Progress

| Phase | Status |
|---|---|
| 0 Foundation · 1 SLOs · 2 Observability | ✅ done |
| 3 Alerting & on-call | ✅ done (real PagerDuty/Slack pending credentials) |
| 4 Incident game days | 🔄 in progress (GD1 done) |

Highlights: an SLI that was blind to a 50% outage, found and fixed; memory-limit thrashing with zero OOM kills;
and a root cause we got **wrong** and corrected in the open ([sre-in-practice.md](docs/sre-in-practice.md)).

## Repository layout

| Path | Purpose |
|---|---|
| [docs/tool-stack.md](docs/tool-stack.md) | Production-grade tool stack: local vs AWS EKS vs Azure AKS, enforced standards, known gaps |
| [docs/architecture.md](docs/architecture.md) | What the app looks like: user flows, service map, platform layers |
| [docs/environments-and-sizing.md](docs/environments-and-sizing.md) | Local vs cloud, what each can test, resource sizing, cost |
| [docs/observability-plan.md](docs/observability-plan.md) | Stack, SLI catalogue, SLOs as code, error budget tracking, alert routing |
| [docs/incident-response-plan.md](docs/incident-response-plan.md) | On-call, severity matrix, response workflow, runbooks, game days |
| [docs/sre-way.md](docs/sre-way.md) | Our SRE operating model: the principles and rules we follow |
| [docs/principles/](docs/principles/) | SRE concepts (SLI/SLO/SLA, error budgets, incidents, postmortems, and more) mapped to this lab |
| [docs/lab-matrix.md](docs/lab-matrix.md) | Phases × local vs cloud × SRE principle coverage |
| [docs/labs/](docs/labs/README.md) | **Step-by-step execution guides per phase**: commands, outputs, issues and fixes |
| [docs/sre-in-practice.md](docs/sre-in-practice.md) | **What the lab proved**: each SRE principle → what we built → evidence → lesson |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phased learning plan with labs and exit criteria |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [docs/templates/](docs/templates/) | SLO, runbook, and postmortem templates |
| [platform/](platform/) | Cluster and infrastructure config |
| [apps/](apps/) | Helm values for workloads |

Directories for `slos/`, `alerts/`, `runbooks/`, `postmortems/`, `chaos/`, and
`interviews/` get added in their roadmap phases.
