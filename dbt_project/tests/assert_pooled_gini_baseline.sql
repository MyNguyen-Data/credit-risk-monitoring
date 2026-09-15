-- Pins the pooled Gini to the value validated against sklearn's roc_auc_score
-- in Phase 1 (agreement to eight significant figures). This test runs on
-- whichever target is active, so on prod it is the cross-engine check: the
-- DuckDB-developed SQL must land on the same number in BigQuery.
--
-- Tolerance rather than equality because rank-based metrics absorb
-- float-summation order differences across engines. No DuckDB-to-BigQuery
-- difference is detectable here: both targets render this value identically to
-- the seventeen significant digits BigQuery exposes, and no adjacent double
-- rounds into that rendering. Exact bit-level agreement is not claimed --
-- decimal text cannot establish it, because BigQuery's FORMAT caps at roughly
-- seventeen significant digits and pads beyond that. The 1e-9 is therefore
-- headroom against a future change in tie-handling or summation order, not
-- absorption of an observed wobble. It is a separate and tighter budget than
-- the sklearn agreement above, which at eight significant figures permits a
-- gap several times wider than this tolerance allows.
--
-- Driven from an expected set and left joined: an empty mart_gini_pooled
-- yields a null and fails, rather than producing no rows and passing.
--
-- The negated comparison rather than a direct `>` is deliberate: a NaN gini
-- compares false against every threshold, so `> 1e-9` would return no row and
-- pass green. Negating catches it.
--
-- The expected literal is left uncast: DuckDB parses it as DECIMAL, BigQuery
-- as FLOAT64. Both promote to double in the subtraction against gini, and
-- DECIMAL holds this value exactly, so the comparison is double-to-double on
-- either engine. No portable type name spans both dialects, so stating the
-- reasoning beats casting.
--
-- Deliberate skip: the join is `on true` with no grain test behind it.
-- mart_gini_pooled returns one row by construction (aggregate with no group
-- by), but that is the model's shape rather than an enforced constraint -- if
-- a second row ever appeared, both would have to match for this to pass.

with expected as 
(
    select 0.36619854813983066 as expected_gini
)
select e.expected_gini, a.gini
from expected e
left join {{ ref('mart_gini_pooled') }} a on true
where a.gini is null
   or not (abs(a.gini - e.expected_gini) <= 1e-9)
