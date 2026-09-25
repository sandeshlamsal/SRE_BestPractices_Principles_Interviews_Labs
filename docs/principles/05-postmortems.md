# 05: Postmortems

> "Failure is the best teacher, but only if you take notes."

## What it is
A **postmortem** (also called an incident review or retrospective) is a written record of an incident:
its impact, what happened, why it happened, and **what we will change so it doesn't happen again
or hurts less next time**.

## Blameless culture
A **blameless** postmortem assumes that everyone acted reasonably given the information,
tools, and pressures they had at the time. It asks:

- ❌ "Who pushed the bad config?"
- ✅ "Why was it possible to push a bad config without a check or a canary catching it?"

**Why this matters:** if people are blamed, they hide mistakes, and the organization stops learning.
"Human error" is where the investigation should start, never the conclusion.

## When a postmortem is required
- Every SEV1 and SEV2
- Any incident that used **> 10% of an error budget**
- Data loss, security incidents, or rollbacks with user impact
- Any case where monitoring failed to detect a problem that users reported
- Any **chaos experiment that disproved its hypothesis** (Phase 5)

## Structure
Use [the template](../templates/postmortem.md). The key sections:

| Section | Questions to answer |
|---|---|
| **Summary** | Could an exec understand it in 30 seconds? |
| **Impact** | Users affected, failed requests, budget consumed, duration |
| **Timeline** | Timestamped facts, from the scribe's log |
| **Root cause & trigger** | Trigger = what started it. Root causes = why the system was vulnerable. Usually there are several. |
| **Detection** | How did we find out? How long did it take (MTTD)? |
| **Response** | What helped, what slowed us down? |
| **Went well / went wrong / got lucky** | "Got lucky" often shows the next incident waiting to happen |
| **Action items** | Specific, owned, dated, and tracked |

## Root cause techniques
- **5 Whys**: keep asking "why" until you reach a systemic cause. Branch when there are several causes.
- **Contributing factors**: complex systems rarely have one root cause. List everything that had to line up for the incident to happen.
- **Timeline analysis**: find the gaps. Why did 20 minutes pass between the alert and the first action?

### Example: 5 Whys for a lab incident
1. Why did checkouts fail? → The payment service returned errors.
2. Why? → A feature flag enabled a failure path in 50% of charges.
3. Why wasn't it caught before users saw it? → Flag changes don't go through a canary.
4. Why did detection take 12 minutes? → We only had a 1h-window alert, with no short confirmation window.
5. Why was mitigation slow? → The runbook didn't mention checking recent flag changes.

**Action items:** a canary process for flag changes (prevent), multi-window burn alerts (detect), and adding "check flag history" to the runbook (mitigate).

## Good action items
Classify each one:

| Type | Goal | Example |
|---|---|---|
| **Prevent** | Stop it recurring | Validate config in CI |
| **Detect** | Find it faster | Add a burn-rate alert |
| **Mitigate** | Reduce impact or speed recovery | Auto-rollback; a runbook step |

Action items should be **SMART**: specific, owned by a named person, with a date and a tracking ticket.
"Be more careful" is not an action item.

## Postmortem review
- Schedule it within **5 working days** while memories are fresh.
- The meeting reviews the draft. It isn't where the draft gets written.
- Share widely. A postmortem only a few people read teaches only a few people.
- Track action item completion. Unfinished actions are one of the most common reasons incidents repeat.

## Mapped to the lab
- Every **Phase 4 game day** produces `postmortems/YYYY-MM-DD-<slug>.md`
- Every **Phase 5 chaos surprise** produces a postmortem
- Keep an index in `postmortems/README.md` with date, sev, MTTD, MTTM, budget used, and action status, so you can **see MTTD/MTTM trend down** over time
- Each postmortem becomes a **STAR interview story** in `interviews/`

## Common mistakes
- Writing "root cause: human error".
- Action items with no owner or date.
- A timeline full of opinions instead of facts.
- Skipping postmortems for "small" incidents that keep recurring.
- Postmortems that get filed and never read.

## Interview questions
1. What makes a postmortem "blameless"? Why does it matter?
2. Walk me through a postmortem you wrote. What were the action items?
3. How do you make sure action items actually get done?
4. What's wrong with "root cause: human error"?
5. When is a postmortem not needed?
