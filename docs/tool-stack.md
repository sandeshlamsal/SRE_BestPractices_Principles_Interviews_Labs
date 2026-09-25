# Tool Stack: Production-Grade, Local and Cloud

**Goal:** the lab should run the same kinds of tools, and follow the same rules, as a real
production platform team. Where it can't, this page says so, so we know exactly where the lab
falls short of production.

Decisions are recorded in ADRs: [0001 app](adr/0001-lab-application.md) ·
[0002 cloud](adr/0002-cloud-provider.md) · [0003 paging](adr/0003-paging-and-incident-tooling.md).

Legend for the **Parity** column: 🟢 same tool and config locally and in the cloud · 🟡 same tool with a different backend · 🔵 cloud only

---

## 1. The stack at a glance

| Layer | Production-grade tool | Local (kind) | Cloud (AWS EKS, primary) | Cloud (Azure AKS, optional) | Parity | Phase |
|---|---|---|---|---|---|---|
| **Kubernetes** | Managed K8s across 3 AZs | kind, 1 control plane + 2 workers | EKS, managed node groups across 3 AZs | AKS, system + user pools across 3 zones | 🟡 | P0 / P8 |
| **Infrastructure as code** | Terraform + tflint + Checkov + Infracost | kind config in Git (`platform/kind/`) | Terraform `infra/aws/` (terraform-aws-modules) | Terraform `infra/azure/` | 🔵 | P8 |
| **GitOps** | Argo CD (app-of-apps) | Argo CD | Argo CD (same apps, different values) | Argo CD | 🟢 | P7 |
| **Progressive delivery** | Argo Rollouts + Prometheus analysis | Argo Rollouts | Argo Rollouts | Argo Rollouts | 🟢 | P7 |
| **CI** | GitHub Actions | `helm lint`, kubeconform, `promtool`, Kyverno CLI, Trivy, markdown link check | + tflint, Checkov, Infracost | same | 🟢 | P7 |
| **Ingress / traffic** | Gateway API + Envoy Gateway | Envoy Gateway + [cloud-provider-kind](https://github.com/kubernetes-sigs/cloud-provider-kind) for LoadBalancer IPs | Envoy Gateway behind an NLB (AWS Load Balancer Controller) | Envoy Gateway behind Azure LB | 🟡 | P2 |
| **TLS** | cert-manager | cert-manager, self-signed internal CA | cert-manager + Let's Encrypt (DNS-01) | same | 🟡 | P2 / P8 |
| **DNS** | external-dns | `/etc/hosts` / `*.localtest.me` | external-dns + Route 53 | external-dns + Azure DNS | 🔵 | P8 |
| **Secrets** | External Secrets Operator + cloud secret manager | ESO with the Kubernetes provider (secrets seeded from a git-ignored `.env`) | ESO + AWS Secrets Manager (Pod Identity) | ESO + Key Vault (Workload Identity) | 🟡 | P7 / P8 |
| **Policy / guardrails** | Kyverno | Kyverno: require limits, probes, owner labels; block `:latest` | same policies | same | 🟢 | P7 |
| **Supply chain** | Trivy scanning, images pinned by digest | Trivy in CI | + ECR scan-on-push | + Defender for Containers (optional) | 🟡 | P7 |
| **Network policy** | Default-deny + allow-lists | Cilium CNI (replaces kindnet) | VPC CNI network policies | Azure CNI powered by Cilium | 🟡 | P7 |
| **Telemetry** | OpenTelemetry SDKs + Collector | OTel Collector (from the demo chart) | same | same | 🟢 | P0 |
| **Metrics** | Prometheus (HA) + long-term storage | kube-prometheus-stack, 1 replica, 7d retention | kube-prometheus-stack, **2 replicas + Thanos sidecar → S3** | same → Blob Storage | 🟡 | P2 / P8 |
| **Traces** | Tempo | Tempo single binary, local disk | Tempo → S3 | Tempo → Blob | 🟡 | P2 |
| **Logs** | Loki | Loki single binary, local disk | Loki → S3 | Loki → Blob | 🟡 | P2 |
| **Dashboards** | Grafana, dashboards as code | Grafana, JSON in `observability/dashboards/` | same | same | 🟢 | P2 |
| **SLOs as code** | Sloth | Sloth specs in `slos/` | same | same | 🟢 | P1 |
| **Synthetic monitoring** | Blackbox exporter + an external prober | Blackbox exporter (inside the cluster) | + **CloudWatch Synthetics canary** (outside-in) | + Azure Monitor availability test | 🟡 | P3 / P8 |
| **Alerting** | Alertmanager | Alertmanager | same | same | 🟢 | P3 |
| **Paging & on-call** | PagerDuty + Slack | PagerDuty free + Slack | same | same | 🟢 | P3 |
| **Incident coordination** | Slack channels + templates in Git | `#inc-*` channels, `incidents/`, `postmortems/` | same | same | 🟢 | P4 |
| **Chaos engineering** | Chaos Mesh + a cloud fault service | Chaos Mesh | Chaos Mesh + **AWS FIS** (AZ power interruption) | Chaos Mesh + **Azure Chaos Studio** | 🟡 | P5 / P8 |
| **Background traffic** | Real users | Locust load generator (in the demo chart) | same | same | 🟢 | P0 |
| **Load / capacity tests** | k6 | k6 (CLI or k6-operator) | k6 on a separate EC2 instance | k6 on a separate VM | 🟡 | P6 |
| **Pod autoscaling** | HPA + KEDA | metrics-server + HPA; KEDA scaling on Kafka lag | same | same | 🟢 | P5 / P6 |
| **Node autoscaling** | Karpenter / Cluster Autoscaler | ❌ not possible | **Karpenter** | Cluster Autoscaler / NAP | 🔵 | P8 |
| **Backup / DR** | Velero + object storage | Velero → MinIO | Velero → S3 | Velero → Blob | 🟡 | P9 |
| **Managed data (failover drill)** | Managed DB with HA | ❌ (in-cluster Postgres/Valkey only) | RDS Postgres Multi-AZ | Postgres Flexible Server zone-redundant | 🔵 | P8 |
| **Cost visibility** | OpenCost + Infracost + budgets | OpenCost (in-cluster cost allocation) | + AWS Budgets, Cost Explorer tags | + Azure Cost Management | 🟡 | P6 / P8 |

### Choices that were still open, now decided

| Was | Chosen | Why | Alternative kept in mind |
|---|---|---|---|
| Sloth vs Pyrra | **Sloth** | Generates plain Prometheus rules that go through GitOps; widely used | Pyrra, if we want a built-in SLO UI |
| Chaos Mesh vs LitmusChaos | **Chaos Mesh** | CNCF project; **Azure Chaos Studio uses it for AKS**, so the skills carry over | Litmus |
| k6 vs Locust | **Both** | Locust = always-on background "users" (already in the demo); k6 = scripted capacity tests with pass/fail thresholds | — |
| Tempo vs Jaeger | **Tempo** | Cheap object storage, links natively with Grafana, Loki, and exemplars | Jaeger (still usable in P0–P1 through the demo) |
| Kyverno vs Conftest | **Kyverno** (cluster) + **Checkov** (Terraform) | Kyverno policies are Kubernetes YAML and run both in CI and in the cluster | OPA Gatekeeper |
| ingress-nginx | **Envoy Gateway (Gateway API)** | ingress-nginx was retired in March 2026; Gateway API is the standard going forward | Istio / Cilium gateway |
| Cluster Autoscaler vs Karpenter (EKS) | **Karpenter** | The current default for EKS; fast, picks instance types | Cluster Autoscaler |

---

## 2. Production-grade standards the lab enforces

These are **requirements**, checked automatically where possible (Kyverno in the cluster, CI on PRs).

| # | Standard | How it's enforced | Phase |
|---|---|---|---|
| 1 | Everything in Git; no manual `kubectl apply/edit` against "prod" | Argo CD self-heal reverts manual changes | P7 |
| 2 | Every workload has requests/limits, readiness + liveness probes | Kyverno `require-requests-limits`, `require-probes` | P5 / P7 |
| 3 | Every CUJ service has ≥ 2 replicas, a PDB, and topology spread | Kyverno + review checklist | P5 |
| 4 | Every workload is labelled `app.kubernetes.io/*`, `owner`, `tier` | Kyverno `require-labels` | P7 |
| 5 | No `:latest` tags; images pinned by digest in prod | Kyverno + Trivy in CI | P7 |
| 6 | Every CUJ has an SLO; every page alert has a runbook | CI checks that each `runbook` annotation points to a file that exists | P1 / P3 |
| 7 | Dashboards, alerts, and SLOs are code | Stored in Git and deployed by Argo CD | P2 / P3 |
| 8 | Secrets never in Git | ESO + gitleaks in CI | P7 |
| 9 | TLS at the edge | cert-manager + Gateway | P2 |
| 10 | Default-deny network policy per namespace | Cilium / VPC CNI policies | P7 |
| 11 | Changes ship through canary with automated SLI analysis | Argo Rollouts `AnalysisTemplate` | P7 |
| 12 | Backups are **restored** on a schedule, not just taken | Velero restore drill, time recorded against the RTO | P9 |
| 13 | Every cloud resource tagged `project=sre-lab`, with a budget alert | Terraform default tags + Checkov | P8 |
| 14 | Separate staging and prod | Namespaces locally; staging on kind and prod on EKS in P8 | P7 / P8 |

---

## 3. Where the lab falls short of production (on purpose)

Being honest about these gaps is itself good SRE practice, and it's also a good interview answer.

| Real production has | This lab has | Why it's acceptable | How to close the gap if you want to |
|---|---|---|---|
| Real users with unpredictable behaviour | Locust + k6 synthetic users | SLO math and alerting behave the same | Replay more varied traffic patterns in k6 |
| Multi-region, active-active | Single region, 3 AZs | AZ failure is the most common large failure | Design-only exercise in P9: write the multi-region ADR |
| Separate clusters per environment | One kind cluster (staging + prod namespaces); one EKS cluster | Cost | A second EKS cluster for one session (~$2) |
| A team of 6–8 on-call | You (+ a friend as game master) | The process is the same; practice handoffs anyway | Invite peers to game days |
| Months of SLO history | Hours to days | Burn-rate alerts work immediately | Leave the kind cluster running for a week |
| Enterprise SSO / RBAC | Local admin | Not a core SRE skill for this lab | Optional: Dex/OIDC + RBAC roles for on-call vs dev |
| Compliance / audit trails | Git history + Argo CD history | Covers change auditing | — |

---

## 4. Resource impact

Adding the production-grade components (Envoy Gateway, cert-manager, ESO, Kyverno, Cilium, KEDA,
Velero + MinIO, OpenCost) adds roughly **2–3 GB** to the local estimate in
[environments-and-sizing.md](environments-and-sizing.md). The local peak becomes about **12–14 GB**,
so **set Docker Desktop to 14–16 GB RAM**. Your 32 GB Mac handles that.
In the cloud, 3 × 8 GB nodes are still enough. Karpenter adds nodes during load tests.

---

## 5. Repository layout this stack implies (created phase by phase)

```
platform/
  kind/                 cluster config (exists)
  bootstrap/            Argo CD install + app-of-apps root
  addons/               Helm values per add-on: envoy-gateway, cert-manager, eso, kyverno,
                        cilium, keda, velero, opencost, chaos-mesh, argo-rollouts
apps/
  astronomy-shop/       values.yaml (exists) + values-local.yaml / values-aws.yaml
observability/
  kube-prometheus-stack/, tempo/, loki/, dashboards/, alertmanager/
slos/                   Sloth specs
policies/               Kyverno policies
chaos/                  Chaos Mesh experiments + FIS templates
loadtests/              k6 scripts
infra/
  aws/                  Terraform: VPC, EKS, Karpenter, S3, IAM, RDS (drill), budgets
  azure/                optional
runbooks/ incidents/ postmortems/ oncall/
.github/workflows/      CI: lint, validate, policy, security, cost
```
