# Credit Risk Scorecard Monitoring

An end-to-end demonstration of **ML model monitoring** for a credit-risk scorecard — scoring
through drift and performance tracking — built on a clean, modern stack
(Python · scikit-learn · DuckDB · BigQuery · dbt). The monitoring layer is the deliverable; the model is
deliberately kept simple so the monitoring stays legible.

## What this is (and isn't)

Production credit-scoring systems often adopt **stacked architectures** — gradient-boosted
sub-models trained on category-specific feature pillars (demographic, behavioural, bureau)
producing sub-scores that feed a final logistic regression for transparent, regulator-friendly
calibration. This project deliberately collapses that pattern into a **single-stage logistic
regression** on a hand-selected feature set. The point isn't the model — it's the monitoring
infrastructure (PSI, Gini tracking, per-feature drift) built around it, and a single-stage model
keeps that demonstration readable.

The opinionated choices are signals, not gaps:

- **Logistic regression, not gradient boosting.** A monotonic, inspectable scorecard is the
  right substrate for a monitoring demo — every score movement traces back to a feature.
- **`EXT_SOURCE` features excluded.** The dataset's strongest predictors are opaque external
  scores. Dropping them costs raw performance but keeps every feature interpretable, which is
  the entire premise of a transparency-first scorecard.
- **Engine-portable SQL — DuckDB locally, BigQuery in prod.** The monitoring transformations
  are warehouse-grade SQL, developed on DuckDB and translated to BigQuery. DuckDB makes the whole
  pipeline reproducible on a laptop with no infrastructure to stand up; the same models run on
  BigQuery as the production warehouse, validated to reproduce every published metric identically
  (see *Warehouse portability*).

## Stack

| Layer | Tooling |
|---|---|
| Scoring | Python, pandas, scikit-learn |
| Storage / SQL engine | DuckDB (dev) · BigQuery (prod) |
| Monitoring transforms | dbt |
| CI/CD | GitHub Actions |
| Data | Home Credit Default Risk (Kaggle) |

## Warehouse portability

The pipeline is DuckDB-first — the entire build, tests included, runs on a laptop with no cloud
account. The same transformation layer also runs on **BigQuery** as a production target, against
raw tables landed in a `phase1` dataset (see §6).

This was a deliberate translation, not a free lunch. DuckDB and BigQuery agree on most ANSI SQL but
diverge in specifics, and each divergence was resolved portably rather than by branching dialects:

- `USING(col)` joins → explicit `ON a.col = b.col`
- `quantile_cont(...)` aggregate → `percentile_cont(...) over ()`
- `||` integer concatenation → explicit `cast(... as string)`
- `(values …) as t(cols)` fixtures → `union all select` with named columns
- a `round(sum(...), 10)` before rank-based metrics, absorbing cross-engine float-summation order
  differences that would otherwise flip mid-rank tie boundaries

After translation, the prod build reproduces the validated metrics — pooled Gini pins to
`0.36619854813983066`, the PSI cohorts match — enforced as dbt tests that run *on* the BigQuery
target, not just asserted in prose.

## Architecture

```
Phase 1 — Scoring (Python)          Phase 2 — Monitoring (dbt + DuckDB/BigQuery)
─────────────────────────          ───────────────────────────────────
raw Kaggle tables                   scored_applications.csv ─┐
   │ feature engineering            model_features.csv ──────┼─► score PSI (by period)
   │ monotonic WOE binning          model_coefficients.csv ──┘   per-feature PSI (grouped)
   │ IV selection + prune                                        Gini (by period)
   ▼                                                             pillar Gini + alert tiers
scored_applications.csv
model_features.csv
model_coefficients.csv
bin_definitions.csv   — WOE/IV dictionary; reference, not consumed by the dbt layer
```

## Running it

Phase 2 reads the Phase 1 outputs from `data/processed/` (produced by the Phase 1 notebook). With
those in place, the pipeline is a **two-step run** — load the sources into `phase1`, then build.
Setup starts at the repo root and ends inside `dbt_project/`; every command after it runs from
there.

**Setup**
```bash
python -m venv .venv && source .venv/bin/activate
pip install dbt-core dbt-duckdb dbt-bigquery
cd dbt_project
dbt deps           # pulls dbt_utils (packages.yml)
```

**dev — DuckDB, no cloud account**
```bash
python ../scripts/load_rawdata.py    # CSVs → phase1 in dev.duckdb
dbt build --target dev
```

**prod — BigQuery (your own GCP project; phase1 dataset in asia-southeast1)**
```bash
gcloud auth application-default login
export DBT_BIGQUERY_PROJECT=your-project-id   # dbt requires this; load_bigquery.py falls back to it
python ../scripts/load_bigquery.py            # CSVs → phase1 dataset via load jobs
dbt build --target prod
```

The load must finish before `dbt build`: DuckDB allows a single read-write connection, so a
held-open notebook connection blocks the build (see Production Notes → DuckDB concurrency).

---

## Phase 1 — The Model

**Data.** 

Home Credit Default Risk (Kaggle): 307,511 applications, ~8% default base rate.
Predictors are anchored on aggregated credit-bureau history, widened with application-form
demographic, employment, financial, and region features.

**Feature pipeline.**

- Widened candidate pool of 57 features across five groups (`bureau_credit`, `employment`,
  `demographic`, `financial`, `region`); `EXT_SOURCE` columns excluded by design.
- **Monotonic WOE binning.** Numeric features are binned to enforce a monotonic weight-of-
  evidence on observed values; structural-zero values (no bureau history, no overdue amount)
  get a *pinned zero bin* with its own floating WOE rather than being forced into the monotonic
  tail — so a "has no bureau record" applicant isn't blended into the lowest credit-amount band.
- **Rare-category collapse.** Categorical levels below 1% of non-missing rows fold into
  `"Other"` (e.g. `ORGANIZATION_TYPE`: 58 levels → 17). This is both an overfit fix and a
  mild-leakage mitigation, since WOE is a supervised encoding fit on the full data.
- **Selection.** Information Value floor of 0.02 → greedy redundancy prune at WOE-correlation
  > 0.85 (5 collinear pairs removed, e.g. region rating with/without city) → hard cap at
  top-12 by IV.

**Model.** 

Plain logistic regression on WOE-encoded features (not class-balanced —
`class_weight` barely moves a rank-based metric, and plain weights keep predicted probabilities
calibrated to the true ~8% base rate, which a scored-and-monitored scorecard needs).

**Result.** 5-fold stratified CV: **AUC 0.683 ± 0.003, Gini 0.366 ± 0.006** — in line with
published no-`EXT_SOURCE` logistic-regression baselines on this dataset (~0.68 AUC). A lean
model drawn from a wide candidate pool, trading a few points of AUC for full interpretability.

**Selected features (12).**

| Feature | Group | IV |
|---|---|---|
| `bur_avg_util_ratio` | bureau_credit | 0.143 |
| `bur_avg_credit_days` | bureau_credit | 0.132 |
| `DAYS_EMPLOYED` | employment | 0.092 |
| `DAYS_BIRTH` | demographic | 0.084 |
| `bur_newest_credit_days` | bureau_credit | 0.080 |
| `OCCUPATION_TYPE` | employment | 0.079 |
| `credit_to_goods` | financial | 0.071 |
| `NAME_INCOME_TYPE` | employment | 0.058 |
| `bur_avg_end_days` | bureau_credit | 0.058 |
| `ORGANIZATION_TYPE` | employment | 0.058 |
| `REGION_RATING_CLIENT_W_CITY` | region | 0.051 |
| `NAME_EDUCATION_TYPE` | demographic | 0.051 |

Group mix: bureau_credit 4 · employment 4 · demographic 2 · financial 1 · region 1.

---

## Phase 2 — Monitoring Design

### 1. Synthetic time periods

Applications are ordered by `DAYS_DECISION` and split into `n_periods` **equal-frequency** cohorts
with `NTILE` — each period holds roughly the same number of records rather than the same span of
calendar time. The ordering runs oldest-first, so `P0` is the oldest cohort and the highest period
the most recent; left-to-right reading maps to forward time progression. With `n_periods = 6` this
yields `P0`–`P5`. Both the period count (`n_periods`) and the sentinel value (`m_sentinel`) are
dbt vars.

**Why equal-frequency, not fixed calendar windows:** Quantile cohorts guarantee every period
carries enough volume for stable PSI and Gini estimates; equal-width calendar buckets would leave
thinly populated cohorts at the ends of the range, where the metrics are dominated by sampling
noise. The trade-off is that period boundaries are population-defined rather than calendar-defined
— §2 covers why a recency-ordered cohort is still a meaningful monitoring unit.

**Sentinel cohort `M`:** Applicants with no prior Home Credit application have no real
`DAYS_DECISION` and are assigned a sentinel value (`m_sentinel`, `299`). These rows are filtered
out of the `NTILE` split and labelled `M` separately, so an imputed-recency block does not distort
the genuine recency cohorts.

**Determinism:** The window orders by `days_decision, sk_id_curr`; the `sk_id_curr` tiebreaker makes
cohort assignment reproducible when many rows share a `days_decision`.

```sql
-- non-sentinel rows → equal-frequency cohorts, P0 = oldest
ntile({{ var('n_periods') }}) over (order by days_decision, sk_id_curr) as period_idx
-- label as 'P' || (period_idx - 1)          →  P0 … P5
-- rows where days_decision = {{ var('m_sentinel') }}  →  period = 'M'
```

### 2. Domain justification for the 90-day offer window

In consumer credit products, an offer is valid for roughly 90 days. If a customer does not
proceed to application within that window, the offer expires and the customer must be re-scored
before a new `DAYS_DECISION` is recorded. So each 90-day window captures a population scored
under roughly the same model conditions and converted within the same offer cycle — closer to a
**model application cohort** than an arbitrary time slice. PSI across these cohorts therefore
measures cohort stability, not just generic score drift.

### 3. PSI reference period

Period 0 (oldest stable cohort) is the expected distribution, following the convention of using
the initial model-rollout population as the baseline.

**Known limitation:** In production, the reference period is immediately affected by downstream
strategy changes. A PSI spike may reflect strategy-induced population selection rather than
genuine model drift — e.g. if credit policy tightens, the incoming applicant pool changes and
PSI spikes even with a stable model. Correct interpretation requires cross-referencing strategy
change logs, typically owned by the business side. This pipeline computes the metric;
interpretation requires business context not captured here.

### 4. Score bins

10 deciles based on the Period 0 score distribution only. Bin edges are computed once from the
reference period and applied to all subsequent periods — per-period decile computation would
guarantee 10% per bin by construction, eliminating the signal PSI is meant to detect.

**Score concentration:** Bins 4–6 cover a narrow score range (~0.483–0.501), indicating heavy
concentration around the decision boundary. PSI in these bins is more sensitive to small shifts
than in the outer bins. This is a calibration characteristic of the model, not a pipeline issue.

**Boundary bins:**

- Bin 1: `(-∞, p10]` — no lower bound
- Bin 10: `(p90, +∞)` — no upper bound

Represented as `NULL` in the edges table and handled via `IS NULL` conditions in the range join,
so scores falling outside the Period 0 range in future periods are still assigned to the correct
boundary bin rather than dropped.

### 5. Materialization strategy

Every model materializes as a `view`. On this static, single-load dataset a view recomputes instantly, so persisting tables buys nothing and avoids stale state — the build stays fully reproducible. A production pipeline on live, growing data would materialize the marts incrementally instead (see Production Notes).

The two test fixture rows back the PSI stress test and are intentionally excluded from the DAG (see Reference → DAG structure), which documents the production data flow only.

| Model | Layer | Materialized |
|---|---|---|
| stg_scored_applications | staging | view |
| stg_model_features | staging | view |
| stg_model_coefficients | staging | view |
| int_period_assignment | intermediate | view |
| int_score_pooled | intermediate | view |
| int_score_with_deciles | intermediate | view |
| int_score_with_periods | intermediate | view |
| int_score_decile_counts | intermediate | view |
| int_subscore_by_pillar | intermediate | view |
| int_subscore_by_pillar_with_periods | intermediate | view |
| int_features_with_periods | intermediate | view |
| int_features_with_bins | intermediate | view |
| mart_psi_score | mart | view |
| mart_psi_features | mart | view |
| mart_gini_by_period | mart | view |
| mart_gini_by_pillar | mart | view |
| mart_gini_by_pillar_with_periods | mart | view |
| mart_gini_pooled | mart | view |
| stress_psi_gap | test fixture | view |
| mart_psi_gap_stress | test fixture | view |

### 6. Data source strategy

The three Phase 1 outputs the monitoring layer consumes — `scored_applications`,
`model_features`, and `model_coefficients` — are **materialized into a `phase1` schema by a
standalone pre-load script**, and dbt reads them through declared **sources**, not in-model file
reads. The build is therefore a two-step run: load first, then `dbt build`.

This is deliberately a pre-load step rather than `dbt seed`. Seeds are meant for small static
reference data; the feature table is long-format (~3.7M rows), well past what seeds handle without
tokenization warnings. A pre-load script handles real-size data and, more importantly, keeps the
**source contract identical across engines** — a dbt source's declared schema is the literal
`phase1`, so `source('raw', X)` resolves to `phase1.X` whether the warehouse is DuckDB or BigQuery.

That identical contract is what lets one set of source declarations and one set of downstream SQL
serve both targets:

- **dev** — `load_rawdata.py` reads the CSVs via DuckDB's `read_csv_auto()` into `phase1` inside
  `dev.duckdb`.
- **prod** — `load_bigquery.py` uploads them via BigQuery load jobs with an **explicit per-table
  schema** (no autodetect, so column types stay deterministic) into the `phase1` dataset.

`bin_definitions` — the Phase 1 WOE/IV dictionary (bin bounds, WOE, IV contribution per feature) —
is loaded alongside them in dev for inspection but is **not a declared source**: the monitoring
models read the already-binned WOE values carried in `model_features`, so nothing in the dbt layer
consumes the dictionary directly.

---

## PSI — Population Stability

This section reports the score- and feature-level PSI computed by the dbt pipeline. Every number
below has been reproduced end-to-end through the marts and verified against either a design-note
target or an independent hand-computation. Numbers not independently verified are not stated.

### Approach

PSI is computed as the symmetric KL (Jeffreys) divergence:

> PSI(a, e) = Σ_bin (a − e) · ln(a / e) = KL(a‖e) + KL(e‖a)

Every per-bin term is ≥ 0, identical distributions score exactly 0, and divergence cannot cancel
across bins. Baseline-vs-itself = 0 is the built-in sanity check (every term `(e − e) · ln(e / e)`
is zero by construction).

### Period spine

Each row is assigned exactly one period:

- `P0` — reference cohort (earliest `days_decision` bucket); serves as the PSI baseline
- `P1`–`P5` — recency cohorts derived from `days_decision`
- `M` — sentinel cohort, operationally `days_decision = 299`; kept separate from `P0`–`P5`

### Alert tiers

Per-period PSI is tagged using two thresholds, set via the `psi_moderate` (`0.1`) and `psi_high`
(`0.2`) dbt vars and applied in the `psi_from_counts` macro:

- `baseline` — the `P0` row (drift is undefined against the reference)
- `stable` — PSI < 0.1
- `moderate` — 0.1 ≤ PSI < 0.2
- `high` — PSI ≥ 0.2

### Empty-bin armor

The `psi_from_counts` macro includes a dense grid plus an epsilon floor
(`greatest(share, 0.0001)`) inside the macro itself. A bin that empties out in some period
becomes a 0-count cell rather than a missing row, and the floor keeps the logarithm finite. So a
vanished category produces a large, finite PSI spike instead of either an error or a silent
omission. The armor is a verified no-op on the current (dense) data, and verified to activate on
a synthetic gap — see *Robustness notes* below.

### Score-level results

Score is binned into deciles cut on `P0`, so `P0` is uniform 0.10 across deciles by construction.
Each period's decile distribution is compared to `P0`:

| Period | PSI    | Tier     |
|--------|--------|----------|
| P0     | 0.000  | baseline |
| P1     | 0.001  | stable   |
| P2     | 0.001  | stable   |
| P3     | 0.001  | stable   |
| P4     | 0.004  | stable   |
| P5     | 0.025  | stable   |
| M      | 0.077  | stable   |

**Reading.** The score distribution is stable across all recency cohorts — no period breaches
PSI 0.1 — with a mild, monotonic drift in the most-recent periods (`P4` → `P5`) that tracks the
underlying base-rate decline (0.089 → 0.073 across the period spine). The sentinel cohort `M`
carries the largest PSI (0.077) but is still well below the stable threshold. Operationally, `M`
is the `days_decision = 299` block and is not blended into the recency spine. Most of `M`'s PSI
sits in decile 0 (0.174 vs 0.10 → ≈ 0.041 of the 0.077), with the rest spread across the top
deciles as they thin out — mass has moved out of the higher-score deciles into the lowest.

### Feature-level results

Feature PSI is computed per-WOE-bin: the Phase 1 binning defines the bins, and the WOE level
itself is the bin. 12 features × 7 periods.

**Recency cohorts (`P1`–`P5`) are stable across the board.** Across every feature and every real
recency period, the maximum PSI observed is **0.047**, and the count of non-stable readings in
`P1`–`P5` is **zero**.

**Sentinel cohort `M` shows moderate drift on the demographic features.** Two features trip the
moderate tier at `M`:

| Feature             | M PSI | Tier     |
|---------------------|-------|----------|
| NAME_EDUCATION_TYPE | 0.152 | moderate |
| NAME_INCOME_TYPE    | 0.109 | moderate |

No feature reaches `high` at any period.

**Reading.** Feature distributions are stable across recency cohorts; the only notable
feature-level drift is in the sentinel cohort, concentrated in demographic features (education,
income). This is consistent with `M` being an operational-flag block rather than a recency
bucket — its composition is structurally different from the time-ordered cohorts.

### Robustness notes

- **Density verified.** Score deciles (10 × 7 = 70 cells) and feature WOE bins are both fully
  populated across every period in this sample (confirmed via anti-join on the dense grid). The
  empty-bin armor is therefore a no-op on this dataset.
- **Armor retained for production robustness.** The failure mode on sparse production data
  *without* the armor is *silent understatement*: the inner join drops the missing-bin term and
  PSI under-reports drift without raising any signal. The armor turns that silent failure into a
  loud `high` alert. It lives inside `psi_from_counts`, so any future caller inherits it.
- **Stress test included.** The repo ships `stress_psi_gap` (a tiny synthetic fixture with a
  deliberately removed bin) and `mart_psi_gap_stress` (the same `psi_from_counts` macro wrapped
  on the fixture). Running it reproduces PSI ≈ **0.702 → `high`** on the gapped period, while the
  un-armored equivalent would silently return ≈ 0.012 → `stable`. The fixture is permanent.

> **Scope.** PSI tells you the population shifted; it does not say the model still discriminates
> well. Discrimination is the Gini layer, below.

---

## Gini — Discrimination

### Pooled and per-period

The dbt rank-sum Gini reproduces the Phase 1 sklearn Gini to eight significant figures
(**0.36619854**). Because the WOE-binned score is heavily tied, this relies on midrank
tie-handling (`ROW_NUMBER` + `AVG`), which reproduces AUC's 0.5-per-tie convention; plain `RANK`
would understate it.

| Period | Gini  |
|--------|-------|
| P0     | 0.374 |
| P1     | 0.368 |
| P2     | 0.390 |
| P3     | 0.350 |
| P4     | 0.351 |
| P5     | 0.339 |
| M      | 0.376 |

**Reading.** Discrimination is stable across the period cohorts — the per-period mean 
over P0–P5 (≈ 0.362) sits in line with the pooled 0.366, with the sentinel M (0.376) held out. 
No monotonic trend (P2 highest, P5 lowest, the rest mid-pack); the spread is scatter, 
not decay — a directional claim either way would need a bootstrap or DeLong CI, 
which this pipeline does not yet compute.

### Pillar (grouped) Gini

Each feature group gets a *sub-score* — `Σ (coefficient × WOE)` over the features in that
pillar — and the rank-sum Gini is computed on it, isolating each group's standalone
discriminatory power.

| pillar         | features | gini  |
|----------------|---------:|------:|
| employment     |        4 | 0.231 |
| bureau_credit  |        4 | 0.226 |
| demographic    |        2 | 0.221 |
| financial      |        1 | 0.136 |
| region         |        1 | 0.098 |

All five sit below the full-model Gini (0.366), as expected — each uses only a subset of the
features. The multi-feature pillars cluster at the top; `demographic` keeps pace with them on
the strength of age (`DAYS_BIRTH`) alone, so pillar Gini tracks discriminatory power, not feature
count.

**Non-additivity (read directionally).** Sub-scores are additive on the logit scale, but their
Ginis are not — the five sum to ~0.91, far above the model's 0.366, because the pillars carry
correlated signal. Pillar Gini is a *directional* attribution tool: when overall discrimination
shifts, the pillar that moves with it is the likely driver. It is never an exact decomposition of
the headline Gini.

**Ties.** A 1–4 feature WOE sum takes few distinct values, so the sub-scores are heavily tied;
the Gini uses midrank handling, the same convention as the pooled score. The rank-sum logic is
shared with the per-period Gini via the `gini_rank_sum` macro, parameterized on the score column
and the partition.

## Testing

The dbt project ships a test suite, not just models — data tests on invariants, plus a unit test on transformation logic. Tests target things that can actually break and are placed where they bite: uniqueness/grain tests sit only at joins that can fan out rows, while grains fixed by a GROUP BY or an x/sum(x) normalization are left untested by design — such a test would be tautological, and the schema.yml description says so rather than silently omitting it.

Coverage is stated honestly. The score-PSI and feature-PSI lineages are covered: grain at the load and at the group-label join, null guards on values and period assignment, PSI non-negativity, and the alert-tier vocabulary. The Gini lineage is covered too: range guards on mart_gini_by_period, mart_gini_by_pillar, and mart_gini_pooled, a null guard on mart_gini_by_period, and a referential test that every scored feature carries a coefficient. The per-test reasoning — why each guard is non-tautological, which silent failure it catches — lives in the model descriptions, where it renders in dbt docs next to the column it defends.

One unit test backs the rank-sum macro. The pooled sklearn reproduction (eight significant figures, above) pins the math, but it cannot tell whether the macro ranks within each period or pools across them — and a range check cannot either. The unit test verifies that per-partition ranking directly, against a hand-verified fixture: the one correctness facet neither the reproduction nor the range guards reach.

---

## Continuous integration

Three GitHub Actions workflows cover the pull request lifecycle.

- **`ci.yml`** — on every pull request. Builds and tests the models that differ from production, into a dataset scoped to that PR.
- **`deploy.yml`** — on merge to `main`. Full build against the production dataset, then uploads the run's `manifest.json` as a workflow artifact. That artifact is the baseline the next PR compares against.
- **`ci-cleanup.yml`** — on PR close. Drops the PR's dataset. No checkout and no dbt — it authenticates and issues a single `bq rm`, which is why it finishes in about thirty seconds. It triggers on `closed` rather than `merged`, so an abandoned PR is cleaned up as thoroughly as a merged one.

### Narrowing the build

`ci.yml` selects `state:modified+` against the production manifest: only nodes that differ from prod, plus everything downstream. Production and CI write to different datasets — `dbt_credit_scoring` and a per-PR `dbt_ci_pr_N` — and that difference does not register as a modification. A pull request touching no dbt files selects nothing and builds nothing.

What this saves is narrower than it looks. Every model here is a view (see §5), and creating a view scans no data and bills nothing. The saving is in the tests, which do issue scanning queries. Narrowing the build narrows the test set; it does not avoid model-creation cost, because there wasn't any.

### Cost

A full build — every model, every test — billed about 1.7 GiB across 48 jobs. Four caveats belong with that number. It is a single observation, not an average. It is bytes *billed*, which is what BigQuery charges for and not the same as bytes scanned. The `maximum_bytes_billed` cap on the CI and prod targets is per query, so it bounds any single job at 2 GiB but places no ceiling on a build as a whole. And it describes a full build only — the cost of a narrowed build is unmeasured.

### Failing loudly

If the manifest fetch fails, the workflow falls back to building everything rather than proceeding with an empty comparison. The distinction matters: a missing baseline and a baseline showing no changes both produce an empty selection, and only the second means the PR is safe to skip. The fallback is conditioned on the fetch step's outcome, so the two stay distinguishable.

The artifact is kept for ninety days, and the clock restarts with each deploy. If the project goes three months without a merge to `main`, the artifact expires, retrieval fails, and every subsequent pull request quietly reverts to full builds — passing, green, and more expensive than it looks. That is the fallback working as designed, but nothing in the interface announces it.

---

## Production Notes

### Incremental PSI

In production this pipeline would use an incremental materialization strategy:

- Period 0 reference table frozen after initial model rollout — never rebuilt
- New monthly period appended to the PSI table each month
- Incremental key: `period`, deduplicated on `(period, bin_number)`
- Roughly 2 months of backward refresh to handle late-arriving data

This portfolio implementation uses full table refresh since the dataset is static. The
incremental design is documented here to reflect production intent.

### DuckDB concurrency

DuckDB allows only one read-write connection at a time. When inspecting materialized models via
notebook, always open the connection read-only:

```python
conn = duckdb.connect('dbt_project/dev.duckdb', read_only=True)
```

Running `dbt run` while a read-write notebook connection is open will throw a lock error.

---

## Reference

### DAG structure

```
Sources → staging
  scored_applications   → stg_scored_applications
  model_features        → stg_model_features
  model_coefficients    → stg_model_coefficients

Shared
  stg_scored_applications → int_period_assignment        # period tags; reused below

PSI — score drift
  stg_scored_applications + int_period_assignment
    → int_score_with_deciles → int_score_decile_counts → mart_psi_score

PSI — feature drift
  stg_model_features + int_period_assignment
    → int_features_with_periods → int_features_with_bins → mart_psi_features
                                                          (also ← stg_model_features)

Gini — by period
  stg_scored_applications + int_period_assignment
    → int_score_with_periods → mart_gini_by_period

Gini — pooled (single-pool benchmark)
  stg_scored_applications → int_score_pooled → mart_gini_pooled

Gini — by pillar
  stg_model_coefficients + stg_model_features + stg_scored_applications
    → int_subscore_by_pillar → mart_gini_by_pillar
  int_subscore_by_pillar + int_score_with_periods
    → int_subscore_by_pillar_with_periods → mart_gini_by_pillar_with_periods
```

### PSI interpretation thresholds

| PSI Value | Interpretation |
|---|---|
| < 0.10 | No significant shift |
| 0.10 – 0.20 | Moderate shift, investigate |
| > 0.20 | Significant shift, action required |

*These thresholds assume decile binning. Different bin counts require recalibration.*

### Limitations

- Time periods are synthetic — derived from `DAYS_DECISION` (recency of last Home Credit
  application), not actual calendar months or model deployment dates.
- 5.3% of applicants with no previous Home Credit application have no `DAYS_DECISION` and are
  assigned the sentinel value (`m_sentinel` = 299) for period assignment, forming the `M` cohort
  kept separate from the recency periods.
- `bureau_balance` (external monthly DPD history) showed low IV against Home Credit defaults in
  this dataset — external delinquency is a weaker predictor of internal default than
  point-in-time bureau aggregates.
- No strategy change logs available to contextualise PSI spikes.
- Static dataset — incremental logic documented but not implemented.
- `application_test.csv` provides a genuinely unseen population (~48k rows) for PSI monitoring of
  features and scores. Because the test set carries no `TARGET`, Gini cannot be computed there —
  only distributional stability. This mirrors real production monitoring, where drift metrics are
  available immediately but performance metrics require outcome maturation. A train → test PSI
  comparison is a natural next step.
