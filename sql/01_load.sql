-- 01_load.sql
-- Load the IEEE-CIS training files and join them into one table.
-- Expects: data/raw/train_transaction.csv, data/raw/train_identity.csv

-- sample_size = -1 makes the CSV sniffer scan the whole file,
-- so column types are inferred from all rows, not a sample.
CREATE OR REPLACE TABLE raw_transaction AS
SELECT * FROM read_csv('data/raw/train_transaction.csv', header = true, sample_size = -1);

CREATE OR REPLACE TABLE raw_identity AS
SELECT * FROM read_csv('data/raw/train_identity.csv', header = true, sample_size = -1);

-- LEFT join: not every transaction has identity data.
-- An inner join would silently drop those transactions.
CREATE OR REPLACE TABLE txn AS
SELECT
    t.*,
    i.* EXCLUDE (TransactionID),
    (i.TransactionID IS NOT NULL) AS has_identity
FROM raw_transaction AS t
LEFT JOIN raw_identity AS i
    ON t.TransactionID = i.TransactionID;
