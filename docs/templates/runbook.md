# Runbook: <AlertName>

**Severity:** page / ticket  **SLO:** <link>  **Dashboard:** <link>

## What this alert means
What users are experiencing, in one or two sentences.

## Triage (first 5 minutes)
1. Check the dashboard for which endpoints and services are affected.
2. Check recent changes (deploys, flags, config).
3. Check dependencies.

## Mitigation
- Roll back: `helm rollback ...`
- Disable the feature flag: ...
- Scale: ...

## Escalation
Who to call and when.

## Verify recovery
Which SLI should return to normal, and how to confirm it.
