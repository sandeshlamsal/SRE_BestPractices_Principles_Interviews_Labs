# Phase 9 (Capstone): Disaster Recovery + Production Readiness Review

> **Goal:** prove the shop can be recovered from a disaster within stated targets, then honestly assess how
> production-ready the whole lab is. **Principles:** [05 Postmortems](../principles/05-postmortems.md), [08 Resilience](../principles/08-capacity-resilience-chaos.md),
> [09 PRR](../principles/09-culture-oncall.md#production-readiness-review-checklist-use-it-on-the-astronomy-shop). **Executed:** 2026-09-26.

---

## Part 1: Disaster recovery

### Targets (set BEFORE the drill)
| Component | Data | RPO target | RTO target | Recovery method |
|---|---|---|---|---|
| Postgres `astronomy-db` | orders, products | **15 min** | **15 min** | `pg_dump` every 15 min → restore |
| Stateless services + all config | none (Git) | **0** | **10 min** | Argo CD re-sync from Git |
| Kafka | in-flight orders | best effort | 10 min | accepted gap (in-memory, P4-ISSUE-8) |
| Valkey | carts | best effort | 10 min | accepted (carts are transient) |

### Backups
[platform/backup/pg-backup.yaml](../../platform/backup/pg-backup.yaml): a CronJob (`*/15`) running `pg_dump -Fc` into a PVC in a **separate `backups`
namespace** (so losing the shop namespace doesn't lose the backups), keeping the newest 10, **synced by Argo CD**. The password lives in a Secret
created by `make backup-secret` (never in Git).
```bash
make backup-secret      # once
make backup-now         # on-demand backup: "backup ok: .../astronomy_db-20260926T180838Z.dump 104K orders=1722"
make db-restore         # scripts/db-restore.sh: restore the newest dump, print the restored order count
```

### The drill: `kubectl delete namespace astronomy-shop` (the "fat finger")
```bash
$TMPDIR/dr-drill.sh     # captured in this guide; delete ns → wait for Argo rebuild → restore DB → measure
```
| t | UTC | Event |
|---|---|---|
| 0 | 18:09:06 | Pre-drill: **1,723 orders**. `kubectl delete namespace astronomy-shop` |
| 49 s | 18:09:55 | Namespace fully deleted |
| 58 s | 18:10:04 | **Argo CD recreates the namespace** (CreateNamespace + selfHeal) |
| 136 s | 18:11:22 | **Stateless recovered:** 37 pods Ready, Argo Synced/Healthy. **DB: orders = 0** (products = 10, re-seeded by the init script) |
| 142 s | 18:11:29 | **Restore** from `astronomy_db-20260926T180838Z.dump` → **1,722 orders** |

| Measure | Target | **Actual** |
|---|---|---|
| Stateless RTO | 10 min | **136 s** ✅ |
| Total RTO (incl. DB restore) | 15 min | **142 s** ✅ |
| RPO | ≤ 15 min of orders | **1 order lost** (placed in the 28 s between the last backup and the disaster) ✅ |
| Without a backup | — | **All 1,723 orders lost** |

### Seeing RPO and RTO: the Grafana dashboard
Dashboard **SRE Lab / Disaster Recovery (RPO & RTO)** ([dr-rpo-rto.json](../../observability/dashboards/dr-rpo-rto.json), synced by Argo CD).
The red dashed lines are Grafana annotations tagged `dr-drill`, one per drill event (commands below).

**The drill window (18:05–18:16 UTC):**

![DR drill: RTO and RPO over the drill window](img-phase9-dr-drill.png)

How to read it:
- **RTO: shop pods Ready.** 37 pods are Ready until the delete (18:09:06). The series then **disappears**: with the namespace gone,
  kube-state-metrics has nothing to report, so the gap *is* the outage. The pods come back at ~18:11 and reach 37/37 Ready at
  18:11:22 (**136 s**). The DB restore marker follows at 18:11:29 (**142 s total**).
- **User impact.** Checkout traffic stops during the outage. The load generator lives **in the deleted namespace**, so it died too:
  the same "monitor inside the blast radius" gap as P8-ISSUE-11 (PRR row 5). After recovery there is a short burst of HTTP 500s.
  The panel counts per 2 min, so it lags the events by about a minute.
- **RPO: backup freshness.** A sawtooth. Backup age climbs linearly and drops to ~0 each time the `*/15` CronJob succeeds (here at 18:15).
  **The worst-case RPO is the peak of the sawtooth.** It must stay under 15 min; the alert threshold is 900 s.
- **Current RPO exposure.** The same number right now. It is green under 15 min, amber at 15–20 min, and red above 20 min
  (a missed backup).

**Steady state (last 3 h):** the drill is the only dip in pods Ready. The RPO gauge reads "7 mins", meaning an incident now would lose
up to 7 minutes of orders.

![DR dashboard, last 3 hours](img-phase9-dr-now.png)

Earlier gaps in the RTO panel (15:30–15:55) are not DR events. They predate the drill.

Adding the drill annotations (Grafana HTTP API; repeat for each event):
```bash
PW=$(make -s grafana-password)
MS=$(python3 -c "import datetime as d;print(int(d.datetime(2026,9,26,18,9,6,tzinfo=d.timezone.utc).timestamp()*1000))")
curl -s -X POST "http://admin:$PW@localhost:8080/grafana/api/annotations" -H 'Content-Type: application/json' \
  -d "{\"time\":$MS,\"tags\":[\"dr-drill\"],\"text\":\"DISASTER: namespace deleted (1,723 orders)\"}"
```
Annotations are stored in Grafana's database, not in Git. If Grafana is rebuilt without persistence, they are gone.
**The durable record of the drill is this document.**

### What the drill taught
1. **Git is the recovery plan for everything stateless.** All 13 PDBs, the canary Rollout, SLO rules, alerts and dashboards came back automatically.
2. **Anything not in Git is lost.** The namespace's Chaos Mesh opt-in annotation (added by hand in `make chaos-up`) **did not come back**.
   Fix: declared in Git via Argo CD `managedNamespaceMetadata` (verified). (P9-ISSUE-1)
3. **Restore order matters.** `pg_restore --clean` replaces tables, so orders written between the rebuild and the restore are wiped (a 7 s window
   here). The right sequence: restore **before** reopening traffic, or pause writers. (P9-ISSUE-2)
4. **Backups here are not off-site.** Same cluster, node-local PV: a cluster or node loss takes the backups too. Production: encrypted,
   versioned object storage in another region, plus regular automated restore tests. (P9-ISSUE-3)

---

## Part 2: Production Readiness Review (the whole lab)

Legend: ✅ ready (evidence) · ⚠️ partial · ❌ not ready

| # | Area | Status | Evidence / gap |
|---|---|---|---|
| 1 | SLOs for every critical user journey, with dashboards | ✅ | 7 SLOs: availability, latency, **correctness** (order integrity), **completeness** (async pipeline); every SLI tested with injected failures ([P1](phase-1-slos.md), [P4](phase-4-incident-response.md)) |
| 2 | Burn-rate alerts with runbooks | ✅ | 19 alerts, all with runbooks (`make check-runbooks`); multi-window burn rates |
| 3 | Alert routing tested | ⚠️ | Routing unit tests 11/11, e2e page 332 s via the alert sink. **Real PagerDuty/Slack not connected** (credentials pending) |
| 4 | Observability: RED/USE, traces↔logs↔metrics, self-monitoring | ✅ | Alert → trace → log < 2 min ([P2](phase-2-observability.md)); pipeline pulled independently |
| 5 | External (outside-in) monitoring | ❌ | Synthetic traffic runs **inside** the blast radius; on AKS it died with the node, so the SLI went blind (P8-ISSUE-11) |
| 6 | Resource limits sized from data | ✅ | cgroup sweep: product-catalog 644k limit hits → fixed; thrashing alert ([P2](phase-2-observability.md)) |
| 7 | Probes, replicas, PDBs, anti-affinity (stateless) | ⚠️ | 13 services: gRPC/TCP probes, 2 replicas, PDBs; node loss 47% → **3.1%** errors. But **preferred** anti-affinity co-located both checkout replicas on AKS (P8-ISSUE-9) |
| 8 | Stateful HA / durability | ❌ | Postgres, Kafka, Valkey: single replica. Kafka in-memory (**~13 orders lost** in P4). Postgres restores from backup only |
| 9 | Autoscaling | ❌ | No HPA; Phase 6 showed CPU is the wrong signal (pool starvation) |
| 10 | Capacity known | ✅ | Knee ~58 req/s, ~4× headroom; bottleneck identified via a trace ([P6](phase-6-capacity.md)) |
| 11 | Overload behaviour | ❌ | Collapse, not graceful degradation: 15 s timeouts, no load shedding (P6-ISSUE-2) |
| 12 | Changes via Git, drift reverted | ✅ | Argo CD self-heal 2 s; CI on every push (render, kubeconform, promtool, routing, links) |
| 13 | Safe releases | ⚠️ | Canary + SLO gate **auto-rolled back** a bad release in ~70 s, but only **after** full exposure: gRPC pinning defeats replica-ratio canaries (P7-ISSUE-7) |
| 14 | Disaster recovery tested | ⚠️ | RTO 142 s / RPO 1 order, **tested** ✅. Backups not off-site ❌ |
| 15 | Incident process | ✅ | Game day, blameless postmortem, 6 action items (5 closed); MTTD tracked. **Blind game day by the owner still pending** |
| 16 | Chaos-tested with hypotheses | ✅ | 5 experiments; hypotheses disproved and confirmed; guardrail (namespace filter) tested |
| 17 | Cost known | ✅ | Local $0; AKS ~$0.31/hr from the retail API; budget alert via Terraform |
| 18 | Zone / region resilience | ❌ | No AZ access on the subscription; single region |

**Verdict:** **Not production-ready. Strong on the operating model, weak on stateful durability and overload.**
- Ready (10): SLOs, alerting logic, observability, limits, capacity knowledge, GitOps/CI, incident process, chaos practice, cost, tested DR.
- Partial (4) / not ready (5): the gaps are concentrated in **stateful HA**, **overload protection**, **outside-in monitoring**, **real paging**, and **zones**.

### Top 5 actions to reach production
| # | Action | Closes |
|---|---|---|
| 1 | Managed or replicated Postgres (and Kafka with persistence, `acks=all`, producer delivery callbacks) + off-site encrypted backups | 8, 14 |
| 2 | External synthetic probe (outside the cluster) feeding an edge SLO | 5 |
| 3 | Fail fast: 1–2 s timeouts on the product-catalog path, Envoy load shedding, fix the DB pool | 9, 11 |
| 4 | L7 traffic routing (service mesh / Rollouts trafficRouting) + a per-version SLI; `required` anti-affinity for CUJ services | 7, 13 |
| 5 | Connect PagerDuty/Slack; run the blind game day; zone-redundant cluster where the subscription allows | 3, 15, 18 |

---

## Issues log
| ID | Area | Symptom | Root cause | Fix |
|---|---|---|---|---|
| P9-ISSUE-1 | DR / GitOps | After the rebuild, the namespace lacked `chaos-mesh.org/inject=enabled` | It was added imperatively (`kubectl annotate`), not in Git | `managedNamespaceMetadata` in the Argo Application; verified |
| P9-ISSUE-2 | DR procedure | Orders written between rebuild and restore would be wiped | `pg_restore --clean` replaces tables | Runbook: restore before reopening traffic / pause writers |
| P9-ISSUE-3 | DR design | Backups share the cluster/node with what they protect | Lab simplification | Production: off-site, encrypted, versioned object storage + scheduled restore tests |
