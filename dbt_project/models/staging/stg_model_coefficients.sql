select feature_name
,coefficient as coef
from {{ source('raw', 'model_coefficients') }}
