# Hours log

| Session | Date | Planned deliverable | Actual hours | Done? | Notes |
|---|---|---|---|---|---|
| 1 | 2026-10-19 | Repo and load | 0.6 | Yes | All 4 load checks pass; identity coverage 24.4% (144,233 rows). Repo created and cloned on 2026-10-02 |
| 2 | 2026-10-20 to 2026-10-23 | Split and rebuild | 1.0 | Yes | Days 1-182, no gaps; cut-offs at days 101 / 141 (60.32 / 20.12 / 19.56%); validation fraud rate higher (3.94%); full rebuild from scratch passes all 7 checks; data frozen |
| 3 | 2026-10-23 to 2026-10-24 | Data quality | 4.0 | Yes | Build ~2 h, review ~2 h. 7 zero-row checks pass (check 6 rewritten after flip-testing); missing-value profile overall and by period; drift: M/D/V columns fill in during train, identity burst on days 15-28; missingness mostly decided by product; full rebuild 59 s |
| 4 | 2026-10-26 | Exploration and baseline | 2.0 | Yes | Train-only fraud rates by product, card, email, amount, hour, identity, distance (added after audit); product C 3.2x average and the main confounder; $200-1,000 orders hold 56% of fraud dollars; baseline chosen: review orders above an amount threshold set on validation to fit capacity, plus approve-all reference; three self-audits fixed wording/number errors; leakage test (flipped non-train labels) passes; full rebuild passes |

## Plan changes

| Date | Change | Reason |
|---|---|---|
| 2026-10-02 | Whole schedule shifted by one day | Start moved from 2026-10-01 to 2026-10-02 |
| 2026-10-19 | Project restarted at Day 1; sessions every other day, Day 15 (v1.0) ~2026-11-16, buffer ~2026-11-18, feedback post ~2026-11-20 | Break between 2026-10-02 and 2026-10-19 |
| 2026-10-23 | Day 2 started a day early (2026-10-20) and was done in three short sittings, finishing 2026-10-23 | Day 1 took under an hour; Day 2 fitted around other commitments |
