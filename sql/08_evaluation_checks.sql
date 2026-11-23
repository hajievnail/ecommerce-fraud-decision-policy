-- 08_evaluation_checks.sql
-- Zero-row checks for Issue 8: every query below must return no rows.

-- 1. Every validation and test order has exactly one action row
SELECT 'orders without exactly one action row' AS problem, count(*) AS n
FROM (SELECT s.TransactionID, count(a.TransactionID) AS c
      FROM txn_scored s LEFT JOIN txn_actions a USING (TransactionID)
      WHERE s.period IN ('validation', 'test') GROUP BY s.TransactionID HAVING c <> 1)
HAVING count(*) > 0;

-- 2. Chosen thresholds fit the review capacity on validation (average rule)
SELECT 'best thresholds exceed capacity' AS problem, reviewed
FROM best_thresholds, eval_params, (SELECT count(*) AS n FROM txn_scored WHERE period = 'validation')
WHERE reviewed > floor(review_capacity * n);

-- 3. Baseline threshold fits the same capacity on validation
SELECT 'baseline exceeds capacity' AS problem, count(*) AS reviewed
FROM txn_scored, baseline_amount_threshold, eval_params
WHERE period = 'validation' AND TransactionAmt >= amount_threshold
HAVING count(*) > (SELECT floor(review_capacity * count(*)) FROM txn_scored, eval_params WHERE period = 'validation' GROUP BY review_capacity);

-- 4. Frauds caught in policy_results agree with a direct count from txn_actions
SELECT 'scorecard frauds caught mismatch' AS problem, r.period
FROM policy_results r
JOIN (SELECT period, count(*) FILTER (WHERE isFraud = 1 AND score_action <> 'approve') AS c
      FROM txn_actions GROUP BY period) t USING (period)
WHERE r.policy = 'scorecard' AND r.frauds_caught <> t.c;

-- 5. Approve-all catches nothing and costs exactly the fraud dollars
SELECT 'approve-all cost wrong' AS problem, r.period
FROM policy_results r
JOIN (SELECT period, round(sum(TransactionAmt) FILTER (WHERE isFraud = 1)) AS fusd FROM txn_scored GROUP BY period) t USING (period)
CROSS JOIN eval_params p
WHERE r.policy = 'approve all' AND (r.frauds_caught <> 0 OR abs(r.total_cost - p.fraud_loss * t.fusd) > 1);

-- 6. Validation grid never flags more orders than validation has
SELECT 'grid flags more than validation orders' AS problem, count(*) AS n
FROM val_grid g, (SELECT count(*) AS n_val FROM txn_scored WHERE period = 'validation') v
WHERE g.reviewed + g.blocked > v.n_val
HAVING count(*) > 0;
