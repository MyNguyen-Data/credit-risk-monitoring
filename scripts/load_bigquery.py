from google.cloud import bigquery
from pathlib import Path
import os

PROJECT = os.environ.get("GCP_PROJECT")
if not PROJECT:
    raise SystemExit("Set GCP_PROJECT to your BigQuery project id (e.g. export GCP_PROJECT=my-project)")
DATASET = "phase1"
LOCATION = "asia-southeast1"

repo_root = Path(__file__).resolve().parent.parent
data_path = repo_root / "data" / "processed"

client = bigquery.Client(project=PROJECT)

# schemas pinned from `bq show --schema` — types AND order must match the CSV
SCHEMAS = {
    "scored_applications": [
        bigquery.SchemaField("SK_ID_CURR", "INTEGER"),
        bigquery.SchemaField("TARGET", "INTEGER"),
        bigquery.SchemaField("score", "FLOAT"),
        bigquery.SchemaField("DAYS_DECISION", "FLOAT"),
    ],
    "model_features": [
        bigquery.SchemaField("SK_ID_CURR", "INTEGER"),
        bigquery.SchemaField("feature_name", "STRING"),
        bigquery.SchemaField("feature_value", "FLOAT"),
        bigquery.SchemaField("feature_group", "STRING"),
    ],
    "model_coefficients": [
        bigquery.SchemaField("feature_name", "STRING"),
        bigquery.SchemaField("coefficient", "FLOAT"),
    ],
}

for name, schema in SCHEMAS.items():
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        schema=schema,
    )
    table_id = f"{PROJECT}.{DATASET}.{name}"
    with open(data_path / f"{name}.csv", "rb") as f:
        client.load_table_from_file(f, table_id, job_config=job_config, location=LOCATION).result()
    print(f"loaded {table_id}")

client.close()