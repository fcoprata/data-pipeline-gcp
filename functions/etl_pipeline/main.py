"""ETL Pipeline - Cloud Function para processamento de transacoes financeiras."""

import io
import logging
import re
from datetime import UTC, datetime

import flask
import functions_framework
import pandas as pd
from google.cloud import storage

PROJECT_ID = "iron-crane-411118"
BUCKET_NAME = "iron-crane-411118-data-pipeline"
RAW_PREFIX = "raw/"
PROCESSED_PREFIX = "processed/"

log = logging.getLogger(__name__)


def _read_csv(bucket: storage.Bucket, blob_name: str) -> pd.DataFrame:
    blob = bucket.blob(blob_name)
    content = blob.download_as_text()
    return pd.read_csv(io.StringIO(content))


def _normalize_customer_id(cid: object) -> str | None:
    """Remove zeros a esquerda do customer_id: C01 -> C1."""
    if pd.isna(cid):
        return None
    match = re.match(r"^C0*(\d+)$", str(cid).strip())
    return f"C{match.group(1)}" if match else str(cid).strip()


def extract(
    bucket: storage.Bucket,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    df_transactions = _read_csv(bucket, f"{RAW_PREFIX}transactions_file1.csv")
    df_details = _read_csv(bucket, f"{RAW_PREFIX}transactions_file2.csv")
    df_customers = _read_csv(bucket, f"{RAW_PREFIX}customers_file3.csv")
    return df_transactions, df_details, df_customers


def transform(
    df_transactions: pd.DataFrame,
    df_details: pd.DataFrame,
    df_customers: pd.DataFrame,
) -> pd.DataFrame:
    df = df_transactions.merge(df_details, on="transaction_id", how="inner")

    df["customer_id"] = df["customer_id"].apply(_normalize_customer_id)

    customers = df_customers.copy()
    customers["customer_id"] = customers["customer_id"].apply(
        _normalize_customer_id,
    )

    df = df.merge(customers, on="customer_id", how="left")
    df = df.drop_duplicates(subset=["transaction_id"], keep="first")

    df["transaction_date"] = pd.to_datetime(
        df["transaction_date"],
        errors="coerce",
    )
    df["transaction_amount"] = pd.to_numeric(
        df["transaction_amount"],
        errors="coerce",
    )
    df["qtty"] = pd.to_numeric(df["qtty"], errors="coerce")
    df["price"] = pd.to_numeric(df["price"], errors="coerce")

    required = [
        "transaction_id",
        "customer_id",
        "transaction_date",
        "transaction_amount",
        "transaction_status",
        "transaction_type",
        "qtty",
        "price",
    ]
    df = df.dropna(subset=required)

    df = df[df["transaction_status"].isin({"approved", "rejected", "pending"})]
    df = df[df["transaction_type"].isin({"buy", "sell"})]
    df = df[(df["qtty"] > 0) & (df["price"] > 0) & (df["transaction_amount"] > 0)]

    df = df.sort_values("transaction_date").reset_index(drop=True)

    df["transaction_date"] = df["transaction_date"].dt.date
    for col in ("transaction_amount", "qtty", "price"):
        df[col] = df[col].astype("float64")

    return df


def load_parquet(bucket: storage.Bucket, df: pd.DataFrame) -> str:
    timestamp = datetime.now(tz=UTC).strftime("%Y%m%d_%H%M%S")
    blob_path = f"{PROCESSED_PREFIX}transactions_{timestamp}.parquet"

    buf = io.BytesIO()
    df.to_parquet(buf, index=False, engine="pyarrow")
    buf.seek(0)

    blob = bucket.blob(blob_path)
    blob.upload_from_file(buf, content_type="application/octet-stream")
    return blob_path


@functions_framework.http
def etl_handler(request: flask.Request) -> tuple[dict, int]:  # noqa: ARG001
    try:
        client = storage.Client(project=PROJECT_ID)
        bucket = client.bucket(BUCKET_NAME)

        df_transactions, df_details, df_customers = extract(bucket)
        raw_count = len(df_transactions)

        df = transform(df_transactions, df_details, df_customers)
        clean_count = len(df)

        blob_path = load_parquet(bucket, df)

        return {
            "status": "success",
            "raw_records": raw_count,
            "clean_records": clean_count,
            "removed_records": raw_count - clean_count,
            "output_path": f"gs://{BUCKET_NAME}/{blob_path}",
            "columns": list(df.columns),
        }, 200

    except (ValueError, KeyError, storage.exceptions.GoogleCloudError) as e:
        log.exception("Pipeline failed")
        return {"status": "error", "message": str(e)}, 500
