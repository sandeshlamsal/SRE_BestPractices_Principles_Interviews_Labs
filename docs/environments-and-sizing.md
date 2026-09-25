# Environments and Sizing

## Decision: local first, cloud later

| | **Local (kind)**, Phases 0–7 | **Cloud (AWS EKS; Azure AKS optional)**, Phases 8–9 |
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
2. **Cloud (AWS EKS, see [ADR-0002](adr/0002-cloud-provider.md)): short sessions that represent "production", ~20%.** Phase 8. Bring it up with Terraform, run the cloud-only scenarios above (kill an AZ, let the autoscaler react, fail over a managed database, run a large load test), write the postmortems, then `terraform destroy`. A few sessions cost about $10–20 in total.
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
| Memory | 8 GB | **12 GB** (measured in Phase 2: containers ~6–9 GB; at 16 GB the Docker VM grew to 26.6 GB RSS and starved macOS on a 32 GB Mac, see [P2-ISSUE-14](labs/phase-2-observability.md#issues-log)) |
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

## Cloud sizing (Phases 8–9)

**Primary: AWS EKS.** The full cost and SRE-coverage comparison is in [ADR-0002](adr/0002-cloud-provider.md).

| | **AWS EKS (primary)** | Azure AKS (optional comparison) | GCP GKE (cheapest) |
|---|---|---|---|
| Nodes | 3 × `t3.large` (2 vCPU / 8 GB), one per AZ; Karpenter for scale-out | 3 × `Standard_D2s_v5` (2 vCPU / 8 GB) across 3 zones; 30 GB OS disks | 3 × `e2-standard-2` (2 vCPU / 8 GB); 30 GB boot disks |
| Control plane | ~$0.10/hr | $0 (Free tier) | Covered by the free-tier credit (one zonal cluster) |
| Extras | NAT gateway, NLB, EBS | Load balancer (no NAT needed), managed disks | Load balancer, persistent disk, Cloud NAT |
| Managed chaos | AWS FIS (AZ power interruption) | Azure Chaos Studio | None (use Chaos Mesh) |
| **Rough cost** | **~$0.45/hr** on-demand, ~$0.29/hr with Spot | **~$0.35/hr** on-demand, ~$0.21/hr with Spot | **~$0.25/hr** on-demand, ~$0.11/hr with Spot |

For the full per-component, per-phase breakdown and hidden costs, see [lab-matrix.md §6](lab-matrix.md#6-cost-estimates).
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
