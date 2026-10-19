-- 01_load_checks.sql
-- Sanity checks after loading. Compare each result with the expected value.

-- 1. Row counts: txn must equal raw_transaction (expected 590,540)
SELECT
    (SELECT COUNT(*) FROM raw_transaction) AS raw_transaction_rows,
    (SELECT COUNT(*) FROM txn)             AS txn_rows;

-- 2. No duplicates created by the join (expected: 0 rows returned)
SELECT TransactionID, COUNT(*) AS n
FROM txn
GROUP BY TransactionID
HAVING COUNT(*) > 1;

-- 3. Fraud count and rate (expected 20,663 frauds, ~3.5%)
SELECT
    SUM(isFraud)                 AS frauds,
    ROUND(AVG(isFraud) * 100, 2) AS fraud_rate_pct
FROM txn;

-- 4. Identity coverage: share of transactions with identity data
SELECT
    SUM(CASE WHEN has_identity THEN 1 ELSE 0 END)                     AS with_identity,
    ROUND(AVG(CASE WHEN has_identity THEN 1.0 ELSE 0 END) * 100, 1)   AS with_identity_pct,
    (SELECT COUNT(*) FROM raw_identity)                               AS raw_identity_rows
FROM txn;
