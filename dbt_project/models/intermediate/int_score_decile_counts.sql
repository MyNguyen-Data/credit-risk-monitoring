select 'score' as series
,period
,score_decile
,count(1) cnt
from {{ ref('int_score_with_deciles') }}
group by 1,2,3