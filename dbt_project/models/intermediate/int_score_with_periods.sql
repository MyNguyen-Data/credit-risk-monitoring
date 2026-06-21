select app.sk_id_curr
,app.is_default
,app.score
,per.period
from {{ ref('stg_scored_applications') }} app
left join {{ ref('int_period_assignment') }} per on per.sk_id_curr = app.sk_id_curr
