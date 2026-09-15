-- Pins the shape of mart_psi_features: row counts per alert_tier, and the sum
-- of psi_value within each tier.
--
-- The counts are not three independent facts. They total 84, which is twelve
-- features times seven periods, so the assertion is first a grain check and
-- only second a severity split. It deliberately overlaps
-- dbt_utils_unique_combination_of_columns_mart_psi_features_feature_name__period,
-- which already forbids duplicates at that grain. What this adds is the
-- absolute count: uniqueness catches a fan-out but not a feature that vanishes
-- from stg_model_features or a period that never materialises. The overlap is
-- recorded rather than removed because the two failures read differently in a
-- log.
--
-- The fan-out worth naming is in the mart itself: feature_groups is a SELECT
-- DISTINCT over the (feature_name, feature_group) pair, not over feature_name
-- alone, so a feature carrying two groups would left join to two rows and push
-- the total above 84.
--
-- The baseline row sums to exactly zero, and exactly is meant literally. That
-- tier is the baseline period compared against itself, so every term is
-- (p-p)*ln(p/p), which is zero before any rounding occurs, on any engine. It
-- catches a mis-join against the wrong period, which returns something
-- non-zero. It does not catch a pipeline collapsed to empty, null, or all
-- zeros, which also sums to zero -- the n = 12 assertion on the same row
-- carries that, and neither half is redundant.
--
-- Tolerance rather than equality on the moderate and stable sums.
-- assert_m_cohort_psi_baseline gives the mechanism for single PSI values; it
-- applies again here at the outer sum across rows, and more strongly.
-- Floating-point addition is not associative and both engines combine partial
-- sums across threads in no fixed order. The effect is not cross-engine, it is
-- run-to-run: three consecutive DuckDB runs over identical data returned three
-- distinct values for the stable sum and two for the moderate sum, adjacent
-- pairs one ULP apart, with BigQuery stable within a batch and different
-- across batches. Measured September 2026. An equality assertion here would
-- fail intermittently with no code change, which is worse than no test.
--
-- Bit-level agreement between engines is therefore not merely unclaimed but
-- unavailable, since neither engine agrees with itself on these sums.
-- Digit-for-digit comparison of the two targets' rendered output establishes
-- nothing here and does not need repeating. The formatter caveat compounds it
-- independently: DuckDB's printf emits the exact decimal expansion while
-- BigQuery's FORMAT caps near seventeen significant digits and pads, and its
-- final digit has been observed off by two units.
--
-- Provenance: literals are taken from DuckDB, at shortest round-trip
-- precision, from the middle of the observed run-to-run spread. BigQuery
-- readings are deliberately not used as the source, since its trailing digits
-- are known to be unreliable. At 1e-9 the choice within the spread is
-- immaterial; it is stated so the next reader does not assume the literal is
-- canonical.
--
-- Driven from an expected set and full outer joined. A tier disappearing from
-- the mart yields nulls on the actual side and fails, rather than returning no
-- rows and passing green; a tier appearing that is not in the expected set
-- fails on the other side. Both branches are exercised by renaming a tier in
-- the expected set, which returns two rows.
--
-- The negated comparison rather than a direct `>` is deliberate: a NaN sum
-- compares false against every threshold, so `> 1e-9` would return no row and
-- pass. Negating catches it.
--
-- Expected literals are left uncast, on the same reasoning as
-- assert_m_cohort_psi_baseline.

with expected as (

    select 'baseline' as alert_tier, 12 as n, 0.0                as psi_sum, 0.0  as tol
    union all
    select 'moderate',               2,       0.2607179216882119,            1e-9
    union all
    select 'stable',                 70,      0.7238728820937371,            1e-9

),

actual as (

    select
        alert_tier,
        count(*)        as n,
        sum(psi_value)  as psi_sum
    from {{ ref('mart_psi_features') }}
    group by alert_tier

)

select
    coalesce(e.alert_tier, a.alert_tier) as alert_tier,
    e.n       as expected_n,
    a.n       as actual_n,
    e.psi_sum as expected_psi_sum,
    a.psi_sum as actual_psi_sum
from expected e
full outer join actual a
    on a.alert_tier = e.alert_tier
where
    a.alert_tier is null
    or e.alert_tier is null
    or a.n <> e.n
    or not abs(a.psi_sum - e.psi_sum) <= e.tol
