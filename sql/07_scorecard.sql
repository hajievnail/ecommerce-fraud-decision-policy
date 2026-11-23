-- 07_scorecard.sql
-- Issue 7: turn bin fraud rates into points and score every order.
--
-- Method (naive Bayes scorecard; Siddiqi, "Intelligent Credit Scoring"; ESL 6.6.3):
--   log_odds(order) = base_log_odds + SUM over the 9 variables of (log_odds(bin) - base_log_odds)
-- Points (our scaling choice): points = 500 + 50 * SUM(contribution)
--   so +1 in log-odds = +50 points; doubling the odds = +34.7 points.
--   500 = an order whose bins are all exactly as risky as the learning window's base rate.
--
-- Everything is learned from bin_rates (train days 29-101). No label is read here
-- except through bin_rates; txn_scored carries isFraud only so Issue 8 can evaluate.
--
-- Outputs:
--   scorecard_base  -- one row: learning-window base rate and base log-odds
--   card_definition -- one row per bin (44): rate, log-odds, contribution, points
--   txn_scored      -- view, one row per order: points, score_log_odds, prob_fraud
--
-- DuckDB-specific: CROSS JOIN LATERAL (VALUES ...), GROUP BY ALL. (T-SQL: CROSS APPLY.)

CREATE OR REPLACE TABLE scorecard_base AS
SELECT COUNT(*)                                                AS orders,
       SUM(isFraud)                                            AS frauds,
       SUM(isFraud) / COUNT(*)                                 AS base_rate,
       LN(SUM(isFraud) / (COUNT(*) - SUM(isFraud)))            AS base_log_odds
FROM txn_split
WHERE period = 'train' AND day >= 29;

CREATE OR REPLACE TABLE card_definition AS
SELECT r.var, r.bin, r.orders, r.frauds, r.rate,
       LN(r.rate / (1 - r.rate))                               AS log_odds,
       LN(r.rate / (1 - r.rate)) - b.base_log_odds             AS contribution,
       500.0 + 50.0 * (LN(r.rate / (1 - r.rate)) - b.base_log_odds) AS points
FROM bin_rates AS r CROSS JOIN scorecard_base AS b;

CREATE OR REPLACE VIEW txn_scored AS
WITH parts AS (
    SELECT b.TransactionID, c.contribution
    FROM txn_binned AS b
    CROSS JOIN LATERAL (VALUES
        ('product', b.b_product), ('amount', b.b_amount), ('email', b.b_email),
        ('card6',   b.b_card6),   ('device', b.b_device), ('dist1', b.b_dist1),
        ('hour',    b.b_hour),    ('n24h',   b.b_n24h),   ('gap',   b.b_gap)
    ) AS u(var, bin)
    JOIN card_definition AS c ON c.var = u.var AND c.bin = u.bin
),
per_order AS (
    SELECT TransactionID, COUNT(*) AS n_parts, SUM(contribution) AS contrib_sum
    FROM parts GROUP BY TransactionID
)
SELECT s.TransactionID, s.day, s.period, s.TransactionAmt, s.isFraud,
       p.n_parts,
       500.0 + 50.0 * p.contrib_sum                                       AS points,
       k.base_log_odds + p.contrib_sum                                    AS score_log_odds,
       1.0 / (1.0 + EXP(-(k.base_log_odds + p.contrib_sum)))              AS prob_fraud
FROM txn_split AS s
JOIN per_order AS p USING (TransactionID)
CROSS JOIN scorecard_base AS k;

-- The card, for reading
SELECT var, bin, orders, frauds, round(100 * rate, 2) AS rate_pct,
       round(contribution, 3) AS contribution, round(points, 1) AS points
FROM card_definition
ORDER BY var, points DESC;

-- Score by period and label
SELECT period,
       COUNT(*)                                                   AS orders,
       round(AVG(points), 1)                                      AS avg_points,
       round(AVG(points) FILTER (WHERE isFraud = 1), 1)           AS avg_points_fraud,
       round(AVG(points) FILTER (WHERE isFraud = 0), 1)           AS avg_points_legit,
       round(AVG(prob_fraud), 4)                                  AS avg_prob,
       round(AVG(isFraud), 4)                                     AS actual_rate
FROM txn_scored
GROUP BY period
ORDER BY period;
