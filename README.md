# E-commerce fraud: order decision policy

Approve, send to manual review, or block? A cost-based decision policy for e-commerce orders, built as a SQL risk scorecard with an Excel cost model and a Power BI dashboard, on the IEEE-CIS Fraud Detection data.

> Work in progress. Sections marked *TBD* are filled in as the project progresses.

## Business question
*TBD*

## Headline result
*TBD: chosen (review, block) thresholds, cost saving vs. baseline on the held-out test period, statistical test, sensitivity range.*

## Recommendation
*TBD*

## Method
*TBD: data split, scorecard, threshold choice, evaluation.*

## Failure analysis
*TBD*

## Limitations
*TBD*

## Repository structure
| Folder | Contents |
|---|---|
| `sql/` | Numbered SQL scripts: load, checks, split, scorecard, marts |
| `excel/` | Cost model and Power Query code |
| `powerbi/` | Dashboard, DAX measures, screenshots |
| `docs/` | Data notes, assumptions, hours log |

## How to reproduce
1. Join the [IEEE-CIS Fraud Detection](https://www.kaggle.com/competitions/ieee-fraud-detection) competition on Kaggle and accept its rules.
2. Download `train_transaction.csv` and `train_identity.csv` into `data/raw/`.
3. Install [DuckDB](https://duckdb.org/) (CLI).
4. From the repo root, run: `duckdb data/fraud.duckdb < run_all.sql`

Details on the data and the train / validation / test split: [`docs/data_notes.md`](docs/data_notes.md).
