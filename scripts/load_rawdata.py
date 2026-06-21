import duckdb
from pathlib import Path

repo_root =  Path(__file__).resolve().parent.parent
dbpath = Path(repo_root,'dbt_project')
data_path = Path(repo_root,'data/processed')

conn = duckdb.connect(dbpath/'dev.duckdb')


conn.execute("""
CREATE SCHEMA IF NOT EXISTS phase1             
""")


conn.execute(f"""
CREATE OR REPLACE TABLE phase1.scored_applications AS
SELECT *
FROM read_csv_auto('{data_path}/scored_applications.csv')""")


conn.execute(f"""
CREATE OR REPLACE TABLE phase1.bin_definitions AS
SELECT *
FROM read_csv_auto('{data_path}/bin_definitions.csv')""")


conn.execute(f"""
CREATE OR REPLACE TABLE phase1.model_features AS
SELECT *
FROM read_csv_auto('{data_path}/model_features.csv')""")


conn.execute(f"""
CREATE OR REPLACE TABLE phase1.model_coefficients AS
SELECT *
FROM read_csv_auto('{data_path}/model_coefficients.csv')""")


conn.close()