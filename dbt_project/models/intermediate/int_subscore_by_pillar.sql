with subscore as (
    select
        feat.sk_id_curr,
        feat.feature_group as pillar,
        round(sum(feat.feature_value * c.coef), 10) as subscore
    from {{ ref('stg_model_features') }} feat
    left join {{ ref('stg_model_coefficients') }} c  on c.feature_name = feat.feature_name
    group by 1, 2
)
select
    s.sk_id_curr,
    s.pillar,
    s.subscore,
    sc.is_default
from subscore s
left join {{ ref('stg_scored_applications') }} sc on sc.sk_id_curr = s.sk_id_curr