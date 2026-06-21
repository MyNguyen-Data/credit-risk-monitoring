select
    pi.*,            -- sk_id_curr, pillar, subscore, is_default
    per.period
from {{ ref('int_subscore_by_pillar') }} pi
left join {{ ref('int_score_with_periods') }} per on pi.sk_id_curr = per.sk_id_curr