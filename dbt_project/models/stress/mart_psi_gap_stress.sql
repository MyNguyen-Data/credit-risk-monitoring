-- models/stress/mart_psi_gap_stress.sql
{{ psi_from_counts(ref('stress_psi_gap'), series_key='series', bin_col='bin', count_col='cnt') }}