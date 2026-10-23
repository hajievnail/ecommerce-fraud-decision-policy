# Data notes

## Source
- IEEE-CIS Fraud Detection (Kaggle, data provided by Vesta): `train_transaction.csv` and `train_identity.csv`.
- Kaggle's test files are not used: they have no fraud labels.
- Raw files are not in the repo (see `.gitignore`); download them from the competition page into `data/raw/`.

## Load (session 1, `sql/01_load.sql`)
- 590,540 transactions, 20,663 frauds (3.50%).
- Identity file LEFT-joined on `TransactionID`: 144,233 transactions (24.4%) have identity data; every identity row matched a transaction.
- No duplicate `TransactionID` after the join.

## Time span (session 2)
- `TransactionDT` is seconds from an unknown reference point, not a real date.
- Day index: `day = floor(TransactionDT / 86400)`.
- Days 1 to 182, every day has data (no gaps), so about six months.
- Transactions per day: 2,048 to 6,852, average 3,245.
- Frauds per day: 51 to 234, average 113.5.
- Spike: four of the five busiest days fall on days 20-24 (about double the usual volume). The cause is unknown because real dates are unknown. Day 24 has a low fraud rate (76 frauds in 6,065 transactions, 1.3%).

## Train / validation / test split (session 2, `sql/02_split.sql`)
- Split by time on whole days, by share of **transactions** (not days).
- Rule, fixed before looking at results: each period ends on the first day where the running share of transactions reaches 60% / 80%.

| Period | Days | Number of days | Transactions | Share | Frauds | Fraud rate |
|---|---|---|---|---|---|---|
| Train | 1-101 | 101 | 356,216 | 60.32% | 12,039 | 3.38% |
| Validation | 102-141 | 40 | 118,790 | 20.12% | 4,682 | 3.94% |
| Test | 142-182 | 41 | 115,534 | 19.56% | 3,942 | 3.41% |

- Train covers 55% of days but 60% of transactions, because the busy days 20-24 fall in it.
- Validation has a higher fraud rate than train or test (3.94% vs 3.38% / 3.41%). With about 119,000 transactions, the standard error of the validation rate is about 0.06 percentage points, so the gap is real drift, not noise. Thresholds are chosen on validation, so they may be tuned to a more fraud-heavy period than test; the held-out test shows the effect honestly.
- Uses: train builds the scorecard; validation chooses thresholds and runs sensitivity; test is evaluated once for the headline result.

## Data freeze
- From session 2 on, the loaded data and the split (cut-offs at days 101 and 141) do not change.
- The cut-offs are hard-coded in `sql/02_split.sql` on purpose.
- Checks in `sql/02_split_checks.sql`: every transaction has one period, no day falls in two periods, shares close to 60/20/20.
