# Phase 7: Release Engineering, CI and GitOps (Execution Guide)

> **Goal:** every change is validated automatically and reaches the cluster only through Git.
> **Principles:** [07 Release engineering](../principles/07-release-engineering.md), [06 Toil](../principles/06-toil-automation.md).
> **Status (2026-09-26):** CI ✅ · Argo CD GitOps ✅ (self-heal in 2 s) · **Canary ✅: a bad release was rolled back automatically in ~70 s** (after the first design promoted one).

## Part 1: CI (GitHub Actions = `make ci`, the same script)
[scripts/ci.sh](../../scripts/ci.sh) · [.github/workflows/ci.yml](../../.github/workflows/ci.yml)

| Stage | What it catches |
|---|---|
| Render every chart with our values | schema violations, bad values, template errors |
| kubeconform (CRD schemas via datree catalog) | invalid manifests: **225 resources valid** |
| Regenerate SLO rules, `git diff --exit-code` | generated rules out of sync with `slos/` |
| promtool | invalid alert rules |
| `check-runbooks` + `test-alert-routing` | alerts without runbooks; routing regressions |
| Link check + dashboard JSON | broken docs, invalid dashboards |

**It took 3 runs to go green, and each failure was a real Linux-vs-macOS bug** that Docker Desktop hides:
1. The Sloth container (non-root) **couldn't write** to the runner workspace → `--user $(id -u):$(id -g)`
2. Tool containers **couldn't read** `mktemp -d` dirs (mode 700) → `chmod 755`
3. (locally) Chaos Mesh CRDs are **not in the public schema catalog** → structure-only check for `chaos/` (known gap)

## Part 2: GitOps with Argo CD
```bash
make argocd-up        # Argo CD 3.5.3 (chart 10.9.2) + gitops/apps/*
make argocd-status
```
| Application | Source | Contents |
|---|---|---|
| `astronomy-shop` | [apps/astronomy-shop](../../apps/astronomy-shop/kustomization.yaml) (Kustomize + Helm inflation) | the shop |
| `sre-lab-config` | directory include | platform alerts, SLO PrometheusRules, Alertmanager routing + alert-sink, PodMonitor, PDBs |
| `sre-lab-dashboards` | [observability/dashboards](../../observability/dashboards/kustomization.yaml) (`configMapGenerator`) | Grafana dashboards |

All three: `automated: {prune: true, selfHeal: true}`.

**Key design change: Kustomize replaced the Helm post-renderer.** Argo CD doesn't support post-renderers. The chart is now inflated by
Kustomize and the gRPC/TCP probes are standard patches ([patches/probes.yaml](../../apps/astronomy-shop/patches/probes.yaml)).
Before switching, both render paths were compared: **0 of 52 objects differ semantically** (after normalising YAML anchors and null fields).
`make deploy` is now only a bootstrap/fallback path.

**Self-heal proof:** `kubectl scale deploy/checkout --replicas=1` → **reverted to 2 by Argo CD in 2 s**. The manual-drift class of
problem (P3-ISSUE-8) is gone.

## Part 3: Canary releases with Argo Rollouts (SLO-gated)
```bash
make rollouts-up        # Argo Rollouts 1.10.0 (chart 2.43.2)
make rollout-status
```
[apps/astronomy-shop/rollout-checkout.yaml](../../apps/astronomy-shop/rollout-checkout.yaml): a `Rollout` that **references** the chart's
checkout Deployment (`workloadRef`, `scaleDown: progressively`, a zero-downtime takeover), plus an `AnalysisTemplate` using the
**same SLI as the checkout SLO** (5xx/422 ratio < 5%). Argo CD ignores the Deployment's replicas (`RespectIgnoreDifferences`)
so selfHeal doesn't fight the Rollout.

**Test method:** ship a deliberately bad release **through Git** (checkout → `payment:9999`) and let the system react.

### Attempt 1: the gate PROMOTED a bad release ❌
Design: 50% → 2 min → analysis → 100%. The analysis measured `0, 0, NaN` → **Successful** → promoted.
Then **~89% of payment calls failed for ~2 min** (04:54–04:56) until a GitOps revert was forced through (`promoteFull`).
**Root cause:** the frontend→checkout calls are **gRPC over long-lived HTTP/2 connections**, and Service load balancing is **per
connection**, so the "50% canary" pod got **~0% of requests**. Traffic only moved when the stable pods terminated,
**after** the gate had already passed. Replica-ratio canaries don't split gRPC traffic.

### Attempt 2: background analysis through a post-100% soak ✅
Design: **background analysis from step 1**, 50% → 2 min → 100% → **3-min soak while still abortable**; interval 30 s, failureLimit 1.

| Time (UTC) | Event |
|---|---|
| 04:59:34 | Bad canary pod up (50%) |
| 04:59:39–05:01:39 | Analysis **0%, 0%, 0%, 0%, 0%**: confirms the canary gets no traffic at 50% |
| 05:01:54 | 100%: stable pods terminate, connections move to the bad pods |
| 05:02:09, 05:02:39 | Analysis **100%, 100%** → 2 failures > limit 1 |
| **05:02:42** | **`RolloutAborted`: automatic rollback** |
| **05:03:03** | Good pods restored. **Customer exposure ≈ 70 s, no human involved** |

Then Git was reverted too (the Rollout stays `Degraded` while Git still declares the bad version: GitOps means fixing it in Git).

**Remaining gap / proper fix:** per-request L7 traffic splitting (service mesh or Rollouts `trafficRouting`) so the canary really
takes 50% **before** full exposure, plus a per-version SLI (span metrics currently carry no pod/version label).

## Issues log
| ID | Area | Symptom | Root cause | Fix |
|---|---|---|---|---|
| P7-ISSUE-1 | CI | `permission denied` writing rules on the Linux runner | Non-root Sloth container vs runner-owned workspace (hidden by Docker Desktop) | `--user $(id -u):$(id -g)` |
| P7-ISSUE-2 | CI | promtool/amtool `stat ... permission denied` | `mktemp -d` is mode 700; tool containers run non-root | `chmod 755` temp dirs |
| P7-ISSUE-3 | CI | kubeconform: no schema for `PodChaos` | Chaos Mesh CRDs are missing from the public catalog | Structure-only check for `chaos/`; later: vendor schemas from the CRDs |
| P7-ISSUE-4 | GitOps | Argo CD can't use the Helm post-renderer | Not supported by Argo CD | Kustomize helm inflation + patches; semantic diff = 0 before switching |
| **P7-ISSUE-5** | **Repo hygiene** | Kustomize downloaded the whole chart into `apps/astronomy-shop/charts/`, which **would have been committed** by the next `git add -A` | helm-inflation cache inside the repo | `.gitignore: apps/*/charts/`; link checker skips vendored charts. The link checker is what surfaced it |
| P7-ISSUE-6 | GitOps | `sre-lab-config` permanently OutOfSync on the PodMonitor | The CRD defaults `action: replace` into relabelings; Git didn't have it | State the default explicitly in Git (preferred over `ignoreDifferences`, which would hide real drift) |
| **P7-ISSUE-7** | **Release safety** | The canary analysis passed (`0, 0, NaN`) and **promoted a bad release**; ~89% payment failures for ~2 min | gRPC connection pinning: the Service balances per connection, so the canary got ~0% traffic; the gate ran before any real exposure | Background analysis spanning a post-100% abortable soak. Re-test: **auto-rollback in ~70 s**. Proper fix: L7 traffic routing |
| P7-ISSUE-8 | Process | Test #2 commit failed to render: `patches/bad-release.yaml: no such file` | `git revert` had deleted the patch file; only the reference was re-added | **CI failed the commit and Argo CD refused to sync** (ComparisonError) → nothing broken deployed. Defense in depth caught my mistake |
