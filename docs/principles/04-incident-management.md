# 04: Incident Management

> The goal of incident response is to **restore service**, not to find the root cause.
> Root cause analysis happens later, in the postmortem.

## What counts as an incident?
An unplanned event that disrupts or degrades service, or threatens to, and needs a
coordinated response. Declare incidents **early and freely**. Downgrading one costs
almost nothing; declaring one late costs a lot.

Declare one if any of these is true:
- A paging SLO alert fired
- Users or customers report impact
- More than one person or team is needed
- You can't mitigate it within 15 minutes

## Severity levels

| Sev | Definition | Lab example | Response |
|---|---|---|---|
| **SEV1** | Critical CUJ down, or major user impact | Checkout failing for > 50% of users | All hands, IC assigned, status updates every 15 min, postmortem required |
| **SEV2** | Partial degradation of a CUJ | Checkout p99 at 5s; one product page erroring | IC assigned, updates every 30 min, postmortem required |
| **SEV3** | Minor, with a workaround or no user impact yet | Kafka lag growing, orders still accepted | Handled by on-call in working hours, postmortem optional |

## Incident lifecycle

```
Detect → Triage → Declare → Mitigate → Resolve → Postmortem → Follow up
  │         │         │          │          │           │             │
alert/   severity,  open      restore    root cause  blameless     action items
report   who owns   channel,  service    fixed       review        tracked to done
                    assign IC (rollback,
                              flag off,
                              scale)
```

### Key metrics
| Metric | From → To |
|---|---|
| **MTTD** (detect) | Impact starts → alert fires |
| **MTTA** (acknowledge) | Alert fires → human acknowledges |
| **MTTM** (mitigate) | Impact starts → users no longer affected |
| **MTTR** (resolve/restore) | Impact starts → fully resolved |

MTTM is the number users care about most.

## Roles (based on the Incident Command System)

| Role | Responsibilities | Does NOT |
|---|---|---|
| **Incident Commander (IC)** | Owns the incident, coordinates, makes decisions, assigns work, sets severity, declares it over | Debug or type commands |
| **Ops / Tech Lead** | Leads the hands-on investigation and mitigation | Talk to stakeholders |
| **Communications Lead** | Status page, stakeholder updates, customer comms | Guess at timelines |
| **Scribe** | Keeps the timeline: what was seen, what was done, when | — |

In a small team, one person may hold several roles. The IC and the person debugging should still be different people whenever possible.

## Response playbook
1. **Acknowledge** the page.
2. **Assess impact** with the SLO dashboard. Which CUJ, how many users, since when?
3. **Declare** the incident and set severity. Open `#inc-YYYYMMDD-short-name`. Assign IC.
4. **Mitigate first.** Standard mitigations, in rough order of preference:
   - Roll back the most recent change (deploy, config, feature flag)
   - Turn off a feature flag, or degrade gracefully
   - Drain or move traffic away from the bad zone or instance
   - Scale up or out
   - Restart (last resort, since it destroys evidence)
5. **Communicate** on a regular schedule, even when the update is "no change".
6. **Verify recovery** using the SLI, not by assuming it's fixed.
7. **Resolve**, and schedule the postmortem within 5 working days.

### Status update template
```
[SEV2] Checkout errors: UPDATE #3 (14:30 UTC)
Impact: ~20% of checkouts failing since 14:02 UTC
Current status: Mitigating. Payment feature flag disabled; error rate falling
Next steps: Confirm recovery on SLO dashboard; identify trigger
Next update: 15:00 UTC
IC: @alice | Ops: @bob
```

## Mapped to the lab: game days (Phase 4)

The Astronomy Shop's flagd flags create **repeatable, realistic incidents**. Run each one as a full drill:

| Scenario | Flag | Expected symptom | Severity | Mitigation to find |
|---|---|---|---|---|
| Payment outage | `paymentFailure` | Checkout errors | SEV1/2 | Identify payment service, disable flag |
| Bad product | `productCatalogFailure` | One product page errors | SEV2/3 | Trace to product-catalog |
| Noisy neighbour | `adServiceHighCpu` | Latency on browse | SEV2 | Saturation on ad service, scale or limit it |
| GC pauses | `adServiceManualGc` | Latency spikes | SEV3 | JVM GC metrics |
| Memory leak | `recommendationCacheFailure` | Rising memory, OOM kills | SEV2 | Memory growth, restart and fix |
| Async backlog | `kafkaQueueProblems` | Consumer lag, delayed accounting | SEV3 | Kafka lag dashboard |
| Traffic spike | `loadGeneratorFloodHomepage` | Saturation, latency | SEV2 | Scaling, rate limiting |

Available flag names vary by demo version, so check the flag UI at `/feature`.

### How to run a game day
1. One person (the **game master**) secretly turns on a flag and doesn't tell the responders which one.
2. Responders take on the IC, Ops, and Comms roles and work only from alerts and dashboards.
3. Record MTTD, MTTM, and the budget consumed.
4. Write a postmortem in `postmortems/`.
5. Practicing alone? Use a randomizer script to pick the flag and start time.

## Common mistakes
- Debugging for an hour before mitigating. Roll back first.
- The IC debugging, so nobody is coordinating.
- No timeline, which leaves the postmortem to be reconstructed from memory.
- Declaring "fixed" without checking the SLI.
- Heroics: one person fixing it silently with no record.

## Interview questions
1. Walk me through how you'd handle a checkout outage from the moment you're paged.
2. What does an Incident Commander do, and why shouldn't they debug?
3. How do you decide severity?
4. Mitigation vs resolution. Why mitigate first?
5. Tell me about the worst incident you handled. Use a STAR story from your game-day postmortems.
6. How do you communicate during an incident to execs vs engineers?
