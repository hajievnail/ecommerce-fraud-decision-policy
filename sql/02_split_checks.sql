-- 02_split_checks.sql
-- Checks for the day index and the three-way split.

-- 1. Every transaction has exactly one period
--    Expected: total_rows = 590,540 and rows_without_period = 0
SELECT
    COUNT(*)                                       AS total_rows,
    SUM(CASE WHEN period IS NULL THEN 1 ELSE 0 END) AS rows_without_period
FROM txn_split;

-- 2. No day falls in two periods
--    Expected: 0 rows returned
SELECT day, COUNT(DISTINCT period) AS n_periods
FROM txn_split
GROUP BY day
HAVING COUNT(DISTINCT period) > 1;

-- 3. Period summary: days, transactions, share, frauds, fraud rate
--    Expected shares close to 60 / 20 / 20
SELECT
    period,
    COUNT(DISTINCT day)                              AS days,
    COUNT(*)                                         AS txns,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct,
    SUM(isFraud)                                     AS frauds,
    ROUND(100.0 * AVG(isFraud), 2)                   AS fraud_rate_pct
FROM txn_split
GROUP BY period
ORDER BY MIN(day);