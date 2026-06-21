with psi as (
  {{ psi_from_counts(
       relation   = ref('int_features_with_bins'),
       series_key = 'feature_name',
       bin_col    = 'feature_value',
       count_col  = 'cnt'
  ) }}
),
feature_groups as (
  select distinct feature_name, feature_group
  from {{ ref('stg_model_features') }}
)
select
  p.series as feature_name,
  g.feature_group,
  p.period,
  p.psi_value,
  p.alert_tier
from psi p
left join feature_groups g on g.feature_name = p.series