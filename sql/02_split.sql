-- 02_split.sql
-- Day index and time-based three-way split.
--
-- day: TransactionDT counts seconds from an unknown reference point (not a real date).
-- 86,400 seconds = 1 day, so floor(TransactionDT / 86400) gives a whole-day number.
--
-- period: split by share of TRANSACTIONS, on whole days.
-- Rule (fixed before looking at results): each period ends on the first day
-- where the running share of transactions reaches 60% / 80%.
--   train      = days 1-101   (60.32% of transactions)
--   validation = days 102-141 (20.12%)
--   test       = days 142-182 (19.56%)
-- The cut-offs are hard-coded on purpose: this is the data freeze.

CREATE OR REPLACE VIEW txn_split AS
WITH t AS (
    SELECT
        *,
        CAST(floor(TransactionDT / 86400) AS INTEGER) AS day
    FROM txn
)
SELECT
    *,
    CASE
        WHEN day <= 101 THEN 'train'
        WHEN day <= 141 THEN 'validation'
        ELSE 'test'
    END AS period
FROM t;