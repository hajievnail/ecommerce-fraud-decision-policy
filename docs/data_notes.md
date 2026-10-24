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

## Data quality (session 3, `sql/03_quality.sql`, `sql/03_quality_checks.sql`)

### Zero-row checks
All 7 checks return 0 rows on the full data:
1. `TransactionAmt` missing or <= 0.
2. `isFraud` missing or not 0/1.
3. `TransactionDT` missing or negative.
4. Negative `dist1` / `dist2`.
5. Category values outside the allowed lists (NULL allowed except in `ProductCD`):
   - `ProductCD`: W, C, R, H, S
   - `card4`: visa, mastercard, american express, discover
   - `card6`: debit, credit, debit or credit, charge card
   - `DeviceType`: desktop, mobile
6. Identity values (`id_01`-`id_38`, `DeviceType`, `DeviceInfo`) filled on a row without an identity record.
7. `id_01` filled exactly when `has_identity` is true.

- The allowed lists were fixed on 2026-10-23 after listing the distinct values, so check 5 catches changes from that state; it does not prove the values are correct.
- Checks 5 and 6 were tested by flipping them (they must then return rows). This exposed a first version of check 6 that only caught rows with all 40 identity columns filled; it was rewritten to count filled values per column.

### Category values
- No spelling variants, empty strings or junk codes.
- `ProductCD` letters are masked; their meaning is unknown.
- `card6` has two tiny categories: "debit or credit" (30 rows) and "charge card" (15 rows). Likely merged into an "other" bin on Day 6.
- `card4` and `card6` are mostly missing together (1,565 rows both missing, 12 only `card4`, 6 only `card6`).
- `DeviceType` is empty on all 446,307 rows without identity and on 3,423 of the 144,233 rows with identity.

### Missing-value profile (table `quality_missing`)
- 437 columns: 55 never empty, 214 at least 50% empty, 12 at least 90% empty.

| Family | Columns | Median % empty | Most empty |
|---|---|---|---|
| core (ID, label, time, amount, product, has_identity, day, period) | 8 | 0 | 0 |
| C (counts) | 14 | 0 | 0 |
| card1-card6 | 6 | 0.3 | 1.5 (`card2`) |
| address / distance | 4 | 35.4 | 93.6 (`dist2`) |
| email domain | 2 | 46.4 | 76.8 (`R_emaildomain`) |
| M (match flags) | 9 | 47.7 | 59.4 (`M5`) |
| D (time deltas) | 15 | 52.5 | 93.4 (`D7`) |
| V (Vesta features) | 339 | 47.3 | 86.1 |
| id_ (identity, incl. DeviceType/DeviceInfo) | 40 | 79.2 | 99.2 |

- Columns needed later are nearly complete: `D1` 0.21% empty (card identity, Day 5), `card1` 0%, `addr1` 11.1% (needs handling in the card-ID recipe).
- Identity columns are mostly empty because 75.6% of transactions have no identity record (`id_01` is empty in exactly that share), not because of bad data.
- The 339 V columns fall into only 14 distinct null percentages, and several match a D column exactly (e.g. 12.88% ~ `D10`, 28.61% ~ `D4`, 47.29% ~ `D11`). Own observation, not verified: V columns seem to come in blocks built from the same source. Correlated blocks matter for the overlap check (Day 7).
- For the scorecard, "missing" will be its own bin rather than a reason to drop a column.

### Missingness by period (table `quality_missing_by_period`)
Label-free, so all periods are used. Average % empty per family:

| Family | Train | Validation | Test |
|---|---|---|---|
| core, C | 0 | 0 | 0 |
| card | 0.5 | 0.2 | 0.8 |
| address / distance | 44.2 | 44.2 | 42.7 |
| V | 42.7 | 44.0 | 43.1 |
| email domain | 45.3 | 47.3 | 48.8 |
| D | 60.0 | 55.9 | 54.8 |
| M | 58.7 | 36.8 | 36.4 |
| id_ | 82.4 | 88.0 | 87.2 |

- **Gradual fill-in during train:** `M1`-`M3`, `M7`-`M9`, `D11` and `V1`-`V11` are 58-71% empty in train but 28-40% in validation and test. Two-week blocks show a gradual fall (`D11`: ~69-74% empty in days 1-28, ~30% by days 85-98), then flat through validation and test. Not a single switch-over date. Cause unknown (masked features). Risk: a "missing" bin learned on train means something different later. Decide on Day 6/7 whether to prefer stable columns or use only the later part of train for these columns.
- **Identity burst:** 52% of transactions in days 15-28 have identity data, vs ~15-23% elsewhere (24.4% overall). Same window as the volume spike on days 20-24. This is why `id_` columns look more empty in validation/test. The spike days differ in kind, not only in volume.
- Email domain becomes slightly more often empty over time (45% -> 49%).

### Missingness by product (found during the session 3 review)
Label-free, all periods:

| Product | Orders | Has identity | `D11` empty | `R_emaildomain` empty |
|---|---|---|---|---|
| W | 439,670 | 0% | 29.2% | 100% |
| C | 68,519 | 90.8% | 100% | 3.1% |
| R | 37,699 | 99.6% | 100% | 0% |
| H | 33,024 | 99.6% | 100% | 32.8% |
| S | 11,628 | 99.6% | 100% | 5.1% |

- Missingness is mostly decided by the product: W never has identity data or a recipient email; `D11` exists only for W.
- So it is not "missing completely at random" (Rubin 1976; Little & Rubin, *Statistical Analysis with Missing Data*). It is mostly structural: the value does not exist for that product, rather than being unrecorded. No imputation; "missing" stays its own bin.
- "Identity missing" is close to "product W": expect a strong overlap in the Day 7 check (missing identity x product).
- Hypothesis, not checked: the identity burst on days 15-28 and the gradual D/M fill-in may come from changes in product mix rather than in data collection. Check (label-free) on Day 4.
