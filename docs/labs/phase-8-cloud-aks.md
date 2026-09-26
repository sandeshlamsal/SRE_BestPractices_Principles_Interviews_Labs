# Phase 8: Cloud on Azure AKS (Execution Guide + AKS Reference)

> **Goal:** run the same lab (same repo, same GitOps, same SLOs) on a managed cloud cluster, and practice what kind can't:
> real nodes, cloud load balancers, node autoscaling, cloud cost. **Decision:** Azure AKS (the owner's account) instead of AWS
> EKS: ADR-0002 already listed AKS as the alternative, and both cover all SRE principles.
> **Cost rule:** ~**$0.30/hr** while running → **`make aks-down` after every session.**

---

## 1. Pre-flight: read-only account checks (before spending anything)

```bash
az version                                                   # CLI 2.90.0
az account show --query '{sub:name,id:id,user:user.name}'    # logged-in subscription
SUB=$(az account show --query id -o tsv)
az rest --method get --url "https://management.azure.com/subscriptions/$SUB?api-version=2022-12-01" \
  --query subscriptionPolicies.quotaId -o tsv               # offer type
az vm list-usage -l eastus -o table | grep -E "Total Regional vCPUs|BS Family|DSv5|Low-priority"
az aks get-versions -l eastus --query "values[].{v:version,default:isDefault}" -o tsv
```

| Check | Result (2026-09-26) | Consequence |
|---|---|---|
| Subscription | "Azure subscription 1", `PayAsYouGo_2014-09-01` (Microsoft Customer Agreement) | Real charges. **Budget alert first** |
| Regional vCPU quota (eastus) | **10** | Max ~5 × 2-vCPU nodes |
| **DSv5 family quota** | **0** | ❌ `Standard_D2s_v5` (ADR-0002's choice) is impossible (P8-ISSUE-1) |
| BS (B-series) family quota | 10 | ✅ `Standard_B2ms` |
| Spot (low-priority) quota | 3 vCPUs | Effectively no Spot nodes |
| AKS default version | **1.35** (1.36, 1.37 available) | Same as kind v1.35.0: version parity |
| Credit balance (API) | **not visible** (`balanceSummary` null) | Check the portal: Cost Management → Credits. The budget alert covers either way |
| Month-to-date spend | $5.92, from an older, **already-deleted** cluster (`san-dev-aks`) | Nothing currently accruing |

Cost breakdown query (reusable):
```bash
az rest --method post --url "https://management.azure.com/subscriptions/$SUB/providers/Microsoft.CostManagement/query?api-version=2023-11-01" \
  --body '{"type":"ActualCost","timeframe":"MonthToDate","dataset":{"granularity":"None","aggregation":{"totalCost":{"name":"Cost","function":"Sum"}},"grouping":[{"type":"Dimension","name":"ResourceGroupName"},{"type":"Dimension","name":"ServiceName"}]}}' \
  --query properties.rows -o table
```

---

## 2. AKS configuration reference (Terraform: [infra/azure/](../../infra/azure/))

| Setting | Value | Why |
|---|---|---|
| Terraform / provider | `>= 1.9` / `hashicorp/azurerm ~> 4.0` (locked v4.81.0) | Pinned, reproducible |
| Resource group | `sre-lab-rg` (eastus) | Everything for the lab in one group → one budget, one `destroy` |
| Tags | `project=sre-lab, owner=sandesh, managed_by=terraform, phase=8` | Cost filtering |
| **Budget** | `sre-lab-budget`: **$20/month**, alerts at **50/80/100% actual + 100% forecast** → email | **Created before the cluster** (guardrail) |
| Cluster | `sre-lab-aks`, `sku_tier = Free` | No control-plane charge (no uptime SLA: fine for a lab) |
| Kubernetes | `1.35` | Parity with kind |
| Node pool | `system`: **3 × `Standard_D2as_v7`** (AMD, 2 vCPU / 8 GiB, non-burstable), `os_disk_size_gb = 30`, `Managed` | DSv5 quota 0; B2ms not allowed; Dasv7 quota 10 (P8-ISSUE-1/5). 30 GB avoids the 128 GB Premium default (~4× disk cost) |
| **Zones** | `var.zones = []` (none) | This subscription has **no zone access in eastus for any size** (P8-ISSUE-2) |
| Network | Azure CNI **overlay** + **Cilium** data plane, Standard LB | Enforces NetworkPolicy (tool-stack.md); pod IPs don't consume VNet space |
| Identity | System-assigned managed identity | No service-principal secrets to manage |
| Monitoring add-on | **Off** (no Container Insights / Log Analytics) | ~$2.30/GB ingestion; telemetry goes to our own stack |
| Upgrade surge | `max_surge = 1` | One extra node during upgrades |

Note: B2ms (the first fallback) would have been **burstable**, with CPU credits that run out and throttle to baseline under sustained load, a hidden capacity cliff.
D2as_v7 avoids that.

### Files
| File | Purpose |
|---|---|
| [versions.tf](../../infra/azure/versions.tf) | Terraform + provider pins, subscription |
| [variables.tf](../../infra/azure/variables.tf) | location, version, VM size, node count, zones, budget |
| [main.tf](../../infra/azure/main.tf) | resource group, budget, AKS |
| [outputs.tf](../../infra/azure/outputs.tf) | names + `get-credentials` command |
| [terraform.tfvars.example](../../infra/azure/terraform.tfvars.example) | copy to `terraform.tfvars` (**git-ignored**): subscription id + budget email |

Git-ignored: `.terraform/`, `terraform.tfvars`, `*.tfstate*`, `*.tfplan`. **State is local** (lab). Production: remote state in
an Azure Storage container with locking.

---

## 3. Lifecycle commands

```bash
cp infra/azure/terraform.tfvars.example infra/azure/terraform.tfvars    # fill subscription_id + email
make aks-plan      # terraform init + plan -out=plan.tfplan   (free; review it)
make aks-up        # apply the reviewed plan + az aks get-credentials --context sre-lab-aks
make aks-cost      # month-to-date cost of sre-lab-rg
make aks-down      # terraform destroy  (ALWAYS after a session)
kubectl config get-contexts        # kind-sre-lab (local) vs sre-lab-aks (cloud); always check before kubectl
```

---

## 4. Execution log

| Time (UTC) | Step | Result |
|---|---|---|
| 13:09 | Read-only checks | DSv5 quota 0 → B2ms; no Spot; budget missing |
| 13:15 | `terraform init/validate/plan` | 3 to add (RG, budget, AKS) |
| 13:16:36 | `terraform apply` | ✅ RG (26 s) ✅ budget (8 s) ❌ **AKS: `AvailabilityZoneNotSupported`, zone '2' not supported, supported zones ''** |
| 13:23:46 | zones → `[]`, re-apply | ❌ **`Standard_B2ms` not allowed in your subscription in eastus**. The error **listed the allowed sizes** |
| 13:24 | `az vm list-usage` for v7 families | Dasv7 quota = 10 → `Standard_D2as_v7` |
| 13:25:08 | Retry **with** zones on the new size | ❌ `AvailabilityZoneNotSupported`, **supported zones ''**: no zone access for any size |
| 13:25:54 | Apply | ❌ still sent B2ms: my edit to variables.tf **silently didn't match** after `terraform fmt` (P8-ISSUE-6) |
| 13:28:15 | Fixed edit, **verified in `terraform plan`** (`vm_size = Standard_D2as_v7`), apply | ✅ `Creating`: 3 × D2as_v7, k8s 1.35, Free tier |
| 13:32:39 | **Teardown requested mid-creation** (owner leaving) | `az group delete -n sre-lab-rg --yes --no-wait` + the node RG `MC_sre-lab-rg_sre-lab-aks_eastus`; Terraform apply interrupted; `terraform state rm` for all resources (state = `[]`) |

---

### Emergency teardown (when `terraform destroy` isn't an option, e.g. mid-create)
```bash
az group delete -n sre-lab-rg --yes --no-wait                         # cluster, budget, everything in the RG
az group delete -n MC_sre-lab-rg_sre-lab-aks_eastus --yes --no-wait   # AKS node RG (VMs/disks/LB) if it lingers
cd infra/azure && for r in $(terraform state list); do terraform state rm "$r"; done   # keep state truthful
az group list --query "[?contains(name,'sre-lab')].{n:name,s:properties.provisioningState}" -o table   # verify: empty
```
Azure performs the delete server-side, so it completes even if the laptop sleeps.
⚠️ **The budget is NOT deleted with the resource group**: consumption budgets are billing objects that outlive their scope (P8-ISSUE-7).
On the next `make aks-up`, import it instead of recreating it:
```bash
cd infra/azure && terraform import -var-file=terraform.tfvars azurerm_consumption_budget_resource_group.lab \
  "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/sre-lab-rg/providers/Microsoft.Consumption/budgets/sre-lab-budget"
```
**Before the next session:** confirm nothing is left: `az group list ... contains(name,'sre-lab')` → empty.

### Session 2 (2026-09-26, after the owner returned)
| Time (UTC) | Step | Result |
|---|---|---|
| 15:53 | Verify teardown | No `sre-lab` groups, no VMSS ✓ |
| 15:53:56 | `make aks-up` | ✅ RG 28 s ✅ **AKS 5m25s** ❌ budget: "already exists" |
| 16:01 | `terraform import` budget → `terraform plan` | **No changes**; `get-credentials` → 3 nodes Ready, **v1.35.8** |
| 16:01–16:07 | `make obs-up`, `make rollouts-up`, `make argocd-up` (**unchanged** targets, context `sre-lab-aks`) | ✅ all deployed in **389 s** |
| 16:17 | Argo CD sync | config + dashboards Synced/Healthy; shop 37/38 (one `payment` replica stuck, see below); checkout Rollout Healthy |
| 16:20:34 | **Real node failure:** `az vmss stop --skip-shutdown` on `vmss000000` (6 min) | see §5 |
| 16:26:52 | Power on | node Ready at +412 s |
| 16:31:54–16:38:43 | `make aks-down` | ✅ **Destroy complete: 3 destroyed**; context switched back to `kind-sre-lab`. Session ≈ 45 min ≈ **$0.25** |

⚠️ `az aks get-credentials` makes `sre-lab-aks` the **current** context. Check `kubectl config current-context` before any
destructive command; switch back with `kubectl config use-context kind-sre-lab`.

## 5. SRE principles on real cloud nodes (results)

### Portability of the operating model ✅
The **same repo, unchanged**, deployed onto AKS: Argo CD synced the shop, SLO rules, alerts, routing and dashboards; all
**7 SLIs evaluated** on AKS (the checkout Rollout too). **That's the proof that it's an operating model, not a laptop demo.**

### Cost vs reliability (Azure retail price API, eastus)
| Component | $/hr |
|---|---|
| 3 × `D2as_v7` | 3 × 0.0908 = **0.272** |
| AKS control plane (Free) | 0.00 |
| LB + 4 PVCs (21 GB) + 3 × 30 GB OS disks | ~0.04 |
| **Total** | **≈ $0.31/hr** (ADR-0002 estimated $0.35) |

| "One more nine" option | Cost | Trade-off |
|---|---|---|
| AKS **Standard** tier | **+$0.10/hr (+32%)** | financially backed API-server SLA (Free has none) |
| **Spot** nodes ($0.0176/hr) | **−81% compute** | evictable at any time; quota allows only 1 node here |
| **Availability zones** | n/a | subscription has no zone access (P8-ISSUE-2) |
```bash
curl -s -G "https://prices.azure.com/api/retail/prices" --data-urlencode \
  "\$filter=serviceName eq 'Virtual Machines' and armRegionName eq 'eastus' and armSkuName eq 'Standard_D2as_v7' and priceType eq 'Consumption'"
```

### Cold start on a fresh cluster
**11 checkouts returned 500 at 16:13**, while pods were starting (16:08–16:13) and the load generator was already sending
traffic, then 0. That's the Phase 0 startup-ordering issue (ISSUE-6) reproduced on real cloud nodes.

### A broken replica, contained by readiness
One `payment` replica never answered gRPC health (not even with a 5 s timeout) and was restarted 4× by liveness; **readiness kept it
out of rotation** and the other replica served traffic (0 checkout errors after cold start). Mitigation: delete the pod;
the replacement was healthy immediately.

### Real node failure (`vmss000000` powered off, 16:20:34–16:26:52)
| Finding | Detail |
|---|---|
| **"2 replicas" ≠ "2 failure domains"** | **Both checkout replicas were on the failed node**. *Preferred* anti-affinity allows co-location (that node was at 91% memory). Needs `required` anti-affinity or topologySpreadConstraints for critical services |
| **Dependency chains lengthen recovery** | Checkout pods were rescheduled at +81 s but stuck in `Init` until **+174 s**: their `wait-for-kafka` init container waited for Kafka, which **died on the same node** |
| **The synthetic users were in the blast radius** | The load generator (single replica, default 300 s toleration) ran on the failed node, so **0 requests of any kind from 16:22 to 16:30**. The SLI went **blind, not red** (P1-ISSUE-16 again). User impact **couldn't be measured**. Real SLOs need an **external probe** outside the cluster |
| Measurement tooling | The Prometheus port-forward dropped at t+35 s (P2-ISSUE-7); the impact was reconstructed from Prometheus **history** |
| Confounded page state | `CheckoutAvailabilityBudgetBurn` was already firing from the 16:13 cold start (30m window) |

## Issues log
| ID | Area | Symptom | Root cause | Fix / decision |
|---|---|---|---|---|
| P8-ISSUE-1 | Quota | Planned `Standard_D2s_v5` impossible | DSv5 family quota = **0** on this subscription | `Standard_B2ms` (BS quota 10). Alternative: request a quota increase |
| P8-ISSUE-2 | Zones | AKS create failed after ~40 s: `AvailabilityZoneNotSupported ... supported zones for location 'eastus' are ''` | Zone access for B2ms is restricted on this subscription (eastus and eastus2) | `zones = []`. **AZ-outage drill downgraded to node-failure**. A real AZ test needs zone access or another SKU |
| P8-ISSUE-3 | Security | Local AWS CLI uses **root account access keys** | Root keys created at some point | Not used for this lab. **Recommended: delete root keys, use an IAM user/SSO** |
| P8-ISSUE-4 | Tooling | `az vm list-skus` region scan timed out (> 5 min) | It scans the full SKU catalogue per region | Query one region/size at a time, or use `az vm list-usage` + an error-driven approach |
| P8-ISSUE-5 | SKU policy | `The VM size of Standard_B2ms is not allowed in your subscription in location 'eastus'` | Subscription-level SKU restriction, not quota. Quota ≠ permission | Read the allowed list **from the error**, check the quota of the family (`az vm list-usage`), pick `Standard_D2as_v7` |
| P8-ISSUE-6 | Tooling | Re-apply still used the old VM size | A scripted string replace didn't match after `terraform fmt` realigned the file; no error was raised | **Verify the plan before apply** (`terraform plan \| grep vm_size`). A silent no-op edit is the same class of bug as P2-ISSUE-18 |
| P8-ISSUE-7 | Teardown | Next `terraform apply`: budget `already exists` | Consumption budgets survive deleting their resource group; state had been `rm`'d | `terraform import` the budget (keeps its alert history). **Deleting the RG isn't a complete teardown**; verify with `az consumption budget list` |
| P8-ISSUE-8 | Startup | 11 × HTTP 500 on checkout at 16:13 on a fresh cluster | Load generator starts sending before dependencies are ready (ISSUE-6) | Readiness gates / start traffic after ready; the external probe decides |
| P8-ISSUE-9 | Scheduling | Both checkout replicas on one node | `preferredDuringScheduling` anti-affinity is a *preference*; memory pressure let the scheduler co-locate | `required` anti-affinity or topologySpreadConstraints for CUJ services |
| P8-ISSUE-10 | Recovery | Rescheduled checkout stuck in `Init` for ~90 s | `wait-for-kafka` init container + Kafka on the same failed node | Spread dependencies apart; don't hard-block startup on async dependencies |
| **P8-ISSUE-11** | **Measurement** | Node-failure impact **unmeasurable**: 0 requests from 16:22 to 16:30 | The single-replica load generator ran on the failed node: **the traffic source was in the blast radius** | External synthetic probe (outside the cluster) for real SLO measurement |
| P8-ISSUE-12 | Mystery | One payment replica never answered gRPC health | Unknown (the other replica was fine; the replacement was fine) | Readiness contained it; open for a deeper look |
