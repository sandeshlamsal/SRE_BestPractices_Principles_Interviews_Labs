# Environments and Sizing

## Decision: local first, cloud later

| | **Local (kind)**, Phases 0–7 | **Cloud (EKS or GKE)**, Phase 8 |
|---|---|---|
| Cost | Free | Pay per hour, so tear it down after each session |
| Speed to iterate | Fast rebuilds, no waiting on the cloud | Slower |
| Realism | Good for everything except real zones, load balancers, and cloud IAM | Real multi-AZ, managed load balancers, IAM, autoscaling nodes |
| What you learn | Kubernetes, observability, SLOs, incidents, chaos, GitOps | Terraform, cloud networking, cost and reliability trade-offs |

The SRE practices are the same in both. Do them locally first, where mistakes cost nothing,
then repeat the setup in the cloud as a "migration" exercise.

## Is local "real" enough for SRE?

**Mostly, yes.** SRE is about practices (SLOs, error budgets, alerting, incident response,
postmortems, chaos, and release safety), and those work the same way on any Kubernetes cluster.
What local can't do is reproduce the **infrastructure failure modes** that only a cloud provider has.

| Practice | Local kind | Needs cloud | Why |
|---|---|---|---|
| SLIs, SLOs, error budgets, burn-rate alerts | ✅ Real | | Same Prometheus and same math. Traffic from the load generator counts as real traffic |
| Dashboards, tracing, logs | ✅ Real | | Same OpenTelemetry pipeline |
| Incident response and postmortems | ✅ Real | | The failures from flags and chaos behave like real ones |
| Pod or service failure, memory leaks, CPU saturation | ✅ Real | | Kubernetes behaves the same |
| Canary releases, GitOps, rollback | ✅ Real | | Argo works the same everywhere |
| Node failure / drain | ⚠️ Simulated | ✅ | kind "nodes" are containers on one machine, not separate hosts |
| **Availability-zone outage** | ❌ | ✅ | Needs real multi-AZ nodes and storage |
| **Cluster autoscaler / node provisioning delay** | ❌ | ✅ | Adding nodes takes minutes in the cloud. That delay is an important capacity lesson |
| **Load test at real scale** | ⚠️ Limited to what your laptop can handle | ✅ | The laptop becomes the bottleneck before the app does |
| Cloud load balancer, DNS, TLS certificates | ❌ | ✅ | Health-check and DNS TTL behavior only exists there |
| Managed dependencies (RDS, ElastiCache, MSK) | ❌ | ✅ | Failovers of managed services are common real incidents |
| IAM / quota / expired-credential incidents | ❌ | ✅ | Some of the most common real outages |
| Cost vs reliability trade-offs | ❌ | ✅ | Each extra nine costs money |
| Real network latency and packet loss between zones | ⚠️ Injected with chaos | ✅ | |

### Recommendation: what real SRE teams do
Real teams don't test everything in production. They use a **pipeline of environments**, and so will we:

1. **Local (kind): where you practice every day, ~80% of the learning.** Phases 0–7. Free, fast, and safe to break. You'll build the whole SRE operating model here: SLOs, alerts, runbooks, game days, chaos, canaries.
2. **Cloud (EKS/GKE): short sessions that represent "production", ~20%.** Phase 8. Bring it up with Terraform, run the cloud-only scenarios above (kill an AZ, let the autoscaler react, fail over a managed database, run a large load test), write the postmortems, then `terraform destroy`. A few sessions cost about $10–20 in total.
3. **Same Git repo for both.** The SLOs, alerts, dashboards, and runbooks move from local to cloud unchanged. That portability is what proves you've built a real operating model rather than a laptop demo.

For interviews, this gives you two kinds of stories: **"I defined SLOs and ran incidents"** (from local)
and **"I handled an AZ failure and autoscaling on EKS"** (from cloud). Hiring managers look for both.

## Local sizing

### This workstation
- MacBook Pro, Intel i9-8950HK, **12 threads, 32 GB RAM**, ~590 GB free disk
- Enough for the full stack: the shop, the observability platform, chaos tooling, and GitOps

### Docker Desktop settings
Settings → Resources:

| Resource | Minimum (Phase 0–1) | **Recommended (all phases)** |
|---|---|---|
| CPUs | 4 | **6–8** |
| Memory | 8 GB | **12–14 GB** |
| Swap | 1 GB | 2 GB |
| Disk image | 40 GB | **80 GB** |

### Estimated memory use by phase

| Component | Approx. RAM | Added in |
|---|---|---|
| kind (3 nodes: control plane + 2 workers) | ~1.5 GB | 0 |
| Astronomy Shop, incl. Kafka and bundled observability | ~5–6 GB | 0 |
| kube-prometheus-stack (Prometheus, Alertmanager, Grafana, exporters) | ~1.5–2 GB | 2 |
| Loki + Tempo (single-binary mode) | ~1 GB | 2 |
| Bundled Jaeger / OpenSearch / Prometheus **removed** | −2 GB | 2 |
| Chaos Mesh | ~0.5 GB | 5 |
| Argo CD + Argo Rollouts | ~1 GB | 7 |
| **Peak total** | **~9–11 GB** | |

These numbers are estimates. Measure the real ones with `kubectl top nodes` and `kubectl top pods -A`
(this needs metrics-server) and update this table. That's also capacity-planning practice.

### Keeping it light
- `make cluster-down` when you're done. The cluster rebuilds in minutes, and everything is in Git.
- OpenSearch is the most memory-hungry bundled component. Phase 2 replaces it with Loki.
- Lower Prometheus retention to 7d locally. Local SLO windows can be shorter as well (see the [observability plan](observability-plan.md#local-slo-windows)).

## Cloud sizing (Phase 8, optional)

| | AWS EKS | GCP GKE Standard |
|---|---|---|
| Nodes | 3 × `t3.large` (2 vCPU / 8 GB), one per AZ | 3 × `e2-standard-2` (2 vCPU / 8 GB), regional or zonal |
| Control plane | ~$0.10/hr | One zonal cluster covered by the free-tier credit |
| Extras | NAT gateway, load balancer, EBS | Load balancer, persistent disk |
| **Rough cost** | **~$0.40–0.60/hr** while running | **~$0.25–0.40/hr** while running |

Prices change, so check the AWS or GCP pricing calculator before building. To keep costs low:
- Provision everything with **Terraform** and run `terraform destroy` after every session. A 4-hour session costs about $2.
- Use Spot or Preemptible nodes for the worker pool. Being interrupted is chaos practice for free.
- Set a **billing alert** (e.g. $20/month) before creating anything.

## Environments model
To practice promotion flows without paying for more clusters, use namespaces on the one kind cluster:

| Environment | Where | Purpose |
|---|---|---|
| `staging` | namespace `astronomy-shop-staging` (Phase 7) | Canary analysis, testing chart upgrades |
| `prod` | namespace `astronomy-shop` | The "production" whose SLOs we defend |
