# 08: Capacity, Resilience and Chaos Engineering

## Capacity planning
Make sure there's enough capacity for **expected demand plus headroom**, without paying for far more than you need.

1. **Forecast demand**: organic growth plus planned events (launches, sales).
2. **Measure capacity with load tests**. Don't guess. Find where latency bends and errors start (the saturation point).
3. **Add headroom** for failure: with N+1 or N+2, the system survives losing a node or zone at peak.
4. **Autoscale** for normal variation, and **plan ahead** for large known events.

**Little's Law**: `concurrency = throughput × latency`. At 200 req/s with 250ms latency, you have about 50 requests in flight. If latency doubles, concurrency doubles, and pools and threads fill up.

## Resilience patterns

| Pattern | Protects against | K8s / lab implementation |
|---|---|---|
| **Timeouts** | Hanging dependencies | gRPC deadlines, Envoy route timeouts |
| **Retries with backoff + jitter** | Transient errors | Only on idempotent calls, with a retry budget |
| **Circuit breaker** | Hammering a failing dependency | Envoy outlier detection / service mesh |
| **Bulkheads** | One slow dependency using up all threads | Separate pools; resource limits per pod |
| **Graceful degradation** | Non-critical dependency failure | Show products even if ads or recommendations fail |
| **Load shedding / rate limiting** | Overload | Envoy rate limit, HPA, queue limits |
| **Redundancy** | Instance or node loss | replicas ≥ 2, pod anti-affinity, PodDisruptionBudgets |
| **Health checks** | Serving from broken instances | Readiness vs liveness probes (they're different!) |

**Cascading failure** is the classic large outage: one slow service → callers' threads fill up
→ retries multiply the load → everything falls over. Timeouts, retry budgets, and circuit breakers stop the chain.

## Chaos engineering
> "Breaking things on purpose to build confidence that the system withstands turbulent conditions."

### The method
1. Define the **steady state** with an SLI (e.g. checkout success ≥ 99.5%).
2. Write a **hypothesis**: "If one worker node dies, checkout SLI stays above 99.5%."
3. Limit the **blast radius** (one pod, one service, a short duration) and set an **abort condition**.
4. **Inject** the failure.
5. **Observe**: did the hypothesis hold?
6. **Learn**: fix the weakness, write a postmortem if you were surprised, and repeat with a larger blast radius.

Only run experiments while there's **error budget** left.

## Mapped to the lab

### Phase 5: resilience and chaos
| Experiment | Tool | Hypothesis to test |
|---|---|---|
| Kill random `cart` pods | Chaos Mesh PodChaos | Add-to-cart SLO holds (needs replicas ≥ 2 + readiness) |
| Drain a worker node | `kubectl drain` | All CUJs survive (needs PDBs + anti-affinity) |
| 500ms latency on `currency` | NetworkChaos | Checkout latency SLO holds (tests timeouts) |
| Packet loss to `payment` | NetworkChaos | Retries hide it without a retry storm |
| Kill Kafka | PodChaos | Checkout still succeeds; accounting catches up later (async decoupling) |
| Fail `ad` / `recommendation` | Flag or PodChaos | Pages still render (graceful degradation) |
| Stress CPU on a node | StressChaos | HPA scales; the noisy neighbour is contained by limits |

Hardening checklist to apply as experiments uncover gaps:
- [ ] Resource requests and limits on every container
- [ ] Separate readiness and liveness probes
- [ ] replicas ≥ 2 for CUJ services, plus a PodDisruptionBudget
- [ ] Topology spread / anti-affinity across the 2 workers
- [ ] HPA on frontend, checkout, product-catalog

### Phase 6: capacity
- [ ] k6 or Locust test ramping checkout traffic until the latency SLO breaks. That's your **capacity**.
- [ ] Plot throughput vs p99 and mark the "knee"
- [ ] Set HPA targets below the knee; document capacity + headroom in `docs/capacity-plan.md`
- [ ] Repeat with one node gone (N-1 capacity)

## Interview questions
1. How would you capacity-plan for a Black Friday sale?
2. What is a cascading failure, and how do you prevent one?
3. Readiness vs liveness probe. What goes wrong if you mix them up?
4. Why can retries make an outage worse? How do you retry safely?
5. How would you start a chaos engineering program safely?
6. Explain Little's Law and apply it.
