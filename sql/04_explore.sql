-- 04_explore.sql
-- Session 4: exploration before the scorecard.
-- Rule: any query that uses isFraud runs on the TRAIN period only.
-- Label-free queries (like section 1) may use all periods.
-- Results are printed, not stored; findings go to docs/data_notes.md.
--
-- DuckDB-specific syntax used in this file (PostgreSQL / T-SQL equivalents):
--   MEDIAN(x)               -> percentile_cont(0.5) WITHIN GROUP (ORDER BY x)
--   ANY_VALUE(x)            -> PostgreSQL 16+ has it; otherwise MAX(x) on a constant
--   x::INT                  -> CAST(x AS INT) (T-SQL has no ::)
--   FILTER (WHERE ...)      -> PostgreSQL has it; T-SQL: SUM(CASE WHEN ... END)
--   GROUP BY ALL            -> list the grouping columns
--   // (integer division)   -> FLOOR(a / b) or integer division of integers
--   PIVOT ... USING         -> different syntax in T-SQL; crosstab() in PostgreSQL
--   quantile_cont(x, [list]) -> one percentile_cont per quantile
--   floor(x) % 24           -> floor() returns a decimal here; PostgreSQL's %
--                              needs integers, so CAST(floor(x) AS INT) % 24

-- 1. Product mix over time (label-free, all periods)
--    Question from session 3: do the identity burst (days 15-28) and the
--    gradual fill-in of D/M columns come from changes in product mix?
--    Two-week blocks; "within W" columns hold product fixed.
--    Blocks 99-112 and 141-154 straddle a period boundary, so the periods
--    column lists every period in the block.
--    DuckDB-specific: // (integer division), ::INT, FILTER (WHERE ...),
--    string_agg(DISTINCT ... ORDER BY ...).
SELECT
    (day - 1) // 14 * 14 + 1                                                 AS from_day,
    MAX(day)                                                                 AS to_day,
    string_agg(DISTINCT period, '+' ORDER BY period)                         AS periods,
    COUNT(*)                                                                 AS orders,
    ROUND(100 * AVG((ProductCD = 'W')::INT), 1)                              AS w_pct,
    ROUND(100 * AVG((ProductCD = 'C')::INT), 1)                              AS c_pct,
    ROUND(100 * AVG((ProductCD IN ('R', 'H', 'S'))::INT), 1)                 AS rhs_pct,
    ROUND(100 * AVG(has_identity::INT), 1)                                   AS identity_pct,
    ROUND(100 * AVG(has_identity::INT) FILTER (WHERE ProductCD <> 'W'), 1)   AS identity_pct_non_w,
    ROUND(100 * AVG((D11 IS NULL)::INT), 1)                                  AS d11_null_pct,
    ROUND(100 * AVG((D11 IS NULL)::INT) FILTER (WHERE ProductCD = 'W'), 1)   AS d11_null_within_w,
    ROUND(100 * AVG((M7 IS NULL)::INT) FILTER (WHERE ProductCD = 'W'), 1)    AS m7_null_within_w
FROM txn_split
GROUP BY 1
ORDER BY 1;

-- 2. Fraud rate by product (TRAIN only)
--    lift = product fraud rate / overall train fraud rate (1 = average risk).
--    ci95_pm_pp = half-width of an approximate 95% confidence interval for the
--    rate, in percentage points: 1.96 * sqrt(p * (1 - p) / n).
--    fraud_value_rate_pct = share of the dollar amount that is fraud
--    (matters for cost, which is driven by amounts, not counts).
--    Window functions SUM(...) OVER () give the grand total on every row.
WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
)
SELECT
    ProductCD,
    COUNT(*)                                                                 AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                       AS order_share_pct,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100.0 * SUM(isFraud) / SUM(SUM(isFraud)) OVER (), 1)               AS fraud_share_pct,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift,
    ROUND(MEDIAN(TransactionAmt), 0)                                         AS median_amt,
    ROUND(100.0 * SUM(TransactionAmt) FILTER (WHERE isFraud = 1)
          / SUM(TransactionAmt), 2)                                          AS fraud_value_rate_pct
FROM txn_split, base
WHERE period = 'train'
GROUP BY ProductCD
ORDER BY fraud_rate_pct DESC;

-- 3. Fraud rate by card network (card4) and card type (card6) (TRAIN only)
--    Same measures as section 2, plus the rate within products W and C,
--    to see whether a card effect is just a product effect in disguise.
--    COALESCE shows NULL as '(missing)'.
WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
)
SELECT
    COALESCE(card4, '(missing)')                                             AS card4,
    COUNT(*)                                                                 AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                       AS order_share_pct,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'W'), 2)              AS rate_within_w_pct,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'C'), 2)              AS rate_within_c_pct
FROM txn_split, base
WHERE period = 'train'
GROUP BY 1
ORDER BY orders DESC;

WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
)
SELECT
    COALESCE(card6, '(missing)')                                             AS card6,
    COUNT(*)                                                                 AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                       AS order_share_pct,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'W'), 2)              AS rate_within_w_pct,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'C'), 2)              AS rate_within_c_pct
FROM txn_split, base
WHERE period = 'train'
GROUP BY 1
ORDER BY orders DESC;

-- Card network x product (order counts, TRAIN): American Express never
-- appears in W and almost never in C (2 orders); Discover never in C.
-- DuckDB-specific: PIVOT ... ON ... USING.
PIVOT (SELECT card4, ProductCD FROM txn_split WHERE period = 'train')
ON ProductCD IN ('W', 'C', 'H', 'R', 'S')
USING COUNT(*)
ORDER BY card4;

-- 4. Fraud rate by purchaser email domain (P_emaildomain) (TRAIN only)
--    59 distinct domains in train. Domains with fewer than 1,000 train orders
--    are grouped as "other" (own choice, to avoid unstable rates; Day 6 sets
--    the final bins). COUNT(*) OVER (PARTITION BY ...) gives each row the size
--    of its domain without collapsing rows.
--    c_share_pct shows how much of each domain is product C (the riskiest product).
WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
),
d AS (
    SELECT *, COUNT(*) OVER (PARTITION BY P_emaildomain) AS domain_orders
    FROM txn_split
    WHERE period = 'train'
)
SELECT
    CASE
        WHEN P_emaildomain IS NULL THEN '(missing)'
        WHEN domain_orders >= 1000 THEN P_emaildomain
        ELSE '(other, <1000 orders each)'
    END                                                                      AS email_domain,
    COUNT(*)                                                                 AS orders,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'W'), 2)              AS rate_within_w_pct,
    ROUND(100 * AVG((ProductCD = 'C')::INT), 1)                              AS c_share_pct
FROM d, base
GROUP BY 1
ORDER BY orders DESC;

-- 5. Fraud rate by amount band (TRAIN only)
--    Bands are round dollar values (own choice for exploration; train median
--    is $70, 90th percentile ~$280, 99th ~$1,086). Day 6 sets the final bins.
--    share_of_fraud_usd_pct: where the fraud DOLLARS are, which drives cost.
--    DuckDB-specific: quantile_cont with a list returns several quantiles at once.
SELECT
    ROUND(MIN(TransactionAmt), 3)                                            AS min_amt,
    quantile_cont(TransactionAmt, [0.1, 0.25, 0.5, 0.75, 0.9, 0.99])         AS quantiles,
    ROUND(MAX(TransactionAmt), 0)                                            AS max_amt
FROM txn_split
WHERE period = 'train';

WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
)
SELECT
    CASE
        WHEN TransactionAmt < 10   THEN '1: <10'
        WHEN TransactionAmt < 25   THEN '2: 10-25'
        WHEN TransactionAmt < 50   THEN '3: 25-50'
        WHEN TransactionAmt < 100  THEN '4: 50-100'
        WHEN TransactionAmt < 200  THEN '5: 100-200'
        WHEN TransactionAmt < 500  THEN '6: 200-500'
        WHEN TransactionAmt < 1000 THEN '7: 500-1000'
        ELSE '8: 1000+'
    END                                                                      AS amount_band,
    COUNT(*)                                                                 AS orders,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'W'), 2)              AS rate_within_w_pct,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'C'), 2)              AS rate_within_c_pct,
    ROUND(100 * AVG((ProductCD = 'C')::INT), 1)                              AS c_share_pct,
    ROUND(SUM(TransactionAmt) FILTER (WHERE isFraud = 1))                    AS fraud_usd,
    ROUND(100.0 * SUM(TransactionAmt) FILTER (WHERE isFraud = 1)
          / SUM(SUM(TransactionAmt) FILTER (WHERE isFraud = 1)) OVER (), 1)  AS share_of_fraud_usd_pct
FROM txn_split, base
WHERE period = 'train'
GROUP BY 1
ORDER BY 1;

-- 6. Fraud rate by relative hour of day (TRAIN only)
--    rel_hour = floor(TransactionDT / 3600) % 24. TransactionDT counts seconds
--    from an unknown reference point, so hour 0 is NOT necessarily midnight;
--    the real time zone is unknown.
WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
)
SELECT
    CAST(floor(TransactionDT / 3600) % 24 AS INTEGER)                        AS rel_hour,
    COUNT(*)                                                                 AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)                       AS order_share_pct,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'W'), 2)              AS rate_within_w_pct,
    ROUND(100 * AVG((ProductCD = 'C')::INT), 1)                              AS c_share_pct
FROM txn_split, base
WHERE period = 'train'
GROUP BY 1
ORDER BY 1;

-- 7. Fraud rate by identity record (has_identity), against product (TRAIN only)
--    Session 3 found that product W never has identity data and the other
--    products almost always do, so the identity effect may be a product effect.
WITH base AS (
    SELECT AVG(isFraud) AS base_rate FROM txn_split WHERE period = 'train'
)
SELECT
    has_identity,
    COUNT(*)                                                                 AS orders,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2)                            AS lift
FROM txn_split, base
WHERE period = 'train'
GROUP BY 1
ORDER BY 1;

-- Identity x product: only product C has a sizeable group on both sides.
SELECT
    ProductCD,
    has_identity,
    COUNT(*)                                                                 AS orders,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp
FROM txn_split
WHERE period = 'train'
GROUP BY ALL
ORDER BY ProductCD, has_identity;

-- Device type, among orders that have an identity record.
SELECT
    COALESCE(DeviceType, '(missing)')                                        AS device_type,
    COUNT(*)                                                                 AS orders,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * AVG(isFraud) FILTER (WHERE ProductCD = 'C'), 2)              AS rate_within_c_pct,
    ROUND(100 * AVG((ProductCD = 'C')::INT), 1)                              AS c_share_pct
FROM txn_split
WHERE period = 'train' AND has_identity
GROUP BY 1
ORDER BY orders DESC;

-- 8. Sizing simple candidate baseline rules (TRAIN only, 101 days)
--    For each rule: share of orders flagged, flagged per day, share of frauds
--    and of fraud DOLLARS caught, and legitimate dollars flagged.
--    PERCENT_RANK() OVER (ORDER BY amount DESC) = 0 for the largest order,
--    so "< 0.05" keeps the top 5% by amount.
WITH t AS (
    SELECT *, PERCENT_RANK() OVER (ORDER BY TransactionAmt DESC) AS amt_rank
    FROM txn_split
    WHERE period = 'train'
),
tot AS (
    SELECT
        SUM(isFraud)                                    AS frauds,
        SUM(TransactionAmt) FILTER (WHERE isFraud = 1)  AS fraud_usd,
        COUNT(*)                                        AS orders
    FROM t
)
SELECT
    rule,
    ROUND(100.0 * COUNT(*) / ANY_VALUE(tot.orders), 1)                               AS pct_orders_flagged,
    ROUND(COUNT(*) / 101.0)                                                          AS flagged_per_day,
    ROUND(100.0 * SUM(isFraud) / ANY_VALUE(tot.frauds), 1)                           AS pct_frauds_caught,
    ROUND(100.0 * SUM(TransactionAmt) FILTER (WHERE isFraud = 1)
          / ANY_VALUE(tot.fraud_usd), 1)                                             AS pct_fraud_usd_caught,
    ROUND(100 * AVG(isFraud), 2)                                                     AS fraud_rate_in_flagged_pct,
    ROUND(SUM(TransactionAmt) FILTER (WHERE isFraud = 0))                            AS legit_usd_flagged
FROM (
    SELECT 'top 2% by amount'  AS rule, * FROM t WHERE amt_rank < 0.02
    UNION ALL
    SELECT 'top 5% by amount'  AS rule, * FROM t WHERE amt_rank < 0.05
    UNION ALL
    SELECT 'top 10% by amount' AS rule, * FROM t WHERE amt_rank < 0.10
    UNION ALL
    SELECT 'all product C'     AS rule, * FROM t WHERE ProductCD = 'C'
    UNION ALL
    SELECT 'all orders'        AS rule, * FROM t
) AS r, tot
GROUP BY rule
ORDER BY pct_orders_flagged;

-- 9. Distance (dist1) (added after the session 4 audit; TRAIN only for labels)
--    dist1 exists only for product W (100% missing in C, H, R, S), so the
--    fraud rates are computed WITHIN W, and lift_vs_w compares with W's own
--    rate (2.04%). Bands are round values (own choice; within-train quantiles:
--    median 9, 75th 26, 90th 347, 99th 2,119; integers from 0 to 10,286).
--    median_amt and credit_pct are a rough check that a distance effect is not
--    just amount or card type in disguise.
SELECT
    ProductCD,
    COUNT(*)                                                                 AS orders,
    ROUND(100 * AVG((dist1 IS NULL)::INT), 1)                                AS dist1_missing_pct
FROM txn_split
WHERE period = 'train'
GROUP BY 1
ORDER BY orders DESC;

WITH w AS (
    SELECT * FROM txn_split WHERE period = 'train' AND ProductCD = 'W'
),
base AS (
    SELECT AVG(isFraud) AS w_rate FROM w
)
SELECT
    CASE
        WHEN dist1 IS NULL  THEN '0: missing'
        WHEN dist1 = 0      THEN '1: 0'
        WHEN dist1 <= 5     THEN '2: 1-5'
        WHEN dist1 <= 20    THEN '3: 6-20'
        WHEN dist1 <= 100   THEN '4: 21-100'
        WHEN dist1 <= 500   THEN '5: 101-500'
        WHEN dist1 <= 2000  THEN '6: 501-2000'
        ELSE '7: 2001+'
    END                                                                      AS dist1_band,
    COUNT(*)                                                                 AS orders,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                       AS share_of_w_pct,
    SUM(isFraud)                                                             AS frauds,
    ROUND(100 * AVG(isFraud), 2)                                             AS fraud_rate_pct,
    ROUND(100 * 1.96 * SQRT(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci95_pm_pp,
    ROUND(AVG(isFraud) / ANY_VALUE(w_rate), 2)                               AS lift_vs_w,
    ROUND(MEDIAN(TransactionAmt), 0)                                         AS median_amt,
    ROUND(100 * AVG((card6 = 'credit')::INT), 1)                             AS credit_pct
FROM w, base
GROUP BY 1
ORDER BY 1;

-- dist1 missingness within W over time (label-free, all periods):
-- unlike D11 / M7, it shows no trend (38-54% in every two-week block).
SELECT
    (day - 1) // 14 * 14 + 1                                                 AS from_day,
    MAX(day)                                                                 AS to_day,
    string_agg(DISTINCT period, '+' ORDER BY period)                         AS periods,
    ROUND(100 * AVG((dist1 IS NULL)::INT), 1)                                AS dist1_null_within_w
FROM txn_split
WHERE ProductCD = 'W'
GROUP BY 1
ORDER BY 1;
