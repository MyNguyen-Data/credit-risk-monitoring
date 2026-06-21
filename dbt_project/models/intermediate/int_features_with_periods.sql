select fea.sk_id_curr
,feature_name
,feature_group
,feature_value
,period
from {{ ref('stg_model_features') }} fea 
left join {{ ref('int_period_assignment') }} per on per.sk_id_curr = fea.sk_id_curr
