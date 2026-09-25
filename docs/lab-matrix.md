# Lab Matrix: Phases × Local vs Cloud × SRE Principles

This page answers three questions:
1. **What do I do in each phase**, locally and in the cloud?
2. **Which SRE principles does each phase practice?**
3. **Is anything missed**, and where is it covered?

Legend: ✅ fully practiced · ⚠️ simulated or partial · ❌ not possible · — not applicable

---

## 1. How the lab progresses

```
 LOCAL (kind, free, daily practice)                                      CLOUD (EKS; AKS opt., short sessions)
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

| Phase | Local lab (kind) | Cloud extension (AWS EKS) | What only the cloud adds |
|---|---|---|---|
| **P0 Foundation** | 3-node kind cluster, deploy the shop, trace one checkout | Terraform cluster in 3 AZs, same Helm chart | Real nodes in separate zones, a managed control plane, cloud networking |
| **P1 SLIs & SLOs** | Baseline SLIs, Sloth specs, budget dashboard | Same specs, unchanged, plus an SLI from the **cloud load balancer** | An edge SLI measured by the load balancer, closer to the user |
| **P2 Observability** | kube-prometheus-stack, Tempo, Loki, RED/USE dashboards | Same stack, with long-term storage in S3/GCS; cloud metrics (CloudWatch / Cloud Monitoring) | Observability for managed services, storage costs, retention trade-offs |
| **P3 Alerting & on-call** | Burn-rate alerts → PagerDuty + Slack, runbooks | Same alerts, plus **uptime checks from outside** (e.g. multiple regions) | Detecting failures from outside the network you're monitoring |
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
| 10–11 | P8 Cloud sessions (P0–P7 repeated + cloud-only scenarios) | Cloud | ~$9–17 |
| 12 | P9 DR drill + PRR | Local, then cloud | ~$1–2 |

Total cloud cost for the whole program: **about $10–20** (see §6 for the breakdown), as long as you tear everything down after each session.

---

## 6. Cost estimates

> These are approximate on-demand list prices in `us-east-1` (AWS) and `us-central1` (GCP),
> in USD, **before tax and free credits**. Cloud prices change, so check the
> [AWS Pricing Calculator](https://calculator.aws/) or the
> [GCP Pricing Calculator](https://cloud.google.com/products/calculator) before building,
> and update this table with what you actually see on your bill.

### 6.1 Local lab (P0–P7, and the local half of P9)

| Item | Cost |
|---|---|
| kind cluster, the shop, observability stack, Chaos Mesh, Argo | **$0** (open source, runs on your Mac) |
| Paging (PagerDuty free plan + Slack free workspace) | $0 |
| GitHub repo + Actions (public repo) | $0 |
| Electricity (laptop under load for about 4h a day) | Negligible |
| **Total** | **$0** |

### 6.2 Cloud cluster: hourly cost while running

> **Decision:** AWS EKS is the primary cloud; Azure AKS is an optional comparison session (≈ $0.35/hr on-demand, $12–13 for the whole program).
> The three-way EKS / AKS / GKE comparison is in [ADR-0002](adr/0002-cloud-provider.md).

**AWS EKS**: 3 × `t3.large` (2 vCPU / 8 GB), one per AZ

| Component | On-demand $/hr | With Spot workers $/hr | Notes |
|---|---|---|---|
| EKS control plane | 0.100 | 0.100 | Fixed while the cluster exists |
| 3 × t3.large worker nodes | 0.250 | ~0.080 | Spot is roughly 60–70% cheaper, but instances can be reclaimed at any time |
| NAT gateway (1) | 0.045 | 0.045 | Plus $0.045 per GB processed. Use 1 NAT, not 1 per AZ, in a lab |
| Application load balancer | ~0.025 | ~0.025 | Includes light traffic (LCU) usage |
| EBS gp3 volumes (~100 GB total) | ~0.011 | ~0.011 | Node disks + PVCs |
| Public IPv4 addresses (~3) | 0.015 | 0.015 | $0.005/hr per IP |
| CloudWatch logs / metrics | ~0.010 | ~0.010 | Keep control-plane logging minimal |
| **Total** | **≈ $0.45/hr** | **≈ $0.29/hr** | |

**GCP GKE Standard (zonal control plane, nodes in 3 zones)**: 3 × `e2-standard-2` (2 vCPU / 8 GB)

| Component | On-demand $/hr | With Spot nodes $/hr | Notes |
|---|---|---|---|
| Cluster management fee | 0.100 → **$0** | $0 | The free-tier credit covers one zonal or Autopilot cluster per billing account |
| 3 × e2-standard-2 nodes | 0.201 | ~0.060 | Spot VMs are roughly 60–90% cheaper, but can be preempted |
| Load balancer forwarding rule | 0.025 | 0.025 | |
| Persistent disk (3 × 30 GB boot + PVCs) | ~0.015 | ~0.015 | Set a boot disk size. The default of 100 GB triples this cost |
| Cloud NAT + egress | ~0.010 | ~0.010 | |
| **Total** | **≈ $0.25/hr** | **≈ $0.11/hr** | |

**Recommendation:** GKE zonal is about half the price of EKS, and Spot nodes halve it again.
Choose EKS if the jobs you're targeting use AWS, since the extra few dollars buy you directly
relevant experience.

### 6.3 Extras for specific scenarios (only while the scenario runs)

| Add-on | Used in | AWS $/hr | GCP $/hr | Notes |
|---|---|---|---|---|
| Autoscaler adds up to 3 more nodes | P6 load test | +0.25 | +0.20 | Only for the ~2h test |
| Managed Postgres, Multi-AZ (`db.t3.micro` / Cloud SQL HA small) | P8 database failover drill | ~0.035 | ~0.05 | Delete right after the drill |
| Managed Redis (`cache.t3.micro` / Memorystore basic 1 GB) | P8 cache failover | ~0.017 | ~0.05 | Optional |
| Load generator VM (`c5.large` / `c2-standard-4`) | P6 large load test | ~0.085 | ~0.21 | Keeps the load generator from competing with the app for CPU |
| Object storage for Velero and Tempo/Loki | P2, P9 | < $0.01 | < $0.01 | A few GB, so pennies a month |
| Managed Kafka (MSK / Confluent) | ❌ Skip it | ~0.10+ | — | Too expensive for a lab. Run Kafka in the cluster instead |

### 6.4 Cost per phase (recommended hybrid plan)

| Phase | Where | Cloud hours | Est. AWS (EKS) | Est. GCP (GKE) |
|---|---|---|---|---|
| P0–P7 | Local | 0 | $0 | $0 |
| P8 session 1: build the cluster with Terraform, deploy the same repo | Cloud | 4 | ~$1.80 | ~$1.00 |
| P8 session 2: SLOs, alerts, outside-in probes | Cloud | 4 | ~$1.80 | ~$1.00 |
| P8 session 3: AZ outage + node chaos + Spot interruptions | Cloud | 4 | ~$1.80 | ~$1.00 |
| P8 session 4: large load test + cluster autoscaler | Cloud | 4 (+2h extra nodes, +LG VM) | ~$2.60 | ~$2.20 |
| P8 session 5: managed database failover + IAM/quota incident | Cloud | 4 | ~$2.00 | ~$1.20 |
| P9 cloud DR: destroy and rebuild from Terraform + Git + Velero | Cloud | 4 | ~$1.80 | ~$1.00 |
| Data transfer, NAT processing, stray charges | Cloud | — | ~$3–5 | ~$2–3 |
| **Total for the program** | | **~24 h** | **≈ $15–17** | **≈ $9–11** |

With Spot or Preemptible worker nodes the total drops to about **$11–13 (AWS)** or **$6–7 (GCP)**.

### 6.5 Why hybrid: what running in the cloud all the time would cost

| Approach | AWS EKS | GCP GKE |
|---|---|---|
| **Hybrid (recommended)**: local daily, cloud ~24h total | **≈ $15–17 total** | **≈ $9–11 total** |
| Cloud during working hours only (~4h/day × 12 weeks) | ≈ $150 | ≈ $85 |
| Cloud 24/7 for a month | ≈ $330/month | ≈ $180/month |
| Cloud 24/7 for the whole 12-week program | **≈ $900** | **≈ $500** |

The hybrid plan covers the same set of SRE principles (see §3) for about **2% of the always-on cost**.
Choosing where to spend money on reliability is itself an SRE skill.

### 6.6 Hidden costs to watch for

| Trap | Why it happens | Guardrail |
|---|---|---|
| **Orphaned load balancers and disks** | Kubernetes `Service type=LoadBalancer` and PVCs create cloud resources that **Terraform doesn't track**, so `terraform destroy` leaves them behind | `helm uninstall` and delete LB Services and PVCs **before** `terraform destroy`; afterwards check the console for LBs, volumes, and IPs |
| NAT gateway data processing | Pulling container images through NAT ($0.045/GB) | Use one NAT; use VPC endpoints / Private Google Access for the registry |
| Cross-AZ traffic | $0.01/GB in each direction between AZs on AWS | Fine at lab scale, but note it as a cost of running across zones |
| Log ingestion | CloudWatch charges about $0.50/GB ingested | Keep app logs in Loki; turn off verbose control-plane logs |
| Forgetting to tear down | A cluster left running over a weekend costs about $22 on EKS | Auto-destroy timer (below) + budget alerts |
| Idle static IPs / snapshots | Billed even when unused | Check `aws ec2 describe-addresses` / `gcloud compute addresses list` after each session |

### 6.7 Cost guardrails to put in place before creating anything

- [ ] **Budget alerts** at $10, $25, and $50 (AWS Budgets / GCP Budgets & alerts) sent to your email
- [ ] **Tag or label everything** with `project=sre-lab` and `owner=<you>` so you can filter the bill
- [ ] **Auto-destroy**: a `make cloud-down` target, plus a scheduled GitHub Action that runs `terraform destroy` every night at 23:00
- [ ] **Infracost** in CI, which shows the cost change of each Terraform PR (the free tier is enough)
- [ ] After each session, check the console for leftovers and record the actual spend in a table at the bottom of this doc

### 6.8 Actual spend log (fill in as you go)

| Date | Session | Hours | Estimated | Actual (from bill) | Notes |
|---|---|---|---|---|---|
| | | | | | |
