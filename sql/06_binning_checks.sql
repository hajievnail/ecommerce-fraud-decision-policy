-- 06_binning_checks.sql
-- Tests for the scorecard bins. Every query below must return 0 rows.
-- If one returns rows, it shows (up to 20) offending orders or bins.
--
-- Label safety: the bin edges are fixed constants in 06_binning.sql, and check 4
-- shows no label column reaches txn_binned. The history bins come from
-- card_features, which passed its own leakage tests in session 5.
-- The label-flip test (flip every non-train label in a scratch copy, re-run
-- 06_binning.sql, compare bin_rates) needs a second database file, so it is run
-- by hand and recorded in docs/data_notes.md (passed 2026-11-20).

-- 1. Exactly one binned row per order
--    Expected: 0 rows returned
SELECT 'row count' AS problem,
       (SELECT COUNT(*) FROM txn_binned) AS n_binned,
       (SELECT COUNT(*) FROM txn_split)  AS n_orders
WHERE (SELECT COUNT(*) FROM txn_binned) <> (SELECT COUNT(*) FROM txn_split)
   OR (SELECT COUNT(DISTINCT TransactionID) FROM txn_binned) <> (SELECT COUNT(*) FROM txn_split);

-- 2. Every order has a bin for every variable (no NULL bin), in every period
--    Expected: 0 rows returned
SELECT TransactionID, period, COLUMNS('^b_')
FROM txn_binned
WHERE b_product IS NULL OR b_amount IS NULL OR b_email IS NULL OR b_card6 IS NULL
   OR b_device  IS NULL OR b_dist1  IS NULL OR b_hour  IS NULL OR b_n24h  IS NULL
   OR b_gap     IS NULL
LIMIT 20;

-- 3. Every bin that occurs in ANY period has a learned rate in bin_rates
--    (otherwise a validation or test order would get no points in Issue 7)
--    Expected: 0 rows returned
SELECT DISTINCT replace(u.var, 'b_', '') AS var, u.bin, 'bin has no learned rate' AS problem
FROM (UNPIVOT (SELECT COLUMNS('^b_') FROM txn_binned) ON COLUMNS('^b_') INTO NAME var VALUE bin) AS u
ANTI JOIN bin_rates AS r ON r.var = replace(u.var, 'b_', '') AND r.bin = u.bin
LIMIT 20;

-- 4. No label column in the binned view
--    Expected: 0 rows returned
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_name = 'txn_binned'
  AND (lower(column_name) LIKE '%fraud%' OR lower(column_name) LIKE '%label%');

-- 5. bin_rates is learned from train days 29-101 only, with nothing lost or double
--    counted: for every variable, orders and frauds add up to the window totals
--    Expected: 0 rows returned
WITH w AS (
    SELECT COUNT(*) AS n, SUM(isFraud) AS f
    FROM txn_split WHERE period = 'train' AND day >= 29
)
SELECT r.var, SUM(r.orders) AS orders, SUM(r.frauds) AS frauds, w.n, w.f
FROM bin_rates AS r CROSS JOIN w
GROUP BY r.var, w.n, w.f
HAVING SUM(r.orders) <> w.n OR SUM(r.frauds) <> w.f;

-- 6. Every bin meets the size rule (>= 100 frauds and >= 1% of the window's orders)
--    and has a valid rate and interval
--    Expected: 0 rows returned
SELECT var, bin, orders, frauds, rate, ci_low, ci_high
FROM bin_rates
WHERE NOT passes_rule
   OR rate <= 0 OR rate >= 1
   OR NOT (ci_low < rate AND rate < ci_high)
   OR ci_low <= 0
LIMIT 20;
