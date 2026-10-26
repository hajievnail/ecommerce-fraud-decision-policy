# Hours log

| Session | Date | Planned deliverable | Actual hours | Done? | Notes |
|---|---|---|---|---|---|
| 1 | 2026-10-19 | Repo and load | 0.6 | Yes | All 4 load checks pass; identity coverage 24.4% (144,233 rows). Repo created and cloned on 2026-10-02 |
| 2 | 2026-10-20 to 2026-10-23 | Split and rebuild | 1.0 | Yes | Days 1-182, no gaps; cut-offs at days 101 / 141 (60.32 / 20.12 / 19.56%); validation fraud rate higher (3.94%); full rebuild from scratch passes all 7 checks; data frozen |
| 3 | 2026-10-23 to 2026-10-24 | Data quality | 4.0 | Yes | Build ~2 h, review ~2 h. 7 zero-row checks pass (check 6 rewritten after flip-testing); missing-value profile overall and by period; drift: M/D/V columns fill in during train, identity burst on days 15-28; missingness mostly decided by product; full rebuild 59 s |
| 4 | 2026-10-26 | Exploration and baseline | 2.0 | Yes | Train-only fraud rates by product, card, email, amount, hour, identity, distance (added after audit); product C 3.2x average and the main confounder; $200-1,000 orders hold 56% of fraud dollars; baseline chosen: review orders above an amount threshold set on validation to fit capacity, plus approve-all reference; three self-audits fixed wording/number errors; leakage test (flipped non-train labels) passes; full rebuild passes |
| 5 | 2026-10-26 | Card identity and history features | 2.5 | Yes | Build ~2 h, review ~0.5 h. `day - D1` tested against a shuffled-D1 placebo (clusters far more than chance); card ID = card1 + addr1 + (day - D1), 217,020 IDs; 7 point-in-time features (strictly earlier orders only); truncation and label-flip leakage tests pass, plus a brute-force recompute; train-only signal: recency and 24 h velocity strong within W, weak within C; left censoring noted; full rebuild 63 s |

## Plan changes

| Date | Change | Reason |
|---|---|---|
| 2026-10-02 | Whole schedule shifted by one day | Start moved from 2026-10-01 to 2026-10-02 |
| 2026-10-19 | Project restarted at Day 1; sessions every other day, Day 15 (v1.0) ~2026-11-16, buffer ~2026-11-18, feedback post ~2026-11-20 | Break between 2026-10-02 and 2026-10-19 |
| 2026-10-23 | Day 2 started a day early (2026-10-20) and was done in three short sittings, finishing 2026-10-23 | Day 1 took under an hour; Day 2 fitted around other commitments |
| 2026-10-26 | Checkpoint after session 4: on track (4 sessions, 7.6 h). The 3 h limit now applies to build work only; the learning review after each session is logged separately in the Notes column | Day 3 went to 4 h only because of the review; reviews are part of learning and should not be rushed |
| 2026-10-26 | P1 gets a planned v1.1 after v1.0: one ML model and an online demo app (see the ideas table below) | Portfolio decision: the two main projects both show ML and a deployed demo, on different data (transactions here, text in P2) |
| 2026-10-26 | No fixed deadline: applications now start in January 2027. Keep the session rhythm, but dates are targets, not limits | Change in the user's job-search timing |

## Ideas for after v1.0 (ML and app now planned as v1.1; details decided after Day 15)

| Date | Idea | Note |
|---|---|---|
| 2026-10-26 | v1.1: one ML model (e.g. LightGBM in Python) trained on the same train period, run through the same thresholds, capacity rule and test evaluation, compared with the scorecard and the baseline | Answers "why no ML?" with a number; reuses the whole pipeline; ~2-3 sessions |
| 2026-10-26 | Interactive online page (e.g. Streamlit) with a threshold what-if | Lower value than ML (Power BI already shows the what-if); aggregated results only, because the competition rules forbid redistributing the data |
