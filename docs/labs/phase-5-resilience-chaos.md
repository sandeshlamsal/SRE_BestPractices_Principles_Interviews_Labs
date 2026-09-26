# Phase 5: Resilience and Chaos Engineering (Execution Guide)

> **Goal:** find where the system is actually fragile, using **hypothesis-driven experiments with abort conditions**,
> then harden it and **prove** the improvement by re-running the same experiment.
> **Principles practiced:** [08 Capacity, resilience & chaos](../principles/08-capacity-resilience-chaos.md), [01 SLIs](../principles/01-sli-slo-sla.md), [02 Error budgets](../principles/02-error-budgets.md).
> **Method:** measure → hypothesize → inject (small blast radius) → observe at the **edge** → learn → harden → re-run.

---

## Step 1: Resilience baseline (measure before changing anything)

```bash
kubectl -n astronomy-shop get deploy,sts -o json | python3 -c "..."   # full script in the commit history of this guide
```
| Control (22 shop workloads) | Count |
|---|---|
| Replicas > 1 | **0** |
| Readiness / liveness probes | **0 / 0** |
| PodDisruptionBudgets | **0** |
| Topology spread / anti-affinity | **0** |
| Persistent storage | **0**: Kafka *and* Postgres `astronomy-db` lose all data on restart |
| Memory requests set | 2 |
| Placement | **15 pods on `sre-lab-worker`, 9 on `sre-lab-worker2`** |

What the demo chart can express per component (from `helm pull` + reading `templates/_objects.tpl`): `replicas`,
`readinessProbe`, `livenessProbe`, `schedulingRules.affinity/nodeSelector/tolerations`, `additionalVolumes`. **No
PodDisruptionBudget or topologySpreadConstraints**, so PDBs become separate manifests and spreading uses pod anti-affinity.

## Step 2: Chaos Mesh, with a blast-radius guardrail

[platform/chaos-mesh/values.yaml](../../platform/chaos-mesh/values.yaml), chart **2.8.4**:
- `chaosDaemon.runtime: containerd`, `socketPath: /run/containerd/containerd.sock` (kind uses containerd; the chart defaults to Docker)
- `controllerManager.enableFilterNamespace: true`: **only namespaces annotated `chaos-mesh.org/inject=enabled` can be targeted** (only `astronomy-shop`)
- Dashboard off: experiments are YAML in Git ([chaos/](../../chaos/))
```bash
make chaos-up      # 31 s
```
**Test the guardrail** (a guardrail you haven't tested is only a hope): a `PodChaos` targeting `alert-sink` in `observability`
→ `Selected=False`, the pod survived ✓.

## Step 3: Experiments

Runner: [scripts/chaos-run.sh](../../scripts/chaos-run.sh) `<experiment.yaml> <route regex> <component> [observe_s]`, which
refuses to run during a game day, applies the experiment, waits for recovery (aborts after 5 min), and reports HTTP status codes.

### Exp 01: kill the `cart` pod ([yaml](../../chaos/exp-01-cart-pod-kill.yaml))
**Hypothesis:** 1 replica, no readiness → add-to-cart fails until the new pod serves.
**Result: disproved.** 117/117 × 200; the pod was "Ready" after 3 s.
**But:** with **no readiness probe, Ready just means "the container started"**, not "the app can serve". The number is meaningless (P5-ISSUE-1).

### Exp 02: kill the `frontend` pod ([yaml](../../chaos/exp-02-frontend-pod-kill.yaml))
**Hypothesis:** every journey fails until Next.js serves.
**Result: disproved, and it exposed a measurement blind spot.**
- The frontend's own spans: 486 × 200, **0 errors**. **A dead service emits no spans**, so our SLIs (measured at the frontend) **cannot see the frontend being down** (P5-ISSUE-2).
- Measured at the **edge** (Envoy `frontend-proxy`, 3-min window): **0.00% failures** (2,625 × 200) vs **0.06%** in a control window. Next.js restarts in ~1 s.
- A query with `increase(...[60s])` returned **empty**: span metrics arrive about every 60 s, and `increase()` needs 2 samples. **Empty ≠ zero** (P5-ISSUE-3).

**Conclusion from 01–02:** this system restarts single pods in seconds, so **pod death isn't where it's fragile.**
Redundancy for pod-kill alone wouldn't have changed the outcome. The risk is **node loss** (15/24 pods on one node, nothing replicated).

### Exp 03: node failure ([script](../../chaos/exp-03-node-failure.sh)), the real weakness
**Target:** `sre-lab-worker` hosted the **entire checkout path** (checkout, cart, payment, product-catalog, quote, email, flagd,
Postgres `astronomy-db`, accounting), **plus the pager (`alert-sink`)**, and Loki and Tempo (volumes pinned to the node).
Default tolerations: `node.kubernetes.io/unreachable` and `not-ready` = **300 s**.

**Hypothesis:** pods stranded ~5–6 min → checkout/cart/browse fail; pages fire but the **pager (same node) can't deliver**;
Loki/Tempo can't move; `astronomy-db` restarts **empty** (no PVC). **Abort:** restart the node at t+480 s.
```bash
chaos/exp-03-node-failure.sh      # docker stop sre-lab-worker; timeline every 30 s; docker start at t+480
```
**Result: every part of the hypothesis held.**

| t (s) | UTC | Event |
|---|---|---|
| 0 | 03:36:16 | `docker stop sre-lab-worker` |
| 62 | 03:37:18 | Node `NotReady` |
| 107 | 03:38:03 | Edge failures (Envoy 5xx/connection errors, 3-min window) **20%** |
| 174–343 | | Edge failures **42–47%**: about half of all user requests failing |
| **184–204** | 03:39:20–40 | 🚨 Browse, Cart, Checkout **pages become active** in Prometheus/Alertmanager |
| ~340 | 03:42 | 300 s toleration expires → pods evicted, 10 Pending → rescheduled to worker2 |
| **368–413** | 03:42:24–03:43:09 | **The pager receives the pages: a ~3-min delivery delay**, because `alert-sink` was on the dead node |
| 376 | 03:42:32 | Postgres `astronomy-db` restarts on worker2, **with no volume** |
| 437 | 03:43:33 | All shop pods Running/Ready again (on one node) |
| 480 | 03:44:16 | Node restored (independent safety timer) |
| 604 | 03:46:20 | 🚨 **`OrderPipelineCompleteness` pages**: orders lost with the node's Kafka/accounting |
| ~650 | 03:47 | Edge failures back to **0%**; Loki and Tempo back (only once the node returned) |

**Findings:**
1. **~8 minutes at ~45% user-facing failure** from losing 1 of 2 worker nodes. Nothing was replicated, and the 300 s toleration left dead pods "Running" for over 5 minutes.
2. **The pager shared the failure domain.** Pages were active at 03:39 but delivered at 03:42–03:43. *Is your alerting on the infrastructure it monitors?* (Production: an external pager plus a dead-man's switch.)
3. **Permanent data loss:** Postgres came back empty. **`accounting.order` = 8 rows, all placed after the restart; ~17 h of order history gone.** The product catalog only survived because an init script re-seeds it. Pod status showed Running/Ready throughout.
4. **Stateful pods with node-local volumes can't fail over** (Loki, Tempo): logs and traces were lost for the outage window, exactly when you'd need them.
5. The completeness SLO (Phase 4) **caught the downstream order loss**, as designed.

Evidence commands:
```bash
kubectl -n observability logs deploy/alert-sink --since=20m | grep '"page"'      # firing startsAt vs received
kubectl -n astronomy-shop exec deploy/astronomy-db -- psql -U postgres -d astronomy_db -tAc "select count(*) from accounting.order"
kubectl -n astronomy-shop exec deploy/astronomy-db -- psql -U postgres -tAc "select pg_postmaster_start_time()"
```

## Step 4: Hardening, then re-run the same experiment

| Change | Where | Finding it addresses |
|---|---|---|
| `replicas: 2` + preferred pod anti-affinity, 13 critical services | [values-resilience.yaml](../../apps/astronomy-shop/values-resilience.yaml) | P5-ISSUE-4 |
| Unreachable/not-ready tolerations **30 s** (default 300 s) | same | P5-ISSUE-4 |
| Readiness + liveness probes: **gRPC** for 7 services (verified `SERVING` with grpc-health-probe), TCP for 6 HTTP services | [postrender.yaml](../../apps/astronomy-shop/postrender.yaml) via [helm-postrender.py](../../scripts/helm-postrender.py) | ISSUE-6, P5-ISSUE-1 |
| PodDisruptionBudgets `minAvailable: 1` | [pdbs.yaml](../../platform/resilience/pdbs.yaml) (`make resilience`) | voluntary disruptions |
| Pager: 2 replicas, **required** anti-affinity, `maxSurge 0` | [alert-sink.yaml](../../observability/alerting/alert-sink.yaml) | P5-ISSUE-5 |

Verified after `make deploy` (revision 8): **13/13 services with 2 ready replicas on different nodes**; pager on both nodes; PDBs allow 1.

### Exp 03b: node failure again, AFTER hardening (04:08:16 UTC, 5 min)
| | Before | **After** |
|---|---|---|
| Peak edge failures | **47%** | **3.1%** |
| Error duration | ~8 min | **~2.5 min** (endpoint removal after NotReady), 0% from t+216 s |
| New pages | Browse, Cart, Checkout | **none** |
| Pods stranded | 10 for ~6 min | 1 (Loki/Tempo: node-pinned volume) |

**Result: hypothesis confirmed.** Losing a node went from a SEV1-class outage to a blip.
Caveat: 3 pages were still firing from Exp 03 (their windows hadn't cleared), so only *new* pages were judged.

### Still open (next step)
All stateful singletons (valkey-cart, flagd, Kafka, Postgres, accounting) now sit on `sre-lab-worker2`. **Losing that node
would still cause the Exp 03 outage and data loss.** Next: Postgres and Kafka persistence (`strategy: Recreate` via the
post-renderer), a replicated flagd, and a node-failure test on worker2.

---

## Issues log
| ID | Area | Symptom | Root cause | Fix / decision |
|---|---|---|---|---|
| P5-ISSUE-1 | Probes | "cart Ready after 3 s" | No readiness probe: Ready = container started, not app serving | Readiness probes (hardening step) |
| **P5-ISSUE-2** | **SLI blind spot** | Frontend killed; frontend-measured SLIs showed 0 errors | A dead service emits no spans; failures happen at the edge (Envoy) | **Edge SLI** at `frontend-proxy` (status code dimension) |
| P5-ISSUE-3 | Query | `increase(...[60s])` returned empty | Span metrics arrive ~60 s apart; a window needs ≥ 2 samples | Windows ≥ 3× the sample interval |
| **P5-ISSUE-4** | **Single failure domain** | Losing 1 of 2 workers → ~45% of user requests failing for ~8 min | Replicas = 1 everywhere, 15/24 pods on one node, 300 s unreachable toleration | Hardening: replicas + anti-affinity across nodes, PDBs, a shorter toleration for stateless pods |
| **P5-ISSUE-5** | **Pager in the blast radius** | Pages active 03:39, delivered 03:42–03:43 | `alert-sink` ran on the failed node | Pager with 2 replicas across nodes; production: an external pager + dead-man's switch |
| **P5-ISSUE-6** | **Data loss** | Postgres rescheduled empty: ~17 h of `accounting.order` lost | No PVC on `astronomy-db` (chart default) | Persistent volume. On single-node-pinned local storage that trades durability for availability; the real answer is replicated/managed storage (Phase 8/9) |
| P5-ISSUE-7 | Observability | Logs and traces lost for the outage window | Loki/Tempo single replica on node-local PVs can't reschedule | Accept locally; production: object storage + replicas |
| P5-ISSUE-8 | Experiment safety | The abort (`docker start`) was inside a loop that could hang on `kubectl logs` for a dead node | Abort depended on the broken component | **Independent safety timer.** An abort must never depend on what you broke |
| P5-ISSUE-9 | Chart | gRPC/TCP probes rejected: "additional properties 'grpc' not allowed" | The demo chart's values schema only allows `httpGet` probes | **Post-renderer** (keeps schema validation for everything else; `--skip-schema-validation` would disable it all) |
| P5-ISSUE-10 | Rollout | Pager with 2 replicas + *required* anti-affinity on 2 nodes would deadlock | The default rollout surges a 3rd pod that fits nowhere | `maxSurge: 0, maxUnavailable: 1` |
