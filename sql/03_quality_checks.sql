-- 03_quality_checks.sql
-- Data-quality tests. Every query below must return 0 rows.
-- If one returns rows, it shows (up to 20) offending transactions.
-- Allowed category values were fixed after listing distinct values on 2026-10-23
-- (session 3): the checks catch changes from that state, not "wrong" values.

-- 1. Amount missing or not positive
--    Expected: 0 rows returned
SELECT TransactionID, TransactionAmt
FROM txn_split
WHERE TransactionAmt IS NULL OR TransactionAmt <= 0
LIMIT 20;

-- 2. Label missing or not 0/1
--    Expected: 0 rows returned
SELECT TransactionID, isFraud
FROM txn_split
WHERE isFraud IS NULL OR isFraud NOT IN (0, 1)
LIMIT 20;

-- 3. Time missing or negative
--    Expected: 0 rows returned
SELECT TransactionID, TransactionDT
FROM txn_split
WHERE TransactionDT IS NULL OR TransactionDT < 0
LIMIT 20;

-- 4. Negative distances (NULL is allowed: see the missing-value profile)
--    Expected: 0 rows returned
SELECT TransactionID, dist1, dist2
FROM txn_split
WHERE dist1 < 0 OR dist2 < 0
LIMIT 20;

-- 5. Unexpected category values (NULL allowed, except ProductCD)
--    Expected: 0 rows returned
SELECT TransactionID, ProductCD, card4, card6, DeviceType
FROM txn_split
WHERE ProductCD IS NULL
   OR ProductCD NOT IN ('W', 'C', 'R', 'H', 'S')
   OR card4 NOT IN ('visa', 'mastercard', 'american express', 'discover')
   OR card6 NOT IN ('debit', 'credit', 'debit or credit', 'charge card')
   OR DeviceType NOT IN ('desktop', 'mobile')
LIMIT 20;

-- 6. Broken join (a): identity values on rows that have no identity record
--    Counts filled values in each of the 40 identity columns (id_01-id_38,
--    DeviceType, DeviceInfo) over rows without identity, and lists any column > 0.
--    DuckDB-specific: COLUMNS('regex') repeats COUNT() for every matching column;
--    UNPIVOT turns the one wide row into one row per column. In PostgreSQL / T-SQL
--    you would list the 40 columns by hand.
--    (Not used: NOT (COLUMNS(...) IS NULL) in WHERE. The copies are joined with AND,
--    so it means "all 40 filled" and would miss a single stray value.)
--    Expected: 0 rows returned
SELECT *
FROM (
    UNPIVOT (
        SELECT COUNT(COLUMNS('^(id_[0-9]+|DeviceType|DeviceInfo)$'))
        FROM txn_split
        WHERE NOT has_identity
    )
    ON COLUMNS(*)
    INTO NAME column_name VALUE filled_rows
)
WHERE filled_rows > 0;

-- 7. Broken join (b): id_01 is filled exactly when an identity record exists
--    (found in the missing-value profile: id_01 null share = share without identity)
--    Expected: 0 rows returned
SELECT TransactionID, has_identity, id_01
FROM txn_split
WHERE has_identity IS NULL
   OR (has_identity AND id_01 IS NULL)
   OR (NOT has_identity AND id_01 IS NOT NULL)
LIMIT 20;
