select sk_id_curr, is_default, score, 1 as pool
from {{ ref('stg_scored_applications') }}