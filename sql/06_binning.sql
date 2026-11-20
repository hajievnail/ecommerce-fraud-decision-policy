-- 06_binning.sql
-- Session 6: bins for the 9 scorecard variables, and train-only fraud rates per bin.
--
-- Variables (chosen 2026-11-20 from train-only information value, see docs/data_notes.md):
--   product, amount, email domain group, card6, device type, dist1, relative hour,
--   orders on the card in the last 24 h, time since the card's previous order.
--
-- Learning window (chosen 2026-11-20): bin rates are learned from TRAIN DAYS 29-101
-- only (229,550 orders, 8,925 frauds). Days 1-28 hold a flood of mostly legitimate
-- product H and R orders that stops after day 28 and does not appear in validation
-- or test (section 4 shows it); learning from them would badly underrate H/R/S.
-- The same cut gives the card history features a 28-day warm-up (left censoring at
-- the data start, see session 5 notes).
--
-- Bin rule (chosen 2026-11-20): every bin needs >= 100 frauds AND >= 1% of the
-- orders in the learning window. Small bins were merged: ordered variables with
-- their neighbour, categories with the bin of the nearest train fraud rate
-- (Apple email, 76 frauds in days 29-101, joined Yahoo).
-- Email domains are grouped by provider; relative hours into 5 bands of neighbouring
-- hours with similar train rates (coarse classing). The bin edges below are fixed
-- constants: they were chosen by looking at train data only, and they are applied
-- unchanged to validation and test. Any value never seen in train still gets a bin
-- (e.g. an unknown email domain falls into 'microsoft+other').
--
-- Section 1 (view txn_binned) reads NO label: it has no isFraud column.
-- Sections 2-6 read labels of the TRAIN period only (section 4 also counts orders,
-- without labels, in validation and test).
--
-- DuckDB-specific syntax (PostgreSQL / T-SQL equivalents):
--   UNPIVOT ... ON cols INTO NAME n VALUE v -> T-SQL has UNPIVOT with a different
--                                              syntax; PostgreSQL: a LATERAL (VALUES ...) join
--   GROUP BY ALL          -> list the grouping columns
--   FILTER (WHERE ...)    -> PostgreSQL has it; T-SQL: SUM(CASE WHEN ... END)
--   COLUMNS(...)          -> list the columns by hand
--   PIVOT ... ON x USING agg -> T-SQL PIVOT (different syntax); PostgreSQL: crosstab()
--                              or SUM(CASE WHEN ...) per column
--   a // b                -> integer division; PostgreSQL: a / b on integers; T-SQL: a / b


-- ---------------------------------------------------------------------------
-- 1. View txn_binned: one row per order, one bin label per variable. No labels.
--    Ordered variables get a leading number so the bins sort in their natural order.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW txn_binned AS
SELECT
    s.TransactionID,
    s.day,
    s.period,
    s.TransactionAmt,

    s.ProductCD AS b_product,

    CASE WHEN s.TransactionAmt < 50  THEN '1 <50'
         WHEN s.TransactionAmt < 100 THEN '2 50-99'
         WHEN s.TransactionAmt < 200 THEN '3 100-199'
         WHEN s.TransactionAmt < 500 THEN '4 200-499'
         ELSE '5 500+' END AS b_amount,

    CASE
      WHEN s.P_emaildomain IS NULL THEN 'missing'
      WHEN s.P_emaildomain IN ('gmail.com', 'gmail') THEN 'google'
      -- Yahoo and Apple share a bin: Apple alone had 76 frauds in days 29-101.
      WHEN s.P_emaildomain LIKE 'yahoo.%'
        OR s.P_emaildomain IN ('ymail.com', 'rocketmail.com',
                               'icloud.com', 'me.com', 'mac.com') THEN 'yahoo+apple'
      WHEN s.P_emaildomain IN ('aol.com', 'aim.com') THEN 'aol'
      WHEN s.P_emaildomain = 'anonymous.com' THEN 'anonymous'
      WHEN s.P_emaildomain IN ('att.net', 'sbcglobal.net', 'bellsouth.net', 'comcast.net',
                               'verizon.net', 'cox.net', 'optonline.net', 'charter.net',
                               'earthlink.net', 'roadrunner.com', 'juno.com', 'frontier.com',
                               'windstream.net', 'embarqmail.com', 'twc.com', 'prodigy.net.mx',
                               'netzero.com', 'netzero.net', 'q.com', 'frontiernet.net',
                               'centurylink.net', 'cfl.rr.com', 'sc.rr.com', 'cableone.net',
                               'suddenlink.net', 'ptd.net') THEN 'isp'
      -- Microsoft (hotmail.*, outlook.*, live.*, msn.com) and every other domain
      -- ('other' had 589 train orders, below the rule; nearest rate = Microsoft).
      ELSE 'microsoft+other' END AS b_email,

    CASE WHEN s.card6 = 'credit' THEN 'credit'
         ELSE 'debit/other/missing' END AS b_card6,

    COALESCE(s.DeviceType, 'missing') AS b_device,

    CASE WHEN s.dist1 IS NULL  THEN '0 missing'
         WHEN s.dist1 = 0      THEN '1 0'
         WHEN s.dist1 <= 5     THEN '2 1-5'
         WHEN s.dist1 <= 20    THEN '3 6-20'
         WHEN s.dist1 <= 100   THEN '4 21-100'
         WHEN s.dist1 <= 500   THEN '5 101-500'
         ELSE '6 501+' END AS b_dist1,

    -- Relative hour = hours since the data's start, modulo 24 (real time zone unknown).
    CASE WHEN h.hr BETWEEN 4  AND 5  THEN '2 04-05'
         WHEN h.hr BETWEEN 6  AND 9  THEN '3 06-09'
         WHEN h.hr BETWEEN 10 AND 12 THEN '4 10-12'
         WHEN h.hr BETWEEN 13 AND 15 THEN '5 13-15'
         ELSE '1 16-03' END AS b_hour,

    -- Orders without a card ID (missing D1) go with "no earlier order": no history known.
    CASE WHEN NOT f.has_card_id OR f.prior_n_24h = 0 THEN '1 0 or no id'
         WHEN f.prior_n_24h = 1 THEN '2 1'
         WHEN f.prior_n_24h < 5 THEN '3 2-4'
         ELSE '4 5+' END AS b_n24h,

    CASE WHEN NOT f.has_card_id OR f.secs_since_prev IS NULL THEN '0 none or no id'
         WHEN f.secs_since_prev < 60     THEN '1 <1m'
         WHEN f.secs_since_prev < 3600   THEN '2 1m-1h'
         WHEN f.secs_since_prev < 86400  THEN '3 1h-1d'
         WHEN f.secs_since_prev < 604800 THEN '4 1d-7d'
         ELSE '5 7d+' END AS b_gap
FROM txn_split s
JOIN card_features f USING (TransactionID)
CROSS JOIN LATERAL (SELECT CAST(floor(s.TransactionDT / 3600) AS INTEGER) % 24 AS hr) h;


-- ---------------------------------------------------------------------------
-- 2. Table bin_rates: TRAIN days 29-101 only. One row per variable x bin.
--    rate      = frauds / orders
--    ci_low/hi = Wilson 95% interval for the rate (Wilson 1927; recommended over the
--                simple +-1.96*SE interval by Agresti & Coull 1998)
--    lift      = bin rate / overall rate in the learning window
--    passes_rule = bin has >= 100 frauds and >= 1% of the window's orders
-- ---------------------------------------------------------------------------
CREATE OR REPLACE TABLE bin_rates AS
WITH long AS (
    UNPIVOT (
        SELECT b.TransactionID, s.isFraud, COLUMNS('^b_')
        FROM txn_binned b
        JOIN txn_split s USING (TransactionID)
        WHERE b.period = 'train' AND b.day >= 29
    )
    ON COLUMNS('^b_')
    INTO NAME var VALUE bin
),
agg AS (
    SELECT replace(var, 'b_', '') AS var, bin,
           COUNT(*)     AS orders,
           SUM(isFraud) AS frauds
    FROM long
    GROUP BY ALL
),
tot AS (
    SELECT COUNT(*) AS n_train, SUM(isFraud) AS f_train
    FROM txn_split WHERE period = 'train' AND day >= 29
)
SELECT
    a.var, a.bin, a.orders, a.frauds,
    a.frauds / a.orders                                   AS rate,
    -- Wilson interval, z = 1.96
    (a.frauds / a.orders + 1.96^2 / (2 * a.orders)
       - 1.96 * sqrt(a.frauds / a.orders * (1 - a.frauds / a.orders) / a.orders
                     + 1.96^2 / (4 * a.orders^2)))
      / (1 + 1.96^2 / a.orders)                           AS ci_low,
    (a.frauds / a.orders + 1.96^2 / (2 * a.orders)
       + 1.96 * sqrt(a.frauds / a.orders * (1 - a.frauds / a.orders) / a.orders
                     + 1.96^2 / (4 * a.orders^2)))
      / (1 + 1.96^2 / a.orders)                           AS ci_high,
    (a.frauds / a.orders) / (t.f_train / t.n_train)      AS lift,
    a.frauds >= 100 AND a.orders >= 0.01 * t.n_train      AS passes_rule
FROM agg a CROSS JOIN tot t
ORDER BY a.var, a.bin;

SELECT var, bin, orders, frauds,
       round(100 * rate, 2)    AS rate_pct,
       round(100 * ci_low, 2)  AS ci_low_pct,
       round(100 * ci_high, 2) AS ci_high_pct,
       round(lift, 2)          AS lift,
       passes_rule
FROM bin_rates
ORDER BY var, bin;


-- ---------------------------------------------------------------------------
-- 3. Information value per variable with the final bins (TRAIN days 29-101).
--    IV = sum over bins of (legit% - fraud%) * ln(legit% / fraud%)
--    (Siddiqi, Intelligent Credit Scoring). Rule of thumb: < 0.02 not useful,
--    0.02-0.1 weak, 0.1-0.3 medium, > 0.3 strong.
-- ---------------------------------------------------------------------------
SELECT var,
       COUNT(*) AS bins,
       round(SUM((legit_pct - fraud_pct) * ln(legit_pct / fraud_pct)), 3) AS iv
FROM (
    SELECT var, bin,
           frauds            / SUM(frauds)            OVER (PARTITION BY var) AS fraud_pct,
           (orders - frauds) / SUM(orders - frauds)   OVER (PARTITION BY var) AS legit_pct
    FROM bin_rates
)
GROUP BY var
ORDER BY iv DESC;


-- ---------------------------------------------------------------------------
-- 4. Why the learning window starts at day 29.
--    a) Orders per product per 2-week block, ALL periods (no labels read).
--    b) Fraud rate per product per 2-week block, TRAIN only.
--    Days 1-28 (blocks 0-1) hold ~8,000-15,000 H and R orders per block at
--    0.7-2.1% fraud; from day 29 on, H and R run at ~1,000-2,000 per block at
--    5-18% fraud, in train, validation and test alike.
-- ---------------------------------------------------------------------------
PIVOT (SELECT (day - 1) // 14 AS block, period, b_product FROM txn_binned)
ON b_product USING COUNT(*)
GROUP BY block, period
ORDER BY block, period;

PIVOT (
    SELECT (b.day - 1) // 14 AS block, b.b_product, s.isFraud
    FROM txn_binned b JOIN txn_split s USING (TransactionID)
    WHERE b.period = 'train'
)
ON b_product USING round(100 * AVG(isFraud), 1)
GROUP BY block
ORDER BY block;


-- Long format of the learning window, used by sections 5 and 6.
CREATE OR REPLACE TEMP TABLE learn_long AS
UNPIVOT (
    SELECT b.TransactionID, b.day, s.isFraud, COLUMNS('^b_')
    FROM txn_binned b JOIN txn_split s USING (TransactionID)
    WHERE b.period = 'train' AND b.day >= 29
)
ON COLUMNS('^b_')
INTO NAME var VALUE bin;


-- ---------------------------------------------------------------------------
-- 5. Stability inside the learning window: lift per bin, days 29-65 vs 66-101.
--    Lift is measured against each half's own base rate, so an overall rise or
--    fall in fraud does not count as instability. Sorted by the size of the change.
-- ---------------------------------------------------------------------------
WITH h AS (
    SELECT replace(var, 'b_', '') AS var, bin,
           CASE WHEN day <= 65 THEN 'a' ELSE 'b' END AS half,
           COUNT(*) AS n, SUM(isFraud) AS f
    FROM learn_long
    GROUP BY ALL
),
base AS (
    SELECT half, SUM(f) / SUM(n) AS r FROM h WHERE var = 'product' GROUP BY half
),
l AS (
    SELECT h.*, (f / n) / base.r AS lift FROM h JOIN base USING (half)
)
SELECT a.var, a.bin,
       a.f AS frauds_29_65, b.f AS frauds_66_101,
       round(a.lift, 2) AS lift_29_65, round(b.lift, 2) AS lift_66_101,
       round(exp(abs(ln(b.lift / a.lift))), 2) AS change_factor
FROM l a
JOIN l b ON a.var = b.var AND a.bin = b.bin AND a.half = 'a' AND b.half = 'b'
ORDER BY change_factor DESC;


-- ---------------------------------------------------------------------------
-- 6. Clustering: how many distinct cards are behind the frauds in each history bin
--    (learning window). Many frauds from few cards would mean a bin's rate is
--    driven by a handful of fraud runs rather than a general pattern.
-- ---------------------------------------------------------------------------
SELECT replace(l.var, 'b_', '') AS var, l.bin,
       SUM(l.isFraud) AS frauds,
       COUNT(DISTINCT c.card_id) FILTER (WHERE l.isFraud = 1) AS fraud_cards,
       round(SUM(l.isFraud) / COUNT(DISTINCT c.card_id) FILTER (WHERE l.isFraud = 1), 1)
           AS frauds_per_card,
       max(cf.top_card_frauds) AS top_card_frauds
FROM learn_long l
JOIN card_features c USING (TransactionID)
LEFT JOIN (
    SELECT var, bin, max(n) AS top_card_frauds
    FROM (SELECT l2.var, l2.bin, c2.card_id, COUNT(*) AS n
          FROM learn_long l2 JOIN card_features c2 USING (TransactionID)
          WHERE l2.isFraud = 1 AND c2.card_id IS NOT NULL
          GROUP BY ALL)
    GROUP BY ALL
) cf ON cf.var = l.var AND cf.bin = l.bin
WHERE l.var IN ('b_gap', 'b_n24h')
GROUP BY ALL
ORDER BY var, bin;
