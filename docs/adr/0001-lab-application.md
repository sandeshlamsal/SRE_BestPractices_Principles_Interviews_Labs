# ADR-0001: Lab application

- **Status:** Accepted
- **Date:** 2026-09-25

## Context
We need a realistic, multi-service e-commerce app to practice SRE: SLOs, alerting,
incident response, and chaos. It must run locally on Kubernetes.

## Options considered
| Option | Pros | Cons |
|---|---|---|
| **OpenTelemetry Astronomy Shop** | CNCF, actively maintained, 15+ services in 10+ languages, full OTel instrumentation, **built-in failure scenarios via flagd feature flags**, Locust load generator, Kafka, bundled Grafana/Jaeger/Prometheus | Heavier (~6 GB RAM) |
| Google Online Boutique (microservices-demo) | Lighter, well known, clean gRPC design | No built-in fault injection, and observability is GCP-focused |
| Weaveworks Sock Shop | Classic reference app | Unmaintained since Weaveworks shut down |

## Decision
Use the **OpenTelemetry Astronomy Shop** through its official Helm chart.
Keep Online Boutique as a lighter alternative, and as a second app for later
exercises like multi-tenant alerting.

## Consequences
- Incidents can be triggered by flipping feature flags (e.g. `paymentFailure`,
  `adHighCpu`, `kafkaQueueProblems`, `productCatalogFailure`), so incident drills can be repeated.
- Docker needs at least 6 GB RAM.
