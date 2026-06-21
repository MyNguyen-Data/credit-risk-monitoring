with {% if target.type == 'bigquery' %}
edges as 
    (select [p10, p20, p30, p40, p50, p60, p70, p80, p90] as e
    from (
        select
            percentile_cont(app.score, 0.1) over () as p10,
            percentile_cont(app.score, 0.2) over () as p20,
            percentile_cont(app.score, 0.3) over () as p30,
            percentile_cont(app.score, 0.4) over () as p40,
            percentile_cont(app.score, 0.5) over () as p50,
            percentile_cont(app.score, 0.6) over () as p60,
            percentile_cont(app.score, 0.7) over () as p70,
            percentile_cont(app.score, 0.8) over () as p80,
            percentile_cont(app.score, 0.9) over () as p90
        from {{ ref('stg_scored_applications') }} app
        join {{ ref('int_period_assignment') }} per using (sk_id_curr)
        where per.period = 'P0'
        )
        limit 1
    )
{% else %}    
edges as (
    select quantile_cont(score, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]) as e
    from {{ ref('stg_scored_applications') }} app
    join {{ ref('int_period_assignment') }} per using (sk_id_curr)
    where per.period = 'P0'
)
{% endif %}
, scored as (
    select app.sk_id_curr, per.period, app.score
    from {{ ref('stg_scored_applications') }} app
    left join {{ ref('int_period_assignment') }} per on app.sk_id_curr = per.sk_id_curr
)
select
    s.sk_id_curr,
    s.period,
    s.score,
    {% if target.type == 'bigquery' %}
    (select count(*) from unnest(edges.e) as x where s.score >= x)
    {% else %}
    len(list_filter(edges.e, x -> s.score >= x))
    {% endif %} as score_decile
from scored s
cross join edges
