{{ config(materialized='view') }}

{{ gini_rank_sum(
    relation = ref('int_score_with_periods'),
    score_col =  'score',
    label_col =  'is_default',
    partition_by =  'period') }}