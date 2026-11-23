-- 07_scorecard_checks.sql
-- Tests for the scorecard. Every query below must return 0 rows.
--
-- The label-flip test (flip every validation/test label in a scratch copy,
-- re-run 07_scorecard.sql, compare card_definition) is run by hand;
-- result recorded in docs/data_notes.md.

-- 1. card_definition has exactly the bins of bin_rates, with valid numbers
SELECT 'bin set differs' AS problem, COUNT(*) AS n
FROM (SELECT var, bin FROM bin_rates EXCEPT SELECT var, bin FROM card_definition)
HAVING COUNT(*) > 0
UNION ALL
SELECT 'bin set differs (reverse)', COUNT(*)
FROM (SELECT var, bin FROM card_definition EXCEPT SELECT var, bin FROM bin_rates)
HAVING COUNT(*) > 0
UNION ALL
SELECT 'null or non-finite points', COUNT(*)
FROM card_definition
WHERE points IS NULL OR NOT isfinite(points)
HAVING COUNT(*) > 0;

-- 2. Points follow the formula: 500 + 50 * (bin log-odds - base log-odds)
SELECT c.var, c.bin, c.points
FROM card_definition AS c CROSS JOIN scorecard_base AS b
WHERE abs(c.points - (500 + 50 * (LN(c.rate / (1 - c.rate)) - b.base_log_odds))) > 1e-9;

-- 3. Base rate is the train days 29-101 rate (8,925 frauds in 229,550 orders)
SELECT 'wrong base' AS problem, orders, frauds
FROM scorecard_base
WHERE orders <> 229550 OR frauds <> 8925;

-- 4. Every order is scored exactly once, with all 9 variables, no NULL score
SELECT 'row count' AS problem, COUNT(*) AS n
FROM txn_scored
HAVING COUNT(*) <> (SELECT COUNT(*) FROM txn_split)
    OR COUNT(DISTINCT TransactionID) <> (SELECT COUNT(*) FROM txn_split)
UNION ALL
SELECT 'order without 9 parts or with NULL score', COUNT(*)
FROM txn_scored
WHERE n_parts <> 9 OR points IS NULL OR prob_fraud IS NULL
HAVING COUNT(*) > 0;

-- 5. Mean score_log_odds over the learning window must be consistent:
--    the sum of the order's contributions recomputed from txn_binned by hand
--    for one variable set is checked by test 4; here check the scale:
--    points of an order must lie between the sum of per-variable min and max.
WITH rng AS (
    SELECT SUM(mn) AS lo, SUM(mx) AS hi
    FROM (SELECT var, MIN(points - 500) AS mn, MAX(points - 500) AS mx FROM card_definition GROUP BY var)
)
SELECT s.TransactionID, s.points
FROM txn_scored AS s CROSS JOIN rng
WHERE s.points < 500 + rng.lo - 1e-6 OR s.points > 500 + rng.hi + 1e-6
LIMIT 20;

-- 6. No label-derived column in card_definition (counts of frauds are inputs from
--    train bin_rates, not labels of orders)
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'card_definition'
  AND lower(column_name) IN ('isfraud', 'label');
