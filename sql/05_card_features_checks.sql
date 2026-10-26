-- 05_card_features_checks.sql
-- Tests for the card ID and history features. Every query below must return 0 rows.
-- If one returns rows, it shows (up to 20) offending transactions.
--
-- The label-flip leakage test (flip every non-train label in a scratch copy,
-- rebuild, compare) needs a second database file, so it is run by hand and
-- recorded in docs/data_notes.md. Check 6 below is its in-database partner:
-- no label column reaches the feature objects at all.

-- 1. Exactly one feature row per order
--    Expected: 0 rows returned
SELECT 'row count' AS problem, (SELECT COUNT(*) FROM card_features) AS n_features,
       (SELECT COUNT(*) FROM txn_split) AS n_orders
WHERE (SELECT COUNT(*) FROM card_features) <> (SELECT COUNT(*) FROM txn_split)
   OR (SELECT COUNT(DISTINCT TransactionID) FROM card_features) <> (SELECT COUNT(*) FROM txn_split);

-- 2. Card ID present exactly when D1 is present; features NULL exactly when no ID
--    Expected: 0 rows returned
SELECT f.TransactionID, t.D1, f.card_id, f.prior_n
FROM card_features AS f
JOIN txn_split AS t USING (TransactionID)
WHERE (t.D1 IS NULL) <> (f.card_id IS NULL)
   OR f.has_card_id <> (f.card_id IS NOT NULL)
   OR (f.card_id IS NULL) <> (f.prior_n IS NULL)
LIMIT 20;

-- 3. Internal consistency of the counts and flags
--    24h count <= 7d count <= all-history count; first-seen exactly when no history;
--    time since previous order present exactly when there is history, and positive
--    (strictly earlier rule: at least 1 second)
--    Expected: 0 rows returned
SELECT TransactionID, prior_n, prior_n_24h, prior_n_7d, is_first_seen, secs_since_prev
FROM card_features
WHERE has_card_id
  AND (   prior_n_24h > prior_n_7d
       OR prior_n_7d  > prior_n
       OR is_first_seen <> (prior_n = 0)
       OR (secs_since_prev IS NULL) <> (prior_n = 0)
       OR secs_since_prev < 1
       OR (amt_vs_prior_avg IS NULL) <> (prior_n = 0)
       OR prior_n_email_domains > prior_n
       OR (is_first_seen AND email_new_for_card))
LIMIT 20;

-- 4. Truncation test at the end of train (day 101)
--    Recompute the features as if the data stopped on day 101. If any feature used
--    later orders, the values for days 1-101 would change. Compared both ways.
--    Expected: 0 rows returned
WITH truncated AS (FROM card_history(101)),
     full_run  AS (SELECT f.* FROM card_features AS f JOIN txn_card AS c USING (TransactionID)
                   WHERE c.day <= 101)
(FROM truncated EXCEPT FROM full_run)
UNION ALL
(FROM full_run EXCEPT FROM truncated)
LIMIT 20;

-- 5. Truncation test at the end of validation (day 141)
--    Expected: 0 rows returned
WITH truncated AS (FROM card_history(141)),
     full_run  AS (SELECT f.* FROM card_features AS f JOIN txn_card AS c USING (TransactionID)
                   WHERE c.day <= 141)
(FROM truncated EXCEPT FROM full_run)
UNION ALL
(FROM full_run EXCEPT FROM truncated)
LIMIT 20;

-- 6. No label column in the card-ID view or the feature table
--    (the macro reads only txn_card, so this covers it too)
--    Expected: 0 rows returned
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_name IN ('txn_card', 'card_features')
  AND lower(column_name) LIKE '%fraud%';
