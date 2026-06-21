select period 
,feature_name
,feature_value
,count(1) cnt
from {{ ref('int_features_with_periods') }}
group by 1,2,3