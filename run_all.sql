-- run_all.sql: rebuild everything from the raw files.
-- Usage (from the repo root):  duckdb data/fraud.duckdb < run_all.sql
-- Each session adds its scripts here, in order.

.read sql/01_load.sql
.read sql/01_load_checks.sql
