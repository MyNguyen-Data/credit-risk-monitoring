-- mart_psi_score.sql
{{ psi_from_counts(
    relation=ref('int_score_decile_counts'),
    series_key='series',
    bin_col='score_decile',
    count_col='cnt'
) }}

