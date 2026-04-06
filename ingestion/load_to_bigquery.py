"""
ingestion/load_to_bigquery.py
Carrega CSVs do Cloud Storage para o BigQuery com particionamento e clustering.
Registra execução na tabela de auditoria.
"""

import os
import uuid
import logging
from datetime import datetime, timezone
from pathlib import Path

from google.cloud import bigquery, storage
from google.cloud.exceptions import NotFound

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s"
)
logger = logging.getLogger("load_to_bigquery")

PROJECT_ID = os.environ.get("GCP_PROJECT_ID", "paybridge-data-challenge")
BUCKET_NAME = os.environ.get("GCS_BUCKET", f"{PROJECT_ID}-raw-zone")
RAW_DATASET = "raw"
AUDIT_DATASET = "audit"
KEY_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "./infra/keys/dbt-sa-key.json")

# Configurações de cada tabela: schema, particionamento, clustering
TABLE_CONFIGS = {
    "transactions": {
        "gcs_path": "raw/transactions/transactions.csv",
        "schema": [
            bigquery.SchemaField("transaction_id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("merchant_id", "STRING"),
            bigquery.SchemaField("customer_id", "STRING"),
            bigquery.SchemaField("amount_brl", "NUMERIC"),
            bigquery.SchemaField("mdr_rate_pct", "NUMERIC"),
            bigquery.SchemaField("mdr_amount_brl", "NUMERIC"),
            bigquery.SchemaField("net_amount_brl", "NUMERIC"),
            bigquery.SchemaField("payment_method", "STRING"),
            bigquery.SchemaField("status", "STRING"),
            bigquery.SchemaField("transaction_date", "DATE"),
            bigquery.SchemaField("transaction_ts", "TIMESTAMP"),
            bigquery.SchemaField("installments", "INTEGER"),
            bigquery.SchemaField("authorization_code", "STRING"),
            bigquery.SchemaField("acquirer", "STRING"),
        ],
        "partition_field": "transaction_date",
        "cluster_fields": ["merchant_id", "payment_method", "status"],
    },
    "customers": {
        "gcs_path": "raw/customers/customers.csv",
        "schema": [
            bigquery.SchemaField("customer_id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("company_name", "STRING"),
            bigquery.SchemaField("cnpj", "STRING"),
            bigquery.SchemaField("customer_segment", "STRING"),
            bigquery.SchemaField("credit_rating", "STRING"),
            bigquery.SchemaField("monthly_revenue_brl", "NUMERIC"),
            bigquery.SchemaField("registration_date", "DATE"),
            bigquery.SchemaField("city", "STRING"),
            bigquery.SchemaField("state", "STRING"),
            bigquery.SchemaField("is_active", "BOOLEAN"),
            bigquery.SchemaField("account_manager_id", "STRING"),
        ],
        "partition_field": None,
        "cluster_fields": ["customer_segment", "state"],
    },
    "merchants": {
        "gcs_path": "raw/merchants/merchants.csv",
        "schema": [
            bigquery.SchemaField("merchant_id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("merchant_name", "STRING"),
            bigquery.SchemaField("merchant_segment", "STRING"),
            bigquery.SchemaField("mdr_credit", "NUMERIC"),
            bigquery.SchemaField("mdr_debit", "NUMERIC"),
            bigquery.SchemaField("mdr_pix", "NUMERIC"),
            bigquery.SchemaField("activated_at", "DATE"),
            bigquery.SchemaField("is_active", "BOOLEAN"),
            bigquery.SchemaField("customer_id", "STRING"),
        ],
        "partition_field": None,
        "cluster_fields": ["merchant_segment"],
    },
    "credit_contracts": {
        "gcs_path": "raw/credit_contracts/credit_contracts.csv",
        "schema": [
            bigquery.SchemaField("contract_id", "STRING", mode="REQUIRED"),
            bigquery.SchemaField("customer_id", "STRING"),
            bigquery.SchemaField("product_type", "STRING"),
            bigquery.SchemaField("principal_brl", "NUMERIC"),
            bigquery.SchemaField("outstanding_balance_brl", "NUMERIC"),
            bigquery.SchemaField("monthly_rate_pct", "NUMERIC"),
            bigquery.SchemaField("term_months", "INTEGER"),
            bigquery.SchemaField("contract_date", "DATE"),
            bigquery.SchemaField("maturity_date", "DATE"),
            bigquery.SchemaField("days_past_due", "INTEGER"),
            bigquery.SchemaField("risk_classification_bacen", "STRING"),
            bigquery.SchemaField("is_npl", "BOOLEAN"),
            bigquery.SchemaField("is_written_off", "BOOLEAN"),
            bigquery.SchemaField("collateral_type", "STRING"),
            bigquery.SchemaField("collateral_value_brl", "NUMERIC"),
        ],
        "partition_field": "contract_date",
        "cluster_fields": ["risk_classification_bacen", "product_type"],
    },
    "daily_rates": {
        "gcs_path": "raw/daily_rates/daily_rates.csv",
        "schema": [
            bigquery.SchemaField("rate_date", "DATE", mode="REQUIRED"),
            bigquery.SchemaField("cdi_annual_pct", "NUMERIC"),
            bigquery.SchemaField("selic_annual_pct", "NUMERIC"),
            bigquery.SchemaField("usd_brl", "NUMERIC"),
            bigquery.SchemaField("eur_brl", "NUMERIC"),
            bigquery.SchemaField("is_business_day", "BOOLEAN"),
        ],
        "partition_field": None,
        "cluster_fields": [],
    },
}


def log_audit(client: bigquery.Client, run_id: str, step: str, status: str,
              rows: int = 0, error: str = None):
    table_id = f"{PROJECT_ID}.{AUDIT_DATASET}.pipeline_runs"
    rows_to_insert = [{
        "run_id": run_id,
        "pipeline_name": "ingestion_load_to_bigquery",
        "step": step,
        "status": status,
        "rows_processed": rows,
        "rows_failed": 0,
        "started_at": datetime.now(timezone.utc).isoformat(),
        "finished_at": datetime.now(timezone.utc).isoformat(),
        "error_message": error,
        "triggered_by": os.environ.get("TRIGGERED_BY", "manual"),
        "git_commit_sha": os.environ.get("GIT_SHA", "local"),
    }]
    errors = client.insert_rows_json(table_id, rows_to_insert)
    if errors:
        logger.warning(f"Falha ao registrar auditoria: {errors}")


def load_table(client: bigquery.Client, table_name: str, config: dict,
               run_id: str) -> int:
    gcs_uri = f"gs://{BUCKET_NAME}/{config['gcs_path']}"
    table_id = f"{PROJECT_ID}.{RAW_DATASET}.{table_name}"

    logger.info(f"Carregando {table_name} de {gcs_uri}...")

    job_config = bigquery.LoadJobConfig(
        schema=config["schema"],
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
        create_disposition=bigquery.CreateDisposition.CREATE_IF_NEEDED,
    )

    if config.get("partition_field"):
        job_config.time_partitioning = bigquery.TimePartitioning(
            type_=bigquery.TimePartitioningType.DAY,
            field=config["partition_field"],
            expiration_ms=None,
        )

    if config.get("cluster_fields"):
        job_config.clustering_fields = config["cluster_fields"]

    try:
        load_job = client.load_table_from_uri(gcs_uri, table_id, job_config=job_config)
        load_job.result()

        table = client.get_table(table_id)
        rows = table.num_rows
        logger.info(f"  OK: {table_name} — {rows:,} linhas")
        log_audit(client, run_id, f"load_{table_name}", "success", rows)
        return rows

    except Exception as e:
        logger.error(f"  ERRO ao carregar {table_name}: {e}")
        log_audit(client, run_id, f"load_{table_name}", "failed", error=str(e))
        raise


def upload_to_gcs(local_dir: str = "./data/raw"):
    """Faz upload dos CSVs locais para o Cloud Storage antes da carga no BQ."""
    storage_client = storage.Client(project=PROJECT_ID)
    bucket = storage_client.bucket(BUCKET_NAME)

    local_path = Path(local_dir)
    if not local_path.exists():
        logger.warning(f"Diretório {local_dir} não encontrado. Certifique-se de rodar extract_postgres.py primeiro.")
        return

    for csv_file in local_path.glob("*.csv"):
        table_name = csv_file.stem
        if table_name not in TABLE_CONFIGS:
            continue
        gcs_path = TABLE_CONFIGS[table_name]["gcs_path"]
        blob = bucket.blob(gcs_path)
        blob.upload_from_filename(str(csv_file))
        logger.info(f"  Upload: {csv_file.name} → gs://{BUCKET_NAME}/{gcs_path}")


def main():
    logger.info("=== PayBridge: Load to BigQuery ===")
    run_id = str(uuid.uuid4())
    logger.info(f"Run ID: {run_id}")

    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = KEY_PATH
    client = bigquery.Client(project=PROJECT_ID)

    # Upload local CSVs para GCS
    logger.info("Fazendo upload dos CSVs para Cloud Storage...")
    upload_to_gcs()

    # Carregar cada tabela no BigQuery
    total_rows = 0
    failed_tables = []

    for table_name, config in TABLE_CONFIGS.items():
        try:
            rows = load_table(client, table_name, config, run_id)
            total_rows += rows
        except Exception as e:
            failed_tables.append(table_name)
            logger.error(f"Falha em {table_name}: {e}")

    # Resumo
    logger.info("")
    logger.info("=== Resumo de Carga ===")
    logger.info(f"  Total de linhas carregadas: {total_rows:,}")
    logger.info(f"  Tabelas com falha: {failed_tables or 'nenhuma'}")
    logger.info(f"  Próximo passo: cd dbt_project && dbt run")

    if failed_tables:
        raise SystemExit(f"Carga falhou para: {', '.join(failed_tables)}")


if __name__ == "__main__":
    main()
