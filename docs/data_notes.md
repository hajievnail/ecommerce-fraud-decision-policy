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
- **Identity burst:** 52% of transactions in days 15-28 have identity data, vs 34% in days 1-14 and ~15-23% after day 28 (24.4% overall). Same window as the volume spike on days 20-24. This is why `id_` columns look more empty in validation/test. The spike days differ in kind, not only in volume.
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
- Checked in session 4: the high identity share in days 1-28 (burst on days 15-28) is a product-mix effect; the gradual D/M fill-in is not (it happens within product W). See "Exploration" below.

## Exploration (session 4, `sql/04_explore.sql`)

Fraud-rate queries use the **train period only** (days 1-101; 356,216 orders, base fraud rate 3.38%). Lift = group fraud rate / 3.38%. 95% confidence intervals use rate +/- 1.96 x sqrt(p(1-p)/n); this approximation is unreliable for small groups or groups with (almost) no frauds, so such groups are only flagged, not interpreted. "Within W" comparisons control for product only, not for other variables. Bands and groupings here are for exploration; the final bins are set on Day 6.

Leakage test (2026-10-26): all validation/test labels were flipped in a scratch copy of `txn_split` and the whole script re-run; the output was identical, so no query uses non-train labels.

### Product mix over time (label-free, all periods)
- **The identity burst is a product-mix effect.** Products R/H/S are 25.5% of orders in days 1-14 and 40.6% in days 15-28 (W falls to 45.8%), vs ~6-12% in every later two-week block. Among non-W orders, the share with identity stays at ~92-99% throughout.
- **The volume spike (days 20-24, session 2) is a non-W spike.** Per day: W 2,502 orders vs 2,512 on other train days (unchanged); R/H/S 2,763 vs 494 (5.6x); C 778 vs 389 (2x). Why is unknown (products are masked).
- **The D/M fill-in is not.** Within product W alone, `D11` goes from ~52% empty (days 1-14) to 8-25% (two-week blocks in validation/test) and `M7` from ~72% to 21-28%, while W's share stays at 76-83% after day 29. Real drift inside W; treat D/M "missing" bins with care.

### Product
| Product | Share of orders | Share of frauds | Fraud rate | Lift | Median amount | Fraud % of the product's $ |
|---|---|---|---|---|---|---|
| C | 11.6% | 36.8% | 10.74% | 3.18 | $31 | 11.7% |
| S | 1.8% | 3.2% | 5.99% | 1.77 | $30 | 8.1% |
| H | 7.5% | 9.5% | 4.27% | 1.26 | $50 | 9.7% |
| R | 7.9% | 7.6% | 3.22% | 0.95 | $125 | 4.4% |
| W | 71.2% | 43.0% | 2.04% | 0.60 | $79 | 2.7% |

- Product shows the largest risk differences among variables that cover many orders, and it is the main confounder for the other variables. Product codes are masked, so their meaning is unknown.

### Card
- Credit 6.28% vs debit 2.30% (lift 1.86 vs 0.68). Holds within products: W 4.25% vs 1.60%, C 16.27% vs 6.92%.
- Network: visa 3.26%, mastercard 3.56% (small difference); discover 6.15% (1.2% of orders), also high within W (6.96%). American Express never appears in W and almost never in C (2 orders); Discover never in C.
- "debit or credit" (23 orders) and "charge card" (12) have no frauds: too small to judge.

### Purchaser email domain
- Most of the apparent differences are product C: hotmail.com 5.18% overall but 52% of its orders are C, and only 1.90% within W; outlook.com 8.44% overall, 3.07% within W.
- ISP domains are genuinely low-risk, also within W: att.net 0.51% overall (0.64% within W), sbcglobal.net 0.37% (0.39%), verizon.net 0.63% (0.70%).
- Missing email (2.89%) and anonymous.com (2.39%) are not risky.

### Amount
- Train amounts: median $70, 90th percentile ~$280, 99th ~$1,086, max $31,937.
- Small amounts look risky (<$10: 8.06%) only because 89% of them are product C; within W small amounts are the safest (1.3-1.7%).
- Within a product, risk rises with amount, then falls: W from 1.3% ($10-25) to 4.3% ($500-1,000), then 1.6% at $1,000+. This curve (plus the C confounding) is why the correlation of amount with fraud is ~0.
- Fraud dollars sit in mid-to-high amounts: $200-1,000 orders are 16% of orders but 56% of fraud dollars (train fraud total ~$1.69M).

### Relative hour of day
- `rel_hour = floor(TransactionDT / 3600) % 24`; the real time zone is unknown, so hour 0 is not necessarily midnight.
- Volume drops sharply around hours 7-10 (<1% of orders per hour); fraud rate peaks there (7-10%, lift 2.2-3.1) and stays high within W (3.4-4.9%). Hours 4-10 together are ~7.8% of train orders (hours 7-10 alone ~2.0%).

### Identity and device
- With identity 6.74% vs without 2.11%, but this is mostly product (W never has identity).
- Within C, with identity 11.34% vs without 5.98%: a real extra effect. For H/R/S the no-identity groups are too small (25-119 orders).
- Among orders with identity: mobile 9.14% vs desktop 5.43% (within C 12.74% vs 10.37%).

### Distance (`dist1`, added after the session 4 audit)
- `dist1` exists **only for product W** (100% missing in C, H, R, S; 46.9% missing within W in train), so it is analysed within W. Integers from 0 to 10,286; median 9, 90th percentile 347.
- Within W (W rate 2.04%): short distances are slightly safer (0-20: 1.56-1.87%, lift vs W 0.76-0.91); 101-2,000 is riskier (3.13-3.15%, lift ~1.5); 2,001+ is 2.63% but rests on 1,561 orders (+/- 0.79 pp). Missing is average (2.13%).
- Far distances (101+) are only ~8% of W orders, so the signal is modest. Median amount and credit-card share are similar across bands, so the effect is not simply amount or card type.
- `dist2` (93% missing in train) is not explored.
- Unlike `D11` / `M7`, `dist1` missingness within W shows no trend over time (38-54% in every two-week block).
- What `dist1` measures is not documented in detail (masked); do not interpret it as a specific distance.

### Implications for the scorecard (to decide on Days 6-7)
- Strong candidates: product, card type, amount (binned), relative hour (grouped).
- Weaker or tangled with product: email domain (grouped; the clear signal is the low-risk ISP domains), device type (only ~27% of train orders have it).
- Use identity as part of a product x identity variable rather than on its own, to avoid double counting.
- Distance (`dist1`): a modest, W-only signal (far = ~1.5x W's rate); a few bins (near / far / missing) at most.
- Worth checking on Day 6: whether per-bin fraud rates are stable within train (early vs late train), since the first four weeks of train have a different product mix.
- Overlap checks on Day 7: email domain x product, identity x product, amount x product.
- Cost is driven by dollars, so later steps report fraud dollars as well as counts.

## Baseline policies (session 4, chosen 2026-10-26)

The scorecard policy is judged against two baselines.

1. **Main baseline (used in the headline): review the largest orders.**
   - Rule: send an order to manual review if `TransactionAmt >= X`; approve everything else; block nothing.
   - `X` is set on **validation**: the lowest amount threshold whose daily review load fits the review capacity. This is the same capacity rule the scorecard policy must meet, so the comparison is like for like.
   - A fixed threshold is used rather than "the K largest orders of each day", because in real time the day's largest orders are not known in advance.
   - It uses no fraud labels; its only input is the review capacity (a cost assumption, set later and covered by sensitivity analysis).
   - Open (decide on Day 8): what "fits capacity" means (every day, on average, or most days). The same rule applies to the baseline and the scorecard policy.
2. **Reference: approve everything** (no screening). Shows the cost of doing nothing.

Why (train sizing in `sql/04_explore.sql`, section 8):
- Amount rules catch fraud **dollars**: the top 10% of orders by amount hold 49.4% of fraud dollars (13.9% of frauds).
- Blocking large orders would be a poor baseline: orders over $1,000 have below-average fraud (1.7%), and the top 10% by amount include $20.6M of legitimate orders.
- A "product C" rule catches counts (36.8% of frauds) but only 12.4% of fraud dollars, and it comes from our own exploration, so it is not a naive policy. Optional extra comparison on Day 8, not part of the headline.
