-- Pins the two moderate PSI alerts on the M sentinel cohort
-- (NAME_EDUCATION_TYPE, NAME_INCOME_TYPE) to their validated values.
--
-- Tolerance rather than equality. PSI is a sum of (a-b)*ln(a/b) over bins, and
-- floating-point addition is not associative: the order in which partial sums
-- combine across threads is not fixed, so the same query over the same data
-- lands on adjacent doubles between runs. Measured September 2026 -- across
-- three DuckDB runs each of these two values took two distinct doubles, one
-- ULP apart. Measured agreement is well inside 1e-9 on both targets. Exact
-- bit-level agreement is deliberately not claimed, and is not available to be
-- claimed: neither engine reproduces its own result to the last bit. A second
-- and independent limit sits on top of that -- BigQuery's FORMAT caps at
-- roughly seventeen significant digits and pads beyond, so decimal text could
-- not resolve a final-bit difference even if one were stable enough to look
-- for. Literals are full precision so the pinned value is an observed value
-- rather than a rounded stand-in, not because the test discriminates at that
-- level -- fault injection confirms a perturbation below 1e-9 passes, as
-- intended.
--
-- Provenance: each literal is one of the two doubles DuckDB returns for that
-- value, and so sits one ULP from the other -- gaps of 2.8e-17
-- (NAME_EDUCATION_TYPE) and 1.4e-17 (NAME_INCOME_TYPE), eight orders inside
-- the tolerance. Which of the two a given run produces is not stable, so "the
-- value DuckDB returns" is not well defined for either.
--
-- Driven from an expected set and left joined: if the M cohort disappears
-- from the mart entirely, the join yields nulls and the test fails, rather
-- than returning no rows and passing.
--
-- The join cannot produce duplicates: mart_psi_features is held to one row
-- per feature_name per period by
-- dbt_utils_unique_combination_of_columns_mart_psi_features_feature_name__period.
--
-- The negated comparison rather than a direct `>` is deliberate: a NaN
-- psi_value compares false against every threshold, so `> 1e-9` would return
-- no row and pass green. Negating catches it.
--
-- Scope: this test checks two named features. A third feature crossing into
-- moderate on M is invisible here by design -- that is
-- assert_psi_features_baseline's job, via tier counts.
--
-- Expected literals are left uncast: DuckDB parses them as DECIMAL, BigQuery
-- as FLOAT64. Both promote to double in the subtraction against psi_value,
-- and DECIMAL holds these values exactly, so the comparison is double-to-double
-- on either engine. No portable type name spans both dialects, so stating the
-- reasoning beats casting.

with expected as
(
    select 'NAME_EDUCATION_TYPE' as feature_name, 0.15175449684993136  as expected_psi
    union all
    select 'NAME_INCOME_TYPE', 0.10896342483828056
)
select e.feature_name, e.expected_psi, a.psi_value
from expected e
left join {{ ref('mart_psi_features') }} a
       on a.feature_name = e.feature_name
      and a.period = 'M'
where a.psi_value is null
   or not (abs(a.psi_value - e.expected_psi) <= 1e-9)
