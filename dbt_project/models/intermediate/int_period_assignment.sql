with scored as 
(
    select sk_id_curr
    ,days_decision
    from {{ ref('stg_scored_applications') }}
)
, periods as (
    select
        sk_id_curr,
        days_decision,
        ntile({{ var('n_periods') }}) over (
            order by days_decision, sk_id_curr   
        ) as period_idx
    from scored
    where days_decision <> {{ var('m_sentinel') }}
)
, m_cohort as (
    select sk_id_curr, days_decision
    from scored
    where days_decision = {{ var('m_sentinel') }}
)

select sk_id_curr, days_decision
-- , 'P' || (period_idx - 1) as period
,'P' || cast(period_idx - 1 as string) as period
from periods
union all
select sk_id_curr, days_decision, 'M' as period
from m_cohort