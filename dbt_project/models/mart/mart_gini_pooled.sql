{{ config(materialized='view') }}

{{ gini_rank_sum(
    relation = ref('int_score_pooled'),
    score_col =  'score',
    label_col =  'is_default',
    partition_by =  'pool') }}