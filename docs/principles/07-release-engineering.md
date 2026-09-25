# 07: Release Engineering and Change Management

> Most outages are caused by changes. Make changes safe instead of rare.

## Principles
1. **Everything is in version control**: app code, infrastructure, config, dashboards, alerts, SLOs.
2. **Builds are reproducible and hermetic**: the same commit produces the same artifact.
3. **Deploys are declarative** (GitOps): Git is the source of truth, and a controller makes the cluster match it.
4. **Progressive delivery**: expose changes to a small share of traffic first and watch the SLIs.
5. **Rollback is fast and routine**: a rollback shouldn't need a meeting.
6. **Separate deploy from release**: ship code "dark" behind feature flags, then turn it on gradually.

## Deployment strategies

| Strategy | How | Pros | Cons |
|---|---|---|---|
| Recreate | Stop old, start new | Simple | Downtime |
| Rolling update | Replace pods gradually (K8s default) | No downtime, built in | Mixed versions; slow rollback |
| Blue/green | Two full environments, switch traffic | Instant rollback | Double the resources |
| **Canary** | Small % of traffic to the new version, analyze, then increase | Limits blast radius; decisions based on data | Needs good SLIs and traffic splitting |
| Feature flags | Code deployed but off; enabled per user or % | Release is separate from deploy | Flags pile up as debt |

## Change management in SRE
- **Automate the checks** instead of requiring approval boards: CI tests, policy checks, canary analysis.
- **Error budget gates releases**: fast when there's budget, slow when there isn't (see [02](02-error-budgets.md)).
- **Make every change visible**: annotate dashboards with deploys and flag changes, so "what changed?" takes 10 seconds to answer during an incident.
- **Change freezes** happen only under the budget policy or at known high-risk times (e.g. Black Friday).

## Key metrics: DORA
| Metric | Elite target |
|---|---|
| Deployment frequency | On demand (multiple per day) |
| Lead time for changes | < 1 day |
| Change failure rate | 0–15% |
| Time to restore service | < 1 hour |

SRE and DORA agree: **speed and stability go together** when changes are small and automated.

## Mapped to the lab (Phase 7)
- [ ] **Argo CD** watches this repo and syncs `apps/` to the cluster. No more `helm upgrade` by hand.
- [ ] **Argo Rollouts** canary for the `checkout` service: 10% → 30% → 100%, with an `AnalysisTemplate` that queries the checkout SLI and burn rate from Prometheus
- [ ] Break a release on purpose (bad image or an injected failure) and watch the automatic rollback
- [ ] **GitHub Actions**: `helm lint`, `kubeconform`, `promtool check rules`, and a policy check (Kyverno CLI: resource limits and probes required), Trivy, and Checkov for Terraform
- [ ] Grafana annotations for every sync and flag change
- [ ] Treat **flagd flag changes as changes**: keep them in Git and review them. Game-day postmortems will show why.

## Interview questions
1. Compare canary, blue/green, and rolling deployments. When would you choose each?
2. How would you automate canary analysis? What metrics would you use?
3. What is GitOps, and what problem does it solve?
4. How do error budgets relate to release velocity?
5. Explain the DORA metrics.
