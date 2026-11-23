-- 09_failure_export.sql
-- Issue 9: export frozen aggregate tables as CSV for the Excel cost model (Issue 10) and Power BI (Issue 12).
-- Aggregates only. Transaction-level tables (fail_missed_top, fail_false_blocks_top, fail_actions_test,
-- txn_scored) are NOT exported: the competition rules forbid redistributing the data (docs/data_notes.md).
-- Run from the repo root.

COPY (SELECT * FROM eval_params)        TO 'excel/inputs/eval_params.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM best_thresholds)    TO 'excel/inputs/best_thresholds.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM policy_results ORDER BY period, policy) TO 'excel/inputs/policy_results.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM score_quality ORDER BY period) TO 'excel/inputs/score_quality.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM score_cum ORDER BY period, b) TO 'excel/inputs/score_cum.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM fail_freeze)        TO 'excel/inputs/fail_freeze.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM fail_missed_by_var ORDER BY var, n DESC) TO 'excel/inputs/fail_missed_by_var.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM fail_false_by_var ORDER BY var, n DESC)  TO 'excel/inputs/fail_false_by_var.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM fail_product_device) TO 'excel/inputs/fail_product_device.csv' (HEADER, DELIMITER ',');
COPY (SELECT * FROM fail_amount_device)  TO 'excel/inputs/fail_amount_device.csv' (HEADER, DELIMITER ',');
