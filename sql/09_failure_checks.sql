-- 09_failure_checks.sql
-- Zero-row checks for Issue 9 (Failure Analysis).

SELECT 'check 1: wrong missed fraud' AS info, f.TransactionID
FROM fail_missed_top f JOIN fail_actions_test a USING (TransactionID)
WHERE a.isFraud = 0 OR a.score_action = 'block';

SELECT 'check 2: wrong false block' AS info, f.TransactionID
FROM fail_false_blocks_top f JOIN fail_actions_test a USING (TransactionID)
WHERE a.isFraud = 1 OR a.score_action <> 'block';

SELECT 'check 3: missing test txns' AS info, count(*)
FROM txn_scored s LEFT JOIN fail_actions_test a USING (TransactionID)
WHERE a.TransactionID IS NULL AND s.period = 'test';

SELECT 'check 4: frauds dont add up' AS info
FROM (SELECT sum(isFraud) AS total,
             count(*) FILTER (WHERE score_action <> 'approve' AND isFraud = 1) AS caught,
             count(*) FILTER (WHERE score_action = 'approve' AND isFraud = 1) AS missed
      FROM fail_actions_test)
WHERE caught + missed <> total;

SELECT 'check 5: freeze mismatch' AS info
FROM (SELECT count(*) AS orders, sum(isFraud) AS frauds,
             count(*) FILTER (WHERE score_action = 'block') AS blocked,
             count(*) FILTER (WHERE score_action <> 'approve' AND isFraud = 1) AS caught,
             count(*) FILTER (WHERE score_action = 'block' AND isFraud = 0) AS false_b
      FROM fail_actions_test) a
JOIN fail_freeze b ON a.orders <> b.orders OR a.frauds <> b.frauds
                   OR a.blocked <> b.blocked OR a.caught <> b.frauds_caught
                   OR a.false_b <> b.false_blocks;