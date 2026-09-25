# Architecture: What We're Running

## The app from a user's view

The Astronomy Shop is an online store that sells telescopes and astronomy gear.

| Page | What you see | What happens behind it |
|---|---|---|
| **Home** | Grid of products, currency selector | `product-catalog`, `currency`, `ad` |
| **Product page** | Photo, price, "You may also like", an ad banner | `product-catalog`, `recommendation`, `ad`, `image-provider` |
| **Cart** | Items, quantities, shipping estimate | `cart` (backed by Valkey/Redis), `shipping` → `quote` |
| **Checkout** | Pre-filled address and fake credit card, "Place Order" | `checkout` calls `cart`, `product-catalog`, `currency`, `shipping`, `payment`, `email`, then publishes to **Kafka** |
| **Order confirmation** | Order ID, tracking ID | `accounting` and `fraud-detection` consume the Kafka event asynchronously |

A **load generator** (Locust) plays the part of real shoppers around the clock, so the dashboards
always have traffic, even when you aren't clicking around.

## Service map

```mermaid
flowchart LR
  user([Shopper / Load generator]) --> proxy[frontend-proxy<br/>Envoy]
  proxy --> fe[frontend<br/>Next.js]
  proxy --> img[image-provider<br/>nginx]
  proxy -.-> flagui[flagd-ui]
  fe --> ad[ad<br/>Java]
  fe --> rec[recommendation<br/>Python]
  fe --> pc[product-catalog<br/>Go]
  fe --> cur[currency<br/>C++]
  fe --> cart[cart<br/>.NET]
  fe --> ship[shipping<br/>Rust]
  fe --> co[checkout<br/>Go]
  rec --> pc
  cart --> valkey[(valkey)]
  ship --> quote[quote<br/>PHP]
  co --> cart & pc & cur & ship
  co --> pay[payment<br/>Node.js]
  co --> email[email<br/>Ruby]
  co --> kafka[(Kafka)]
  kafka --> acct[accounting<br/>.NET]
  kafka --> fraud[fraud-detection<br/>Kotlin]
  flagd[flagd<br/>feature flags] -.-> ad & rec & pc & pay & cart & kafka
```

The exact set of services depends on the demo version. Newer releases add services such as
product reviews. Run `make status` to see what's actually deployed.

## Where each SRE concept lands in the architecture

| Concept | Where it lives |
|---|---|
| SLIs (edge) | `frontend-proxy` (Envoy) and spanmetrics for `checkout`, `product-catalog`, `cart` |
| Synchronous critical path | proxy → frontend → checkout → payment/cart/shipping/currency |
| Async path (freshness SLI) | checkout → Kafka → accounting / fraud-detection |
| Failure injection | `flagd` feature flags |
| State | `valkey` (cart) and Kafka. These are the parts where losing data is possible |
| Traffic | `load-generator`, which can be scaled up for capacity tests |

## Lab platform layers

```
┌───────────────────────────────────────────────────────────────┐
│ Phase 7   Argo CD (GitOps) · Argo Rollouts (canary)           │
├───────────────────────────────────────────────────────────────┤
│ Phase 5   Chaos Mesh (pod / network / stress faults)          │
├───────────────────────────────────────────────────────────────┤
│ Phase 2-3 Observability: OTel Collector → Prometheus · Tempo  │
│           · Loki → Grafana; Alertmanager → PagerDuty + Slack  │
│           Sloth → SLO recording rules + burn-rate alerts      │
├───────────────────────────────────────────────────────────────┤
│ Phase 0   Astronomy Shop (namespace: astronomy-shop)          │
├───────────────────────────────────────────────────────────────┤
│           Kubernetes: kind (local) → EKS (+AKS opt.) (Ph. 8)  │
└───────────────────────────────────────────────────────────────┘
```
