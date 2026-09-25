# SRE Best Practices, Principles, Interviews & Labs

A hands-on lab for learning Site Reliability Engineering by **running a real
microservices e-commerce app** and operating it the way production SRE teams do:
SLOs, error budgets, alerting, incident response, postmortems, chaos, and toil reduction.

**Lab app:** [OpenTelemetry Astronomy Shop](https://opentelemetry.io/docs/demo/), a
CNCF e-commerce demo with 15+ services in 10+ languages, a load generator, and
built-in failure injection via feature flags. The reasons for this choice are in
[ADR-0001](docs/adr/0001-lab-application.md).

## Quick start

Prerequisites: Docker (give it **≥ 6 GB RAM, 4 CPUs**), kind, kubectl, helm.

```bash
make cluster-up   # 3-node kind cluster
make deploy       # install the Astronomy Shop (~5-10 min first time)
make status
make open         # http://localhost:8080
```

## Repository layout

| Path | Purpose |
|---|---|
| [docs/sre-way.md](docs/sre-way.md) | Our SRE operating model: the principles and rules we follow |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Phased learning plan with labs and exit criteria |
| [docs/adr/](docs/adr/) | Architecture Decision Records |
| [docs/templates/](docs/templates/) | SLO, runbook, and postmortem templates |
| [platform/](platform/) | Cluster and infrastructure config |
| [apps/](apps/) | Helm values for workloads |

Directories for `slos/`, `alerts/`, `runbooks/`, `postmortems/`, `chaos/`, and
`interviews/` get added in their roadmap phases.
