{% macro psi_from_counts(relation, series_key, bin_col, count_col) %}

with  base as (
  select
    {{ series_key }} as series,
    period,
    {{ bin_col }}    as bin,
    {{ count_col }}  as cnt
  from {{ relation }}
)

,dense as (
  select sb.series, sb.bin, p.period, coalesce(b.cnt, 0) as cnt
  from (select distinct series, bin from base) sb
  cross join (select distinct period from base) p
  left join base b
    on b.series = sb.series and b.bin = sb.bin and b.period = p.period
)

,shares as (
    select
        series,
        period,
        bin,
        greatest(cnt / sum(cnt) over (partition by series, period), {{ var('psi_epsilon') }}) as pct 
        ---returns float in both with BigQuery errors while division by zero while DuckDb returns nan.

    from dense
)

,baseline as (
    select series, bin, pct as expected_pct
    from shares
    where period = 'P0'
)

,psi as (select
    s.series,
    s.period,
    sum( (s.pct - b.expected_pct) * ln(s.pct / b.expected_pct) ) as psi_value
from shares s
join baseline b
    on s.series = b.series and s.bin = b.bin
group by s.series, s.period
)

select *
,case when period = 'P0' then 'baseline'
    when psi_value  < {{ var('psi_moderate') }} then 'stable'
    when psi_value  < {{ var('psi_high') }} then 'moderate'
    else 'high' end as alert_tier
from psi

{% endmacro %}
