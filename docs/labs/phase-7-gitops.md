# Phase 7: Release Engineering, CI and GitOps (Execution Guide)

> **Goal:** every change is validated automatically and reaches the cluster only through Git.
> **Principles:** [07 Release engineering](../principles/07-release-engineering.md), [06 Toil](../principles/06-toil-automation.md).
> **Status (2026-09-26):** CI ✅ · Argo CD GitOps ✅ (3 apps Synced/Healthy, self-heal proven) · Argo Rollouts canary: next.

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

## Issues log
| ID | Area | Symptom | Root cause | Fix |
|---|---|---|---|---|
| P7-ISSUE-1 | CI | `permission denied` writing rules on the Linux runner | Non-root Sloth container vs runner-owned workspace (hidden by Docker Desktop) | `--user $(id -u):$(id -g)` |
| P7-ISSUE-2 | CI | promtool/amtool `stat ... permission denied` | `mktemp -d` is mode 700; tool containers run non-root | `chmod 755` temp dirs |
| P7-ISSUE-3 | CI | kubeconform: no schema for `PodChaos` | Chaos Mesh CRDs are missing from the public catalog | Structure-only check for `chaos/`; later: vendor schemas from the CRDs |
| P7-ISSUE-4 | GitOps | Argo CD can't use the Helm post-renderer | Not supported by Argo CD | Kustomize helm inflation + patches; semantic diff = 0 before switching |
| **P7-ISSUE-5** | **Repo hygiene** | Kustomize downloaded the whole chart into `apps/astronomy-shop/charts/`, which **would have been committed** by the next `git add -A` | helm-inflation cache inside the repo | `.gitignore: apps/*/charts/`; link checker skips vendored charts. The link checker is what surfaced it |
| P7-ISSUE-6 | GitOps | `sre-lab-config` permanently OutOfSync on the PodMonitor | The CRD defaults `action: replace` into relabelings; Git didn't have it | State the default explicitly in Git (preferred over `ignoreDifferences`, which would hide real drift) |
