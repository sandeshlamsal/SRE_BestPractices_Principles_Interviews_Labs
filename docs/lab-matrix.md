# Lab Matrix: Phases × Local vs Cloud × SRE Principles

This page answers three questions:
1. **What do I do in each phase**, locally and in the cloud?
2. **Which SRE principles does each phase practice?**
3. **Is anything missed**, and where is it covered?

Legend: ✅ fully practiced · ⚠️ simulated or partial · ❌ not possible · — not applicable

---

## 1. How the lab progresses

```
 LOCAL (kind, free, daily practice)                                      CLOUD (EKS/GKE, short sessions)
 ─────────────────────────────────────────────────────────────────────   ─────────────────────────────
 P0 Run it ─► P1 SLOs ─► P2 Observe ─► P3 Alert ─► P4 Incidents ─►        P8 Same repo on cloud
                                                    │                        + cloud-only failures
                                  P7 GitOps ◄─ P6 Capacity ◄─ P5 Chaos       │
                                      │                                      ▼
                                      └────────────────────────────────► P9 DR + readiness review
                                                                            (local drill + cloud drill)
 Maturity:  "it runs" → "we measure" → "we see" → "we get paged" → "we respond" → "we harden" → "we ship safely" → "we survive infra loss" → "production-ready"
```

---

## 2. Phase by phase: local vs cloud

| Phase | Local lab (kind) | Cloud extension (EKS/GKE) | What only the cloud adds |
|---|---|---|---|
| **P0 Foundation** | 3-node kind cluster, deploy the shop, trace one checkout | Terraform cluster in 3 AZs, same Helm chart | Real nodes in separate zones, a managed control plane, cloud networking |
| **P1 SLIs & SLOs** | Baseline SLIs, Sloth specs, budget dashboard | Same specs, unchanged, plus an SLI from the **cloud load balancer** | An edge SLI measured by the load balancer, closer to the user |
| **P2 Observability** | kube-prometheus-stack, Tempo, Loki, RED/USE dashboards | Same stack, with long-term storage in S3/GCS; cloud metrics (CloudWatch / Cloud Monitoring) | Observability for managed services, storage costs, retention trade-offs |
| **P3 Alerting & on-call** | Burn-rate alerts → Slack/Discord, runbooks | Same alerts, plus **uptime checks from outside** (e.g. multiple regions) | Detecting failures from outside the network you're monitoring |
| **P4 Incident response** | Game days triggered by flags (payment, CPU, leak, Kafka, traffic) | Game days on **infrastructure** failures: AZ loss, a failed node group, expired credentials | Incidents with real cloud causes, and cloud console/CLI debugging under pressure |
| **P5 Chaos & resilience** | Chaos Mesh: pod kill, latency, packet loss, `docker stop` a node | Terminate a real EC2/GCE instance, **take down one AZ**, get Spot/Preemptible interruptions | Real node death, rescheduling across zones, re-attaching persistent volumes |
| **P6 Capacity** | k6/Locust up to what the laptop can handle; HPA tuning | Large load test, **cluster autoscaler** adding nodes, capacity with one AZ gone (N−1) | The minutes it takes to add a node, quotas, costs rising with traffic |
| **P7 Release engineering** | Argo CD + Argo Rollouts canary with SLI analysis | The same Argo apps pointed at the cloud cluster; promote staging → prod | Promoting between clusters, the cloud load balancer splitting canary traffic |
| **P8 IaC & cloud** | — (Terraform can be checked locally with `plan` and linting) | The whole cloud column above, run as 3–5 sessions of about 4 hours | IAM, VPC, quotas, cost vs reliability |
| **P9 DR & readiness** | Velero backup to MinIO; delete the namespace and restore; time it against the RTO | Velero to S3/GCS; **rebuild the whole cluster** from Terraform + Git + backups | Real restores from object storage, cross-region DR design |

---

## 3. SRE principle coverage

Each principle, which phase covers it, and whether local alone is enough.

| SRE principle | Principle doc | Phase(s) | Local | Cloud | Local enough? |
|---|---|---|---|---|---|
| Embrace risk (not 100%) | [01](principles/01-sli-slo-sla.md) | P1 | ✅ | ✅ | ✅ Yes |
| SLIs / SLOs / SLAs | [01](principles/01-sli-slo-sla.md) | P1 | ✅ | ✅ | ✅ Yes |
| Error budgets & budget policy | [02](principles/02-error-budgets.md) | P1, P3, P7 | ✅ | ✅ | ✅ Yes (30d windows are more meaningful in the cloud) |
| Monitoring & observability | [03](principles/03-monitoring-alerting.md) | P2 | ✅ | ✅ | ✅ Yes |
| Symptom-based alerting | [03](principles/03-monitoring-alerting.md) | P3 | ✅ | ✅ | ✅ Yes |
| Outside-in / synthetic monitoring | [03](principles/03-monitoring-alerting.md) | P3 | ⚠️ | ✅ | ⚠️ Needs probes outside the cluster |
| Incident management | [04](principles/04-incident-management.md) | P4 | ✅ | ✅ | ✅ Yes |
| Blameless postmortems | [05](principles/05-postmortems.md) | P4+ | ✅ | ✅ | ✅ Yes |
| Toil elimination & automation | [06](principles/06-toil-automation.md) | Ongoing, P7, P8 | ✅ | ✅ | ✅ Yes |
| Release engineering / progressive delivery | [07](principles/07-release-engineering.md) | P7 | ✅ | ✅ | ✅ Yes |
| Infrastructure as code | [07](principles/07-release-engineering.md) | P8 | ⚠️ | ✅ | ❌ Needs the cloud |
| Resilience patterns (timeouts, retries, PDBs) | [08](principles/08-capacity-resilience-chaos.md) | P5 | ✅ | ✅ | ✅ Yes |
| Chaos engineering (app level) | [08](principles/08-capacity-resilience-chaos.md) | P5 | ✅ | ✅ | ✅ Yes |
| Chaos engineering (infra: node, AZ) | [08](principles/08-capacity-resilience-chaos.md) | P5, P8 | ⚠️ | ✅ | ❌ Needs the cloud |
| Capacity planning & load testing | [08](principles/08-capacity-resilience-chaos.md) | P6 | ⚠️ | ✅ | ⚠️ Methods yes, scale no |
| Autoscaling (pods) | [08](principles/08-capacity-resilience-chaos.md) | P6 | ✅ | ✅ | ✅ Yes |
| Autoscaling (nodes) | [08](principles/08-capacity-resilience-chaos.md) | P6, P8 | ❌ | ✅ | ❌ Needs the cloud |
| Disaster recovery (RPO/RTO, restore) | [ROADMAP P9](ROADMAP.md#phase-9-disaster-recovery--production-readiness-capstone) | P9 | ⚠️ | ✅ | ⚠️ Restore yes, region loss no |
| Simplicity | [09](principles/09-culture-oncall.md) | Ongoing (ADRs) | ✅ | ✅ | ✅ Yes |
| Sustainable on-call | [09](principles/09-culture-oncall.md) | P3, P4 | ✅ | ✅ | ✅ Yes |
| Production readiness review | [09](principles/09-culture-oncall.md) | P9 | ✅ | ✅ | ✅ Yes |
| Cost vs reliability | [environments](environments-and-sizing.md) | P8 | ❌ | ✅ | ❌ Needs the cloud |
| Security basics (least privilege, secrets, policy) | — | P7 (policy), P8 (IAM) | ⚠️ | ✅ | ⚠️ Partial |

**Summary:** of 23 principles, 15 are fully covered locally and 4 are partial (outside-in monitoring,
capacity at scale, DR, security). Another 4 need the cloud: IaC, infrastructure chaos, node
autoscaling, and cost. P8 and P9 finish the partial ones. **Nothing is left out** as long as P8 and P9 are done.

---

## 4. Principles × phases heat map

```
                          P0  P1  P2  P3  P4  P5  P6  P7  P8  P9
Embrace risk / SLOs        ·   ●   ○   ○   ○   ·   ·   ○   ○   ○
Error budgets              ·   ●   ○   ●   ●   ○   ·   ●   ○   ·
Observability              ○   ○   ●   ○   ●   ○   ○   ○   ○   ·
Alerting / on-call         ·   ·   ·   ●   ●   ○   ·   ·   ○   ·
Incident response          ·   ·   ·   ○   ●   ●   ·   ○   ●   ●
Postmortems                ·   ·   ·   ·   ●   ●   ○   ○   ●   ●
Toil / automation          ●   ○   ○   ○   ○   ·   ·   ●   ●   ●
Release engineering        ·   ·   ·   ·   ·   ·   ·   ●   ○   ·
Resilience / chaos         ·   ·   ·   ·   ○   ●   ○   ○   ●   ●
Capacity                   ·   ·   ·   ·   ·   ○   ●   ·   ●   ·
IaC / cost                 ○   ·   ·   ·   ·   ·   ·   ○   ●   ●
DR / readiness             ·   ·   ·   ·   ·   ·   ·   ·   ○   ●

● main focus   ○ practiced or reinforced   · not covered
```

---

## 5. Suggested schedule

| Weeks | Phase | Where | Cloud budget |
|---|---|---|---|
| 1 | P0 Foundation | Local | $0 |
| 2 | P1 SLOs | Local | $0 |
| 3 | P2 Observability | Local | $0 |
| 4 | P3 Alerting | Local | $0 |
| 5–6 | P4 Incident game days | Local | $0 |
| 7 | P5 Chaos | Local | $0 |
| 8 | P6 Capacity | Local | $0 |
| 9 | P7 GitOps & canary | Local | $0 |
| 10–11 | P8 Cloud sessions (P0–P7 repeated + cloud-only scenarios) | Cloud | ~$10–20 |
| 12 | P9 DR drill + PRR | Local, then cloud | ~$5 |

Total cloud cost for the whole program: **about $15–25**, as long as you tear everything down after each session.
