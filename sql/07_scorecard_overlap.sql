-- 07_scorecard_overlap.sql
-- Overlap check for the naive-Bayes scorecard (train days 29-101, the learning window).
-- For a pair of variables, compare the ACTUAL fraud rate of each joint cell with the rate
-- implied by adding the two bins' contributions:
--     implied_log_odds = base_log_odds + contribution_1 + contribution_2
-- If the two variables were independent given fraud, actual ~ implied. Ratio > 1 means
-- the sum under-states the risk, < 1 means it over-states it (double counting).
-- Cells need >= 200 orders to be shown. Uses train labels only; it only reads the card.
-- Output is a table, overlap_check; summary per pair at the end.

CREATE OR REPLACE TABLE overlap_check AS
WITH w AS (
    SELECT b.*, s.isFraud
    FROM txn_binned AS b JOIN txn_split AS s USING (TransactionID)
    WHERE s.period = 'train' AND s.day >= 29
),
pairs AS (
    SELECT 'product x device' AS pair, 'product' AS v1, 'device' AS v2, b_product AS bin1, b_device AS bin2, isFraud FROM w
    UNION ALL SELECT 'product x gap',    'product', 'gap',    b_product, b_gap,    isFraud FROM w
    UNION ALL SELECT 'product x email',  'product', 'email',  b_product, b_email,  isFraud FROM w
    UNION ALL SELECT 'product x amount', 'product', 'amount', b_product, b_amount, isFraud FROM w
    UNION ALL SELECT 'gap x n24h',       'gap',     'n24h',   b_gap,     b_n24h,   isFraud FROM w
),
cells AS (
    SELECT pair, v1, v2, bin1, bin2, COUNT(*) AS orders, SUM(isFraud) AS frauds
    FROM pairs GROUP BY ALL HAVING COUNT(*) >= 200
)
SELECT c.pair, c.bin1, c.bin2, c.orders, c.frauds,
       c.frauds / c.orders                                                   AS actual_rate,
       1 / (1 + EXP(-(k.base_log_odds + d1.contribution + d2.contribution))) AS implied_rate
FROM cells AS c
JOIN card_definition AS d1 ON d1.var = c.v1 AND d1.bin = c.bin1
JOIN card_definition AS d2 ON d2.var = c.v2 AND d2.bin = c.bin2
CROSS JOIN scorecard_base AS k;

-- Summary: orders-weighted mean of |actual / implied - 1|, and the share of orders in cells
-- where the implied rate is more than 1.5x or less than 0.67x the actual one
SELECT pair,
       COUNT(*)                                                              AS cells,
       SUM(orders)                                                           AS orders,
       round(SUM(orders * abs(implied_rate / actual_rate - 1)) / SUM(orders), 2) AS weighted_abs_error,
       round(SUM(orders) FILTER (WHERE implied_rate / actual_rate > 1.5 OR implied_rate / actual_rate < 0.67)
             / SUM(orders), 3)                                               AS share_orders_off
FROM overlap_check
WHERE actual_rate > 0
GROUP BY pair
ORDER BY weighted_abs_error DESC;

-- Worst cells (largest orders-weighted gap)
SELECT pair, bin1, bin2, orders, frauds,
       round(100 * actual_rate, 2) AS actual_pct, round(100 * implied_rate, 2) AS implied_pct,
       round(implied_rate / actual_rate, 2) AS implied_over_actual
FROM overlap_check
WHERE actual_rate > 0
ORDER BY orders * abs(implied_rate / actual_rate - 1) DESC
LIMIT 15;
