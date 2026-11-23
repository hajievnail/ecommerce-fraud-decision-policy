-- 09_failure.sql
-- Issue 9: Failure analysis — missed frauds (test), false blocks (test), summary marts, numbers freeze.
-- Needs: txn_scored (view, 07_scorecard.sql), txn_binned (view, 06_binning.sql).

CREATE OR REPLACE TABLE fail_params AS SELECT 519.9 AS review_threshold, 533.5 AS block_threshold;

CREATE OR REPLACE TABLE fail_baseline_amount AS
SELECT min(amt) AS amount_threshold FROM (
    SELECT TransactionAmt AS amt, count(*) AS c,
           sum(count(*)) OVER (ORDER BY TransactionAmt DESC) AS n_ge
    FROM txn_scored WHERE period = 'validation' GROUP BY TransactionAmt
) sub WHERE n_ge <= 0.01 * (SELECT count(*) FROM txn_scored WHERE period = 'validation');

CREATE OR REPLACE TABLE fail_actions_test AS
SELECT s.TransactionID, s.day, s.TransactionAmt, s.isFraud, s.points,
       CASE WHEN s.TransactionAmt >= b.amount_threshold THEN 'review' ELSE 'approve' END AS baseline_action,
       CASE WHEN p.block_threshold IS NOT NULL AND s.points >= p.block_threshold THEN 'block'
            WHEN s.points >= p.review_threshold THEN 'review'
            ELSE 'approve' END AS score_action
FROM txn_scored s
CROSS JOIN fail_params p
CROSS JOIN fail_baseline_amount b
WHERE s.period = 'test';

CREATE OR REPLACE TABLE fail_missed_top AS
SELECT f.TransactionID, f.day, f.TransactionAmt, round(f.points, 1) AS points,
       t.b_product, t.b_amount, t.b_email, t.b_card6, t.b_device, t.b_dist1, t.b_hour, t.b_n24h, t.b_gap
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 1 AND f.score_action <> 'block'
ORDER BY f.TransactionAmt DESC
LIMIT 20;

CREATE OR REPLACE TABLE fail_false_blocks_top AS
SELECT f.TransactionID, f.day, f.TransactionAmt, round(f.points, 1) AS points,
       t.b_product, t.b_amount, t.b_email, t.b_card6, t.b_device, t.b_dist1, t.b_hour, t.b_n24h, t.b_gap
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 0 AND f.score_action = 'block'
ORDER BY f.TransactionAmt DESC
LIMIT 20;

CREATE OR REPLACE TABLE fail_missed_by_var AS
SELECT 'product' AS var, t.b_product AS bin,
       count(*) AS n, sum(f.TransactionAmt) AS usd,
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1) AS pct_of_missed,
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1) AS pct_of_missed_usd
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 1 AND f.score_action <> 'block'
GROUP BY t.b_product
UNION ALL
SELECT 'amount', t.b_amount, count(*), sum(f.TransactionAmt),
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1),
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1)
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 1 AND f.score_action <> 'block'
GROUP BY t.b_amount
UNION ALL
SELECT 'device', t.b_device, count(*), sum(f.TransactionAmt),
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1),
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1)
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 1 AND f.score_action <> 'block'
GROUP BY t.b_device
UNION ALL
SELECT 'gap', t.b_gap, count(*), sum(f.TransactionAmt),
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1),
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1)
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 1 AND f.score_action <> 'block'
GROUP BY t.b_gap;

CREATE OR REPLACE TABLE fail_false_by_var AS
SELECT 'product' AS var, t.b_product AS bin,
       count(*) AS n, sum(f.TransactionAmt) AS usd,
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1) AS pct_of_false,
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1) AS pct_of_false_usd
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 0 AND f.score_action = 'block'
GROUP BY t.b_product
UNION ALL
SELECT 'amount', t.b_amount, count(*), sum(f.TransactionAmt),
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1),
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1)
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 0 AND f.score_action = 'block'
GROUP BY t.b_amount
UNION ALL
SELECT 'device', t.b_device, count(*), sum(f.TransactionAmt),
       round(100.0 * count(*) / NULLIF(sum(count(*)) OVER (), 0), 1),
       round(100.0 * sum(f.TransactionAmt) / NULLIF(sum(sum(f.TransactionAmt)) OVER (), 0), 1)
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
WHERE f.isFraud = 0 AND f.score_action = 'block'
GROUP BY t.b_device;

CREATE OR REPLACE TABLE fail_product_device AS
SELECT t.b_product, t.b_device,
       count(*) AS orders, sum(f.isFraud) AS frauds,
       sum(CASE WHEN f.isFraud = 1 AND f.score_action <> 'block' THEN 1 ELSE 0 END) AS missed,
       sum(CASE WHEN f.isFraud = 1 AND f.score_action <> 'block' THEN f.TransactionAmt ELSE 0 END) AS missed_usd,
       sum(CASE WHEN f.isFraud = 0 AND f.score_action = 'block' THEN 1 ELSE 0 END) AS false_blocks,
       sum(CASE WHEN f.isFraud = 0 AND f.score_action = 'block' THEN f.TransactionAmt ELSE 0 END) AS false_blocked_usd
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
GROUP BY t.b_product, t.b_device
ORDER BY t.b_product, t.b_device;

CREATE OR REPLACE TABLE fail_amount_device AS
SELECT t.b_amount, t.b_device,
       count(*) AS orders,
       sum(CASE WHEN f.isFraud = 1 AND f.score_action <> 'block' THEN 1 ELSE 0 END) AS missed,
       sum(CASE WHEN f.isFraud = 1 AND f.score_action <> 'block' THEN f.TransactionAmt ELSE 0 END) AS missed_usd,
       sum(CASE WHEN f.isFraud = 0 AND f.score_action = 'block' THEN 1 ELSE 0 END) AS false_blocks,
       sum(CASE WHEN f.isFraud = 0 AND f.score_action = 'block' THEN f.TransactionAmt ELSE 0 END) AS false_blocked_usd
FROM fail_actions_test f JOIN txn_binned t USING (TransactionID)
GROUP BY t.b_amount, t.b_device
ORDER BY t.b_amount, t.b_device;

CREATE OR REPLACE TABLE fail_freeze AS
SELECT count(*) AS orders, sum(isFraud) AS frauds,
       round(100.0 * sum(isFraud) / count(*), 2) AS fraud_rate_pct,
       sum(TransactionAmt) AS total_usd,
       count(*) FILTER (WHERE score_action = 'block') AS blocked,
       count(*) FILTER (WHERE score_action = 'review') AS reviewed,
       count(*) FILTER (WHERE score_action <> 'approve' AND isFraud = 1) AS frauds_caught,
       count(*) FILTER (WHERE score_action = 'approve' AND isFraud = 1) AS frauds_missed,
       sum(TransactionAmt) FILTER (WHERE score_action = 'approve' AND isFraud = 1) AS fraud_usd_missed,
       count(*) FILTER (WHERE score_action = 'block' AND isFraud = 0) AS false_blocks,
       sum(TransactionAmt) FILTER (WHERE score_action = 'block' AND isFraud = 0) AS false_blocked_usd
FROM fail_actions_test;

SELECT 'missed frauds (test)' AS info, * FROM fail_missed_top;
SELECT 'false blocks (test)' AS info, * FROM fail_false_blocks_top;
SELECT 'missed by var' AS info, * FROM fail_missed_by_var ORDER BY var, n DESC;
SELECT 'false by var' AS info, * FROM fail_false_by_var ORDER BY var, n DESC;
SELECT 'product x device' AS info, * FROM fail_product_device;
SELECT 'amount x device' AS info, * FROM fail_amount_device;
SELECT 'freeze' AS info, * FROM fail_freeze;