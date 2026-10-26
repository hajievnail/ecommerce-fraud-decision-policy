-- run_all.sql: rebuild everything from the raw files.
-- Usage (from the repo root):  duckdb data/fraud.duckdb < run_all.sql
-- Each session adds its scripts here, in order.

-- Session 1: load and join
.read sql/01_load.sql
.read sql/01_load_checks.sql

-- Session 2: day index and train / validation / test split
.read sql/02_split.sql
.read sql/02_split_checks.sql

-- Session 3: data quality (missing-value profile and zero-row checks)
.read sql/03_quality.sql
.read sql/03_quality_checks.sql

-- Session 4: exploration (train-only fraud rates) and baseline sizing
.read sql/04_explore.sql
