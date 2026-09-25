# Roadmap: Learning SRE on the Astronomy Shop

Each phase ends with **exit criteria** and **interview takeaways**, so the lab work
also prepares you for interviews. Aim for about one phase per week.
The concepts behind each phase are explained in [principles/](principles/README.md).
The local-vs-cloud comparison and principle coverage for every phase are in [lab-matrix.md](lab-matrix.md).

---

## Phase 0: Foundation (this commit)
- [x] Repo structure, operating model ([sre-way.md](sre-way.md)), ADR, templates
- [x] Bring up the kind cluster and deploy the shop (`make cluster-up deploy open`)
- [x] Walk through the app: browse, add to cart, check out. Open Grafana, Jaeger, and the flag UI.
- [x] Draw the service dependency map from Jaeger (`docs/architecture.md`)

📘 **Execution guide:** [labs/phase-0-foundation.md](labs/phase-0-foundation.md), with every command, output, and issue (done 2026-09-25)

**Exit:** the shop runs, and you can trace one checkout request end to end.
**Interview:** "Walk me through what happens when a user clicks *Place order*."

## Phase 1: SLIs & SLOs
- [x] Pick 3 critical user journeys: **browse catalog**, **add to cart**, **checkout**
- [x] Define availability and latency SLIs (at the frontend server spans; Envoy spans carry no route)
- [x] Write SLO specs in `slos/`, then generate the rules with [Sloth](https://sloth.dev)
- [x] Error-budget dashboard in Grafana
- [x] Test the SLI with an injected failure (`paymentFailure`): a blind spot was found and fixed

📘 **Execution guide:** [labs/phase-1-slos.md](labs/phase-1-slos.md), with 18 edge cases logged (done 2026-09-25)

**Exit:** each journey shows its SLI, target, and remaining budget.
**Interview:** SLI vs SLO vs SLA; why not 100%; how to choose a target.

## Phase 2: Observability platform
- [ ] Replace the bundled stack with **kube-prometheus-stack** (Prometheus, Alertmanager, Grafana), plus **Loki** for logs and **Tempo** for traces
- [ ] RED dashboards per service, a USE dashboard for nodes, and a golden-signals overview
- [ ] Link from metrics to traces (exemplars) and from traces to logs

**Exit:** go from an alert → dashboard → trace → log line in under 2 minutes.
**Interview:** RED vs USE, the four golden signals, cardinality problems.

## Phase 3: Alerting & on-call
- [ ] Multi-window, multi-burn-rate SLO alerts (from Phase 1)
- [ ] Alertmanager routing: page vs ticket, grouping, inhibition, silences
- [ ] A runbook for every paging alert in `runbooks/`
- [ ] Route pages to **PagerDuty** (free plan) with an escalation policy, mirrored to Slack `#pages`; tickets to Slack `#alerts`

**Exit:** every page is symptom-based, actionable, and links to a runbook.
**Interview:** alert fatigue, and why to alert on burn rate rather than thresholds.

## Phase 4: Incident response game days
Use flagd flags to inject real failures and run each one as a full incident, with IC, timeline, and postmortem:
- [ ] `paymentFailure`: checkout errors
- [ ] `productCatalogFailure`: errors on one product
- [ ] `adHighCpu` / `adManualGc`: latency and saturation
- [ ] SLI-data-missing alert (`absent()`), found necessary in Phase 1 (P1-ISSUE-16)
- [ ] `kafkaQueueProblems`: async backlog and consumer lag
- [ ] `recommendationCacheFailure`: a memory leak
- [ ] `loadGeneratorFloodHomepage`: a traffic spike

Write a postmortem in `postmortems/` for each one.
**Exit:** 5+ postmortems. Measure MTTD and MTTR for each and watch them improve.
**Interview:** "Tell me about an incident you handled." You'll have real ones to talk about.

## Phase 5: Chaos engineering & resilience
- [ ] Install **Chaos Mesh**
- [ ] Experiments with a hypothesis: pod kill, node drain, network latency and packet loss, DNS failure
- [ ] Add PodDisruptionBudgets, readiness and liveness probes, resource requests and limits, HPA, and retries with timeouts where they're missing

**Exit:** the checkout SLO holds through the loss of one node.
**Interview:** cascading failures, retries vs retry storms, circuit breakers, graceful degradation.

## Phase 6: Capacity & performance
- [ ] Load test with **k6** (Locust keeps running as background traffic); find the saturation point of the checkout path
- [ ] Tune HPAs from the results and write a capacity plan

**Interview:** Little's Law, headroom, and forecasting.

## Phase 7: Release engineering & GitOps
- [ ] Manage all manifests with **Argo CD**
- [ ] **Argo Rollouts** canary with automated analysis on SLIs; roll back automatically on budget burn
- [ ] CI with GitHub Actions: lint, kubeconform, and policy checks

**Interview:** deployment strategies, and how error budgets gate releases.

## Phase 8: Infrastructure as Code & cloud
- [ ] Terraform an **EKS** cluster (3 nodes across 3 AZs, Karpenter, Spot workers; see [ADR-0002](adr/0002-cloud-provider.md)); optionally one comparison session on AKS; run `terraform destroy` after each session
- [ ] Deploy the **same repo** there: the SLOs, alerts, dashboards, and runbooks move over unchanged
- [ ] Run the cloud-only scenarios: AZ outage (AWS FIS), cluster-autoscaler lag, managed-dependency failover, large load test, IAM/quota failure
- [ ] Measure cost against reliability trade-offs (what would one more nine cost?)

See [lab-matrix.md](lab-matrix.md) for what each phase covers locally vs in the cloud.

## Phase 9: Disaster recovery & production readiness (capstone)
- [ ] Define **RPO/RTO** for stateful parts (cart in Valkey, Kafka orders, any database)
- [ ] Back up and **test a restore** with Velero (local: to MinIO; cloud: to S3/GCS). An untested backup doesn't count
- [ ] DR drill: delete the whole namespace (local) or cluster (cloud) and rebuild from Git and backups, timing it against the RTO
- [ ] Complete the [Production Readiness Review](principles/09-culture-oncall.md#production-readiness-review-checklist-use-it-on-the-astronomy-shop) checklist and write up the gaps

**Exit:** the shop can be rebuilt from nothing within the RTO, and the PRR is green.
**Interview:** RPO vs RTO, backup vs DR, "how would you recover from losing a region?"

## Ongoing: Interview prep (`interviews/`)
- SRE fundamentals Q&A, Linux and networking troubleshooting, system design with a reliability focus
- A STAR story for each postmortem you write
