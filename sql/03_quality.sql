-- 03_quality.sql
-- Missing-value profile: share of nulls per column, over all periods.
-- Missingness does not use fraud labels, so looking at all periods is allowed.
--
-- DuckDB-specific: SUMMARIZE (one row per column, incl. null_percentage) and
-- using it as a subquery. In PostgreSQL / T-SQL you would compute, per column,
-- 100.0 * SUM(CASE WHEN col IS NULL THEN 1 ELSE 0 END) / COUNT(*).
-- regexp_matches is DuckDB's regex function (PostgreSQL: ~ operator).

CREATE OR REPLACE TABLE quality_missing AS
SELECT
    column_name,
    column_type,
    CAST(null_percentage AS DOUBLE) AS null_pct,
    CASE
        WHEN regexp_matches(column_name, '^C[0-9]+$')  THEN 'C (counts)'
        WHEN regexp_matches(column_name, '^D[0-9]+$')  THEN 'D (time deltas)'
        WHEN regexp_matches(column_name, '^M[0-9]+$')  THEN 'M (match flags)'
        WHEN regexp_matches(column_name, '^V[0-9]+$')  THEN 'V (Vesta features)'
        WHEN regexp_matches(column_name, '^id_[0-9]+$') THEN 'id_ (identity)'
        WHEN column_name IN ('DeviceType', 'DeviceInfo') THEN 'id_ (identity)'
        WHEN regexp_matches(column_name, '^card[0-9]$') THEN 'card'
        WHEN column_name IN ('addr1', 'addr2', 'dist1', 'dist2') THEN 'address / distance'
        WHEN column_name IN ('P_emaildomain', 'R_emaildomain') THEN 'email domain'
        ELSE 'core'
    END AS family
FROM (SUMMARIZE txn_split);

-- Missing-value profile by period (train / validation / test).
-- Still label-free, so all periods may be used. Shows whether the data
-- itself changes over time (e.g. a column that starts or stops being filled).
-- DuckDB-specific: COUNT(COLUMNS(* EXCLUDE (period))) counts non-null values in
-- every column at once; UNPIVOT turns the wide result into one row per column.
CREATE OR REPLACE TABLE quality_missing_by_period AS
WITH filled AS (
    SELECT *
    FROM (
        UNPIVOT (
            SELECT period, COUNT(*) AS n_rows, COUNT(COLUMNS(* EXCLUDE (period)))
            FROM txn_split
            GROUP BY period
        )
        ON COLUMNS(* EXCLUDE (period, n_rows))
        INTO NAME column_name VALUE filled_rows
    )
)
SELECT
    f.column_name,
    m.family,
    f.period,
    f.n_rows,
    100.0 * (f.n_rows - f.filled_rows) / f.n_rows AS null_pct
FROM filled AS f
JOIN quality_missing AS m USING (column_name);
