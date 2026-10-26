-- 05_card_features.sql
-- Session 5: reconstructed card ID and point-in-time card history features.
--
-- Card ID (recipe chosen on 2026-10-26, see docs/data_notes.md):
--   card1 + addr1 + (day - D1)
--   D1 is said to be "days since the card was first used" (competition discussions,
--   Towards Data Science "IEEE-CIS Fraud Detection: Top 5% Solution"); day - D1 is then
--   the card's first-use day, constant for one card. Tested in section 1 below.
--   Missing addr1 (95% of product C) is kept as its own value 'na'.
--   Missing D1 (1,269 orders) gets no card ID; all history features are NULL.
--
-- Point-in-time rule: every feature uses only orders of the same card with a
-- STRICTLY EARLIER TransactionDT (frame "RANGE ... 1 PRECEDING"). Orders in the
-- same second do not see each other. History may reach into earlier periods
-- (those orders happened before). Sections 1-4 read no label (isFraud) at all.
-- Sections 5-6 (signal check) read labels of the TRAIN period only.
--
-- DuckDB-specific syntax (PostgreSQL / T-SQL equivalents):
--   GROUP BY ALL          -> list the grouping columns
--   arg_max(x, n)         -> DISTINCT ON (PostgreSQL) / ROW_NUMBER() filter (T-SQL)
--   setseed(), random()   -> setseed()/random() in PostgreSQL; RAND(seed) in T-SQL
--   hash(...)             -> md5(concat_ws(...)) / HASHBYTES
--   FILTER (WHERE ...)    -> PostgreSQL has it; T-SQL: SUM(CASE WHEN ... END)
--   COUNT(DISTINCT x) OVER (...)  -> not allowed in PostgreSQL or T-SQL window functions;
--                                    there you would use a self-join or DENSE_RANK tricks
--   RANGE BETWEEN n PRECEDING with a numeric offset -> PostgreSQL 11+ has it; T-SQL does not
--   CREATE MACRO ... AS TABLE    -> a set-returning SQL function (PostgreSQL) /
--                                   inline table-valued function (T-SQL)
--   FROM-first (FROM x without SELECT) -> SELECT * FROM x


-- ---------------------------------------------------------------------------
-- 1. Exploration: is day - D1 stable within card-like groups? (label-free)
--    Groups = orders sharing card1-card6, addr1 and P_emaildomain (2+ orders).
--    Placebo = the same groups with D1 shuffled at random across orders.
--    If D1 carried no card information, real and placebo would look alike.
--    Note: random() under parallel threads may not reproduce exactly; the
--    real-vs-placebo gap is large, so small run-to-run changes do not matter.
-- ---------------------------------------------------------------------------
SELECT setseed(0.42);

WITH base AS (
    SELECT TransactionID, day, D1,
           hash(card1, card2, card3, card4, card5, card6, addr1, P_emaildomain) AS k
    FROM txn_split
    WHERE D1 IS NOT NULL AND addr1 IS NOT NULL
),
shuffled AS (
    SELECT b.*, s.D1 AS D1_shuffled
    FROM (SELECT *, row_number() OVER (ORDER BY TransactionID) AS rn FROM base) AS b
    JOIN (SELECT D1, row_number() OVER (ORDER BY random()) AS rn FROM base) AS s USING (rn)
),
t AS (
    SELECT 'real' AS version, k, day - D1 AS fd FROM shuffled
    UNION ALL
    SELECT 'placebo', k, day - D1_shuffled FROM shuffled
),
g AS (SELECT version, k, fd, COUNT(*) AS n FROM t GROUP BY ALL),
grp AS (
    SELECT version, k, SUM(n) AS total, MAX(n) AS mode_n, arg_max(fd, n) AS mode_fd
    FROM g GROUP BY ALL HAVING SUM(n) >= 2
),
per_grp AS (
    SELECT grp.version, grp.k, grp.total, grp.mode_n,
           SUM(g.n) FILTER (WHERE abs(g.fd - grp.mode_fd) <= 1) AS within_1
    FROM grp JOIN g USING (version, k)   -- single hash key: no NULL-key join problem
    GROUP BY ALL
)
SELECT version,
       CASE WHEN total = 2 THEN '1: 2 orders' WHEN total <= 5 THEN '2: 3-5'
            WHEN total <= 20 THEN '3: 6-20' ELSE '4: 21+' END AS group_size,
       COUNT(*) AS groups,
       SUM(total) AS orders,
       ROUND(100.0 * SUM(mode_n) / SUM(total), 1) AS pct_on_mode,
       ROUND(100.0 * SUM(within_1) / SUM(total), 1) AS pct_within_1_day,
       ROUND(100.0 * COUNT(*) FILTER (WHERE mode_n = total) / COUNT(*), 1) AS pct_groups_one_value
FROM per_grp
GROUP BY ALL
ORDER BY group_size, version DESC;


-- ---------------------------------------------------------------------------
-- 2. Card ID per order (view: no copy of the big table)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW txn_card AS
SELECT TransactionID, TransactionDT, day, period, TransactionAmt, P_emaildomain,
       CASE WHEN D1 IS NOT NULL
            THEN concat_ws('|', card1,
                           COALESCE(CAST(CAST(addr1 AS INTEGER) AS VARCHAR), 'na'),
                           CAST(day - D1 AS INTEGER))
       END AS card_id
FROM txn_split;


-- ---------------------------------------------------------------------------
-- 3. Point-in-time history features (one row per order)
--    Window "w" = same card, strictly earlier TransactionDT.
--    For orders without a card ID every feature is NULL (otherwise all
--    no-ID orders would form one giant "card" in PARTITION BY).
-- ---------------------------------------------------------------------------
--    Features:
--      prior_n               earlier orders of this card (whole history)
--      prior_n_24h / _7d     earlier orders in the last 24 hours / 7 days
--      secs_since_prev       seconds since the card's previous order (NULL if none);
--                            whole seconds, because rounding hours hid gaps under 18 s
--      amt_vs_prior_avg      this amount / average of earlier amounts (NULL if none)
--      is_first_seen         no earlier order of this card in the data
--      prior_n_email_domains distinct non-missing P_emaildomain values used before
--      email_new_for_card    card has history, but never with this email domain
--                            (missing email counts as its own value here)
-- ---------------------------------------------------------------------------
--    The query is a table macro with a cut-off day, so the checks script can
--    recompute features as if the data ended on an earlier day (truncation
--    test). card_features itself uses all days: card_history(182).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE MACRO card_history(max_day) AS TABLE
WITH src AS (
    SELECT * FROM txn_card WHERE day <= max_day
),
w AS (
    SELECT TransactionID, card_id, TransactionDT, TransactionAmt,
           COUNT(*)                      OVER all_prior  AS prior_n,
           COUNT(*)                      OVER last_24h   AS prior_n_24h,
           COUNT(*)                      OVER last_7d    AS prior_n_7d,
           MAX(TransactionDT)            OVER all_prior  AS prev_dt,
           AVG(TransactionAmt)           OVER all_prior  AS prior_avg_amt,
           COUNT(DISTINCT P_emaildomain) OVER all_prior  AS prior_n_email_domains,
           COUNT(*)                      OVER same_email AS prior_n_same_email
    FROM src
    WHERE card_id IS NOT NULL
    WINDOW all_prior  AS (PARTITION BY card_id ORDER BY TransactionDT
                          RANGE BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
           last_24h   AS (PARTITION BY card_id ORDER BY TransactionDT
                          RANGE BETWEEN 86400 PRECEDING AND 1 PRECEDING),
           last_7d    AS (PARTITION BY card_id ORDER BY TransactionDT
                          RANGE BETWEEN 604800 PRECEDING AND 1 PRECEDING),
           same_email AS (PARTITION BY card_id, P_emaildomain ORDER BY TransactionDT
                          RANGE BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING)
)
SELECT t.TransactionID,
       t.card_id,
       t.card_id IS NOT NULL                                AS has_card_id,
       w.prior_n,
       w.prior_n_24h,
       w.prior_n_7d,
       w.TransactionDT - w.prev_dt                          AS secs_since_prev,
       ROUND(w.TransactionAmt / NULLIF(w.prior_avg_amt, 0), 3) AS amt_vs_prior_avg,
       w.prior_n = 0                                        AS is_first_seen,
       w.prior_n_email_domains,
       w.prior_n > 0 AND w.prior_n_same_email = 0           AS email_new_for_card
FROM src AS t
LEFT JOIN w USING (TransactionID);

CREATE OR REPLACE TABLE card_features AS
FROM card_history(182);


-- ---------------------------------------------------------------------------
-- 4. Card ID summary (label-free)
-- ---------------------------------------------------------------------------
SELECT COUNT(DISTINCT card_id)                       AS card_ids,
       COUNT(*) FILTER (WHERE has_card_id)           AS orders_with_id,
       COUNT(*) FILTER (WHERE NOT has_card_id)       AS orders_without_id
FROM card_features;


-- ---------------------------------------------------------------------------
-- 5. Signal check: fraud rate by feature band, TRAIN ONLY
--    Same measures as 04_explore.sql: rate, 95% CI half-width
--    (1.96 * sqrt(p(1-p)/n), rough for small groups), lift = rate / train base rate.
--    rate_after_day28 repeats the rate without the first 4 weeks of train, where
--    every card looks "new" because the data starts on day 1 (left censoring).
--    Bands are a first look, not the Day 6 bins.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TEMP VIEW train_hist AS
SELECT t.isFraud, t.day, t.ProductCD, f.*
FROM card_features AS f
JOIN txn_split AS t USING (TransactionID)
WHERE t.period = 'train';

WITH bands AS (
    SELECT isFraud, day, '1 history' AS feature,
           CASE WHEN NOT has_card_id THEN '0 no card ID'
                WHEN is_first_seen THEN '1 first seen'
                WHEN prior_n < 5 THEN '2 1-4 earlier orders'
                WHEN prior_n < 20 THEN '3 5-19 earlier orders'
                ELSE '4 20+ earlier orders' END AS band
    FROM train_hist
    UNION ALL
    SELECT isFraud, day, '2 orders in last 24h',
           CASE WHEN NOT has_card_id THEN '0 no card ID'
                WHEN prior_n_24h = 0 THEN '1 none'
                WHEN prior_n_24h = 1 THEN '2 one'
                WHEN prior_n_24h < 5 THEN '3 2-4'
                ELSE '4 5+' END
    FROM train_hist
    UNION ALL
    SELECT isFraud, day, '3 time since previous order',
           CASE WHEN NOT has_card_id THEN '0 no card ID'
                WHEN secs_since_prev IS NULL THEN '1 no previous order'
                WHEN secs_since_prev < 60 THEN '2 under 1 minute'
                WHEN secs_since_prev < 3600 THEN '3 1-60 minutes'
                WHEN secs_since_prev < 86400 THEN '4 1-24 hours'
                WHEN secs_since_prev < 604800 THEN '5 1-7 days'
                ELSE '6 over 7 days' END
    FROM train_hist
    UNION ALL
    SELECT isFraud, day, '4 amount vs card average',
           CASE WHEN NOT has_card_id THEN '0 no card ID'
                WHEN amt_vs_prior_avg IS NULL THEN '1 no previous order'
                WHEN amt_vs_prior_avg < 0.5 THEN '2 under 0.5x'
                WHEN amt_vs_prior_avg <= 2 THEN '3 0.5-2x'
                WHEN amt_vs_prior_avg <= 5 THEN '4 2-5x'
                ELSE '5 over 5x' END
    FROM train_hist
    UNION ALL
    SELECT isFraud, day, '5 email domain new for card',
           CASE WHEN NOT has_card_id THEN '0 no card ID'
                WHEN is_first_seen THEN '1 no previous order'
                WHEN email_new_for_card THEN '3 new domain'
                ELSE '2 domain used before' END
    FROM train_hist
    UNION ALL
    SELECT isFraud, day, '6 email domains used before',
           CASE WHEN NOT has_card_id THEN '0 no card ID'
                WHEN is_first_seen THEN '1 no previous order'
                WHEN prior_n_email_domains = 0 THEN '2 none (email missing)'
                WHEN prior_n_email_domains = 1 THEN '3 one'
                ELSE '4 two or more' END
    FROM train_hist
),
base AS (SELECT AVG(isFraud) AS base_rate FROM train_hist)
SELECT feature, band,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY feature), 1) AS pct_orders,
       ROUND(100.0 * AVG(isFraud), 2) AS fraud_rate,
       ROUND(100.0 * 1.96 * sqrt(AVG(isFraud) * (1 - AVG(isFraud)) / COUNT(*)), 2) AS ci_half,
       ROUND(AVG(isFraud) / ANY_VALUE(base_rate), 2) AS lift,
       ROUND(100.0 * AVG(isFraud) FILTER (WHERE day > 28), 2) AS rate_after_day28
FROM bands, base
GROUP BY feature, band
ORDER BY feature, band;


-- ---------------------------------------------------------------------------
-- 6. Same check within products W and C, train days 29-101 only (TRAIN ONLY)
--    Product C is high-risk and has more repeat orders in 24h than W, so the
--    overall table above mixes product and history effects (see 04_explore.sql).
--    Days 1-28 dropped to avoid the left-censoring of "first seen".
-- ---------------------------------------------------------------------------
WITH h AS (
    SELECT isFraud, day, ProductCD, prior_n, prior_n_24h, secs_since_prev, is_first_seen
    FROM train_hist
    WHERE has_card_id AND day > 28 AND ProductCD IN ('W', 'C')
),
b AS (
    SELECT isFraud, ProductCD, 'history' AS feature,
           CASE WHEN is_first_seen THEN '1 first seen' WHEN prior_n < 5 THEN '2 1-4'
                WHEN prior_n < 20 THEN '3 5-19' ELSE '4 20+' END AS band
    FROM h
    UNION ALL
    SELECT isFraud, ProductCD, 'last 24h',
           CASE WHEN prior_n_24h = 0 THEN '1 none' WHEN prior_n_24h = 1 THEN '2 one'
                WHEN prior_n_24h < 5 THEN '3 2-4' ELSE '4 5+' END
    FROM h
    UNION ALL
    SELECT isFraud, ProductCD, 'since prev',
           CASE WHEN secs_since_prev IS NULL THEN '1 none' WHEN secs_since_prev < 3600 THEN '2 <1h'
                WHEN secs_since_prev < 86400 THEN '3 1-24h' WHEN secs_since_prev < 604800 THEN '4 1-7d'
                ELSE '5 7d+' END
    FROM h
)
PIVOT b
ON ProductCD
USING COUNT(*) AS n, ROUND(100.0 * AVG(isFraud), 2) AS rate
GROUP BY feature, band
ORDER BY feature, band;
