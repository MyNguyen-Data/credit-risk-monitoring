select gini
from {{ ref('mart_gini_pooled') }}
where abs(gini - 0.36619854813983066) > 1e-9