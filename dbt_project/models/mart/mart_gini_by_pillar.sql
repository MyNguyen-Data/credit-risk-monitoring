{{ config(materialized='view') }}

{{ gini_rank_sum(
    relation     = ref('int_subscore_by_pillar'),
    score_col    = 'subscore',
    label_col    = 'is_default',
    partition_by = 'pillar')
}}