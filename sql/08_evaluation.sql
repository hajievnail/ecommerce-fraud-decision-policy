-- 08_evaluation.sql
-- Issue 8: evaluate the scorecard, choose review / block thresholds on validation,
-- compare with the baseline under the same capacity rule, run the test period once.
-- Needs: txn_scored (07_scorecard.sql). Labels are used only inside this file, for evaluation.

-- 0. Cost assumptions (defaults, to be covered by sensitivity analysis in Issue 11)
--    review_cost        : dollars per manually reviewed order
--    fraud_loss         : share of the order amount lost when a fraud is approved
--    false_decline_loss : share of the order amount lost when a legit order is blocked
--                         (default 10% of the amount, a margin-based guess)
--    review_capacity    : reviews allowed per day, as a share of that period's orders;
--                         "fits" = on average over the period (per-day overload is reported separately)
--    Reviewers are assumed to decide correctly: a reviewed fraud is stopped, a reviewed legit order is approved.
CREATE OR REPLACE TABLE eval_params AS
SELECT 5.0 AS review_cost, 1.0 AS fraud_loss, 0.10 AS false_decline_loss, 0.01 AS review_capacity;

-- 1. Score buckets (0.1 point resolution) per period, and cumulative "score >= bucket" counts
CREATE OR REPLACE TABLE score_buckets AS
SELECT period,
       CAST(floor(points * 10) AS INTEGER) AS b,
       count(*) AS n,
       sum(isFraud) AS frauds,
       count(*) - sum(isFraud) AS legits,
       coalesce(sum(TransactionAmt) FILTER (WHERE isFraud = 1), 0) AS fraud_usd,
       coalesce(sum(TransactionAmt) FILTER (WHERE isFraud = 0), 0) AS legit_usd
FROM txn_scored
GROUP BY period, b;

CREATE OR REPLACE TABLE score_cum AS
SELECT period, b,
       sum(n)         OVER w AS n_ge,
       sum(frauds)    OVER w AS f_ge,
       sum(fraud_usd) OVER w AS fusd_ge,
       sum(legit_usd) OVER w AS lusd_ge
FROM score_buckets
WINDOW w AS (PARTITION BY period ORDER BY b DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW);

-- 2. Ranking quality per period: AUC (ties count half) and KS
CREATE OR REPLACE TABLE score_quality AS
WITH c AS (
    SELECT period, b, frauds, legits,
           sum(frauds) OVER w AS f_le, sum(legits) OVER w AS l_le,
           sum(frauds) OVER (PARTITION BY period) AS f_tot,
           sum(legits) OVER (PARTITION BY period) AS l_tot
    FROM score_buckets
    WINDOW w AS (PARTITION BY period ORDER BY b ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
)
SELECT period,
       round(sum(frauds * ((l_le - legits) + 0.5 * legits)) / (any_value(f_tot) * any_value(l_tot)), 4) AS auc,
       round(max(abs(f_le * 1.0 / f_tot - l_le * 1.0 / l_tot)), 4) AS ks
FROM c
GROUP BY period;

-- 3. Score deciles (decile 1 = highest scores) per period
CREATE OR REPLACE TABLE score_deciles AS
WITH r AS (
    SELECT period, isFraud, TransactionAmt,
           ntile(10) OVER (PARTITION BY period ORDER BY points DESC) AS decile
    FROM txn_scored
),
d AS (
    SELECT period, decile, count(*) AS orders, sum(isFraud) AS frauds,
           coalesce(sum(TransactionAmt) FILTER (WHERE isFraud = 1), 0) AS fraud_usd
    FROM r GROUP BY period, decile
)
SELECT period, decile, orders, frauds,
       round(100.0 * frauds / orders, 2) AS fraud_rate_pct,
       round(100.0 * sum(frauds) OVER w / sum(frauds) OVER (PARTITION BY period), 1) AS cum_pct_frauds,
       round(100.0 * sum(fraud_usd) OVER w / sum(fraud_usd) OVER (PARTITION BY period), 1) AS cum_pct_fraud_usd
FROM d
WINDOW w AS (PARTITION BY period ORDER BY decile ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
ORDER BY period, decile;

-- 4. Baseline (Issue 4): review the largest orders. Amount threshold set on validation:
--    the lowest amount whose review load fits the capacity (same rule as the scorecard policy).
CREATE OR REPLACE TABLE baseline_amount_threshold AS
WITH a AS (
    SELECT TransactionAmt AS amt, count(*) AS c FROM txn_scored WHERE period = 'validation' GROUP BY amt
),
cum AS (SELECT amt, sum(c) OVER (ORDER BY amt DESC) AS n_ge FROM a)
SELECT min(amt) AS amount_threshold
FROM cum
WHERE n_ge <= (SELECT floor(p.review_capacity * count(*)) FROM txn_scored, eval_params p
               WHERE period = 'validation' GROUP BY p.review_capacity);

-- 5. Scorecard threshold grid on VALIDATION: every (review, block) pair of buckets.
--    block_b = 1000000 means "no block band". Orders with score >= block: declined; review <= score < block: reviewed.
CREATE OR REPLACE TABLE val_grid AS
WITH v AS (SELECT * FROM score_cum WHERE period = 'validation'),
vb AS (SELECT b, n_ge, fusd_ge, lusd_ge FROM v UNION ALL SELECT 1000000, 0, 0, 0),
tot AS (
    SELECT sum(n) AS n, sum(frauds) AS f, sum(fraud_usd) AS fusd
    FROM score_buckets WHERE period = 'validation'
),
p AS (SELECT * FROM eval_params)
SELECT r.b AS review_b,
       k.b AS block_b,
       r.b / 10.0 AS review_threshold,
       CASE WHEN k.b = 1000000 THEN NULL ELSE k.b / 10.0 END AS block_threshold,
       r.n_ge - k.n_ge AS reviewed,
       k.n_ge AS blocked,
       round(100.0 * (r.n_ge - k.n_ge) / tot.n, 3) AS pct_reviewed,
       round(100.0 * r.f_ge / tot.f, 1) AS pct_frauds_caught,
       round(100.0 * r.fusd_ge / tot.fusd, 1) AS pct_fraud_usd_caught,
       round(p.review_cost * (r.n_ge - k.n_ge)
             + p.fraud_loss * (tot.fusd - r.fusd_ge)
             + p.false_decline_loss * k.lusd_ge, 0) AS total_cost,
       (r.n_ge - k.n_ge) <= floor(p.review_capacity * tot.n) AS fits_capacity
FROM v r
JOIN vb k ON k.b > r.b
CROSS JOIN tot CROSS JOIN p;

-- 6. Best thresholds: lowest validation cost among pairs that fit the review capacity
CREATE OR REPLACE TABLE best_thresholds AS
SELECT review_b, block_b, review_threshold, block_threshold, reviewed, blocked,
       pct_reviewed, pct_frauds_caught, pct_fraud_usd_caught, total_cost,
       CASE WHEN block_b = 1000000 THEN NULL ELSE block_b END AS block_b_used
FROM val_grid
WHERE fits_capacity
ORDER BY total_cost, review_b DESC
LIMIT 1;

-- Same, without a block band (to see what blocking adds)
CREATE OR REPLACE TABLE best_review_only AS
SELECT review_b, review_threshold, reviewed, pct_reviewed, pct_frauds_caught, pct_fraud_usd_caught, total_cost
FROM val_grid
WHERE fits_capacity AND block_b = 1000000
ORDER BY total_cost, review_b DESC
LIMIT 1;

-- 7. Decisions for every validation and test order under both policies
CREATE OR REPLACE TABLE txn_actions AS
SELECT s.TransactionID, s.day, s.period, s.TransactionAmt, s.isFraud, s.points,
       CASE WHEN s.TransactionAmt >= b.amount_threshold THEN 'review' ELSE 'approve' END AS baseline_action,
       CASE WHEN t.block_b_used IS NOT NULL AND floor(s.points * 10) >= t.block_b_used THEN 'block'
            WHEN floor(s.points * 10) >= t.review_b THEN 'review'
            ELSE 'approve' END AS score_action
FROM txn_scored s
CROSS JOIN baseline_amount_threshold b
CROSS JOIN best_thresholds t
WHERE s.period IN ('validation', 'test');

-- 8. Policy results (validation: used for choosing; test: judged once)
CREATE OR REPLACE TABLE policy_results AS
WITH long AS (
    SELECT period, 'approve all' AS policy, day, TransactionAmt, isFraud, 'approve' AS action FROM txn_actions
    UNION ALL
    SELECT period, 'baseline (largest orders)', day, TransactionAmt, isFraud, baseline_action FROM txn_actions
    UNION ALL
    SELECT period, 'scorecard', day, TransactionAmt, isFraud, score_action FROM txn_actions
),
agg AS (
    SELECT period, policy,
           count(*) AS orders,
           count(*) FILTER (WHERE action = 'review') AS reviewed,
           count(*) FILTER (WHERE action = 'block') AS blocked,
           count(*) FILTER (WHERE action <> 'approve' AND isFraud = 1) AS frauds_caught,
           sum(isFraud) AS frauds_total,
           coalesce(sum(TransactionAmt) FILTER (WHERE action <> 'approve' AND isFraud = 1), 0) AS fraud_usd_caught,
           coalesce(sum(TransactionAmt) FILTER (WHERE isFraud = 1), 0) AS fraud_usd_total,
           coalesce(sum(TransactionAmt) FILTER (WHERE action = 'approve' AND isFraud = 1), 0) AS fraud_usd_missed,
           coalesce(sum(TransactionAmt) FILTER (WHERE action = 'block' AND isFraud = 0), 0) AS legit_usd_blocked
    FROM long GROUP BY period, policy
)
SELECT period, policy, orders, reviewed, blocked,
       round(100.0 * reviewed / orders, 3) AS pct_reviewed,
       frauds_caught,
       round(100.0 * frauds_caught / frauds_total, 1) AS pct_frauds_caught,
       round(100.0 * fraud_usd_caught / fraud_usd_total, 1) AS pct_fraud_usd_caught,
       round(fraud_usd_missed) AS fraud_usd_missed,
       round(legit_usd_blocked) AS legit_usd_blocked,
       round(p.review_cost * reviewed + p.fraud_loss * fraud_usd_missed + p.false_decline_loss * legit_usd_blocked) AS total_cost
FROM agg CROSS JOIN eval_params p
ORDER BY period DESC, total_cost DESC;

-- 9. Per-day review load against capacity (the rule above is an average; this shows the spread)
CREATE OR REPLACE TABLE capacity_by_policy AS
WITH d AS (
    SELECT period, day, count(*) AS orders,
           count(*) FILTER (WHERE baseline_action = 'review') AS base_reviewed,
           count(*) FILTER (WHERE score_action = 'review') AS score_reviewed
    FROM txn_actions GROUP BY period, day
)
SELECT period, 'baseline (largest orders)' AS policy,
       round(100.0 * count(*) FILTER (WHERE base_reviewed > p.review_capacity * orders) / count(*), 1) AS pct_days_over_capacity,
       round(100.0 * max(base_reviewed * 1.0 / orders), 2) AS worst_day_pct_reviewed
FROM d CROSS JOIN eval_params p GROUP BY period
UNION ALL
SELECT period, 'scorecard',
       round(100.0 * count(*) FILTER (WHERE score_reviewed > p.review_capacity * orders) / count(*), 1),
       round(100.0 * max(score_reviewed * 1.0 / orders), 2)
FROM d CROSS JOIN eval_params p GROUP BY period;

-- Display
SELECT 'cost assumptions' AS info, * FROM eval_params;
SELECT 'ranking quality' AS info, * FROM score_quality ORDER BY period;
SELECT 'deciles' AS info, * FROM score_deciles;
SELECT 'baseline amount threshold' AS info, * FROM baseline_amount_threshold;
SELECT 'best thresholds (validation)' AS info, * FROM best_thresholds;
SELECT 'best without block (validation)' AS info, * FROM best_review_only;
SELECT 'policy results' AS info, * FROM policy_results;
SELECT 'capacity by day' AS info, * FROM capacity_by_policy ORDER BY period, policy;
