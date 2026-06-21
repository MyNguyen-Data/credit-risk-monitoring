{% macro gini_rank_sum(relation, score_col, label_col, partition_by) %}

{#- accept either a single column name or a list, so one-partition callers stay terse -#}
{%- if partition_by is string -%}
    {%- set parts = [partition_by] -%}
{%- else -%}
    {%- set parts = partition_by -%}
{%- endif -%}

{%- set part_cols = parts | join(', ') -%}
{%- set key_cols = [score_col] + parts -%}

with mid_rank as (
    select
        {{ score_col }},
        {{ part_cols }},
        avg(rn) as mid_rank
    from (
        select
            {{ part_cols }},
            {{ score_col }},
            row_number() over (
                partition by {{ part_cols }}
                order by {{ score_col }}
            ) as rn         
        from {{ relation }}
    )
    group by {{ score_col }}, {{ part_cols }}
),

mapp as (
    select
        base.*,
        mr.mid_rank
    from {{ relation }} base
    left join mid_rank mr   on {% for k in key_cols %}mr.{{ k }} = base.{{ k }}{% if not loop.last %} and {% endif %}
    {% endfor %}
),

agg as (
    select
        {{ part_cols }},
        sum(case when {{ label_col }} = 1 then mid_rank else 0 end) as r_pos,
        count(case when {{ label_col }} = 1 then 1 end)             as n_pos,
        count(case when {{ label_col }} = 0 then 1 end)             as n_neg
    from mapp
    group by {{ part_cols }}
)

select
    {{ part_cols }},
    2 * (r_pos - n_pos * (n_pos + 1) / 2) / nullif(n_pos * n_neg, 0) - 1 as gini
from agg

{% endmacro %}