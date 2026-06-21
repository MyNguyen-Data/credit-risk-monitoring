select
    SK_ID_CURR as sk_id_curr,
    feature_name,
    feature_group,
    feature_value,
    feature_value = 0 as is_missing_cohort
from {{ source('raw', 'model_features') }}
where SK_ID_CURR is not null
  and feature_name is not null
