# ADR-0002: Cloud provider for Phases 8–9

- **Status:** Accepted
- **Date:** 2026-09-25

## Context
Phases 0–7 run locally on kind. Phases 8–9 need a managed Kubernetes cloud to practice what
local can't do: AZ outages, node autoscaling, managed-dependency failover, IAM and quota incidents,
and cost trade-offs (see [lab-matrix.md §3](../lab-matrix.md#3-sre-principle-coverage)).
The owner already has **AWS** and **Azure** accounts and is open to **GCP** if it saves money.

## Options

### Cost: hourly while running (3 nodes × 2 vCPU / 8 GB, one per AZ)

These are approximate on-demand list prices in `us-east-1` / `eastus` / `us-central1` (USD).
Check them in the pricing calculators before building.

| Component | AWS EKS | Azure AKS | GCP GKE |
|---|---|---|---|
| Control plane | $0.10 | **$0** (Free tier, no uptime SLA) · $0.10 Standard tier | $0.10, **covered by the free-tier credit** for one zonal cluster |
| 3 worker nodes | $0.25 (t3.large) | $0.29 (Standard_D2s_v5) | $0.20 (e2-standard-2) |
| Outbound (NAT) | $0.045 NAT gateway | $0 (outbound through the load balancer) | ~$0.01 Cloud NAT |
| Load balancer + public IPs | ~$0.04 | ~$0.035 | ~$0.03 |
| Disks | ~$0.01 | ~$0.02 (set a **30 GB OS disk**. The default of 128 GB Premium is about $0.08/hr) | ~$0.015 (set a 30 GB boot disk) |
| Logs / monitoring | ~$0.01 (CloudWatch, minimal) | ~$0.01 (**turn off Container Insights / Log Analytics**, which costs about $2.30/GB) | ~$0 (the GKE system-logging free allotment) |
| **Total on-demand** | **≈ $0.45/hr** | **≈ $0.35/hr** | **≈ $0.25/hr** |
| **With Spot workers** | ≈ $0.29/hr | ≈ $0.21/hr (the system pool can't be Spot, so 1 regular + 2 Spot) | ≈ $0.11/hr |

### Cost: whole program (~24 cloud hours, including extras and stray charges)

| | AWS EKS | Azure AKS | GCP GKE |
|---|---|---|---|
| On-demand | **≈ $15–17** | **≈ $12–13** | **≈ $9–11** |
| With Spot | ≈ $11–13 | ≈ $8–10 | ≈ $6–7 |
| New-account credits | New accounts get free-plan credits (check eligibility) | $200 for 30 days (new accounts only) | **$300 for 90 days (new accounts)**, which covers the whole program. Note: free-trial accounts are limited to 8 vCPUs running at once, which blocks the P6 autoscaler test |
| 24/7 for 12 weeks (for comparison) | ≈ $900 | ≈ $700 | ≈ $500 |

The biggest difference is about **$6 over the whole program**. Cost doesn't decide this. What
you learn and how relevant it is to jobs does.

### SRE coverage: can each cloud practice the cloud-only scenarios?

| Scenario / principle | AWS EKS | Azure AKS | GCP GKE |
|---|---|---|---|
| Multi-AZ nodes | ✅ | ✅ | ✅ |
| **AZ outage drill** | ✅✅ **AWS FIS** has a ready-made *AZ power interruption* scenario | ✅✅ **Azure Chaos Studio** (zone-down faults for VMs/VMSS; it uses Chaos Mesh for AKS) | ✅ Manual: cordon and drain one zone's nodes, or delete its instance group. No managed chaos service |
| Managed chaos service | ✅ FIS (EKS pod/node actions, EC2, RDS failover, network) | ✅ Chaos Studio (AKS through Chaos Mesh, VMSS, Cosmos, NSG) | ❌ Bring your own (Chaos Mesh) |
| Node autoscaling | ✅ Karpenter / Cluster Autoscaler | ✅ Cluster Autoscaler / Node Auto-Provisioning | ✅ Cluster Autoscaler / NAP / Autopilot |
| Managed DB failover drill | ✅ RDS Multi-AZ "reboot with failover" | ✅ Postgres Flexible Server zone-redundant HA, forced failover | ✅ Cloud SQL HA, manual failover |
| Managed Prometheus / SLOs | Amazon Managed Prometheus; CloudWatch Application Signals SLOs | Azure Monitor managed Prometheus | Google Managed Prometheus; **built-in SLO monitoring** in Cloud Monitoring |
| Workload identity (IAM incidents) | EKS Pod Identity / IRSA | AKS Workload Identity (Entra ID) | GKE Workload Identity |
| Terraform maturity | ✅ Excellent (terraform-aws-modules/eks) | ✅ Good (azurerm + AKS modules) | ✅ Excellent (terraform-google-modules/kubernetes-engine) |
| SRE principles covered (of 23, see lab-matrix §3) | **23 / 23** | **23 / 23** | **23 / 23** |
| **Share of SRE / DevOps job postings** | **Highest** | Second (strong in enterprise, finance, healthcare) | Third |

All three cover every principle, because the SRE tooling (Prometheus, Sloth, Chaos Mesh, Argo)
runs **inside the cluster** and moves between clouds unchanged. The differences come down to
realism (managed chaos) and how relevant each is for jobs.

## Decision
**Primary: AWS EKS.**
- It appears in the most SRE job postings, so "I ran an AZ-outage game day on EKS with AWS FIS" is the strongest interview story.
- FIS gives the most realistic AZ-failure drill with the least effort.
- It costs about $5 more than GKE over the whole program, which is small.

**Optional second: Azure AKS**, for one comparison session (~$2) in Phase 8 if you're targeting
Azure-heavy employers. Deploying the same repo on a second cloud also proves the operating model
is portable. Azure Chaos Studio runs on Chaos Mesh, the tool we already use locally.

**GKE: only if cost is the main goal.** With a new account's $300 credit, it costs $0 out of
pocket. Skip the P6 autoscaler scenario there because of the free-trial vCPU limit, or upgrade the account.

## Consequences
- Terraform lives in `infra/aws/` first; `infra/azure/` is optional later.
- Use Spot workers on EKS (≈ $11–13 total) and run the AZ drill with FIS.
- Budget alerts go in place in every account before any resource is created ([lab-matrix §6.7](../lab-matrix.md#67-cost-guardrails-to-put-in-place-before-creating-anything)).
