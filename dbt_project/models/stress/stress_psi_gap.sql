-- models/stress/stress_psi_gap.sql
select 'demo' as series, 'P0' as period, 'A' as bin, 80 as cnt
union all select 'demo', 'P0', 'B', 10
union all select 'demo', 'P0', 'C', 10
union all select 'demo', 'P1', 'A', 90
union all select 'demo', 'P1', 'B', 10