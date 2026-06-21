select
    SK_ID_CURR as sk_id_curr,
    TARGET as is_default,
    score,
    days_decision as days_decision
from {{ source('raw', 'scored_applications') }}
where  TARGET is not null
  and SK_ID_CURR is not null
  and score is not null
  and days_decision is not null