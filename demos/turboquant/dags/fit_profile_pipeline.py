"""Nightly customer fit-profile pipeline.

Schedule: 03:00 UTC daily, after the return-events partition lands in S3.

Tasks
-----
wait_for_partition      S3KeySensor — blocks until today's return events are ready
spark_submit_pipeline   DatabricksSubmitRunOperator — runs pipeline.py at scale
update_lookup_table     PythonOperator — promotes staged profiles to the live path
"""
from __future__ import annotations

from datetime import datetime, timedelta

import boto3
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.amazon.aws.sensors.s3 import S3KeySensor
from airflow.providers.databricks.operators.databricks import DatabricksSubmitRunOperator

BUCKET = "turboquant-data"

_DEFAULT_ARGS = {
    "owner": "size-fit",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "email_on_failure": True,
    "email": ["size-fit-oncall@zalando.de"],
}

with DAG(
    dag_id="turboquant_fit_profile_pipeline",
    description="BERT extraction → PySpark aggregation → lookup table swap",
    schedule_interval="0 3 * * *",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    default_args=_DEFAULT_ARGS,
    tags=["size-fit", "turboquant", "ml"],
) as dag:

    wait_for_partition = S3KeySensor(
        task_id="wait_for_partition",
        bucket_name=BUCKET,
        bucket_key="returns/date={{ ds }}/_SUCCESS",
        aws_conn_id="aws_default",
        timeout=60 * 60 * 4,   # upstream has up to 4 hours to land
        poke_interval=60 * 5,  # check every 5 minutes
        mode="reschedule",     # release the worker slot between pokes
    )

    spark_submit_pipeline = DatabricksSubmitRunOperator(
        task_id="spark_submit_pipeline",
        databricks_conn_id="databricks_default",
        existing_cluster_id="{{ var.value.tq_cluster_id }}",
        spark_python_task={
            "python_file": "dbfs:/turboquant/pipeline.py",
            "parameters": [
                "--input",  f"s3://{BUCKET}/returns/date={{{{ ds }}}}/",
                "--output", f"s3://{BUCKET}/profiles/staged/{{{{ ds }}}}/",
            ],
        },
    )

    def _swap_lookup_table(ds: str) -> None:
        """Copy staged profiles to the live prefix, then delete the staged copy."""
        s3 = boto3.client("s3")
        staged_prefix = f"profiles/staged/{ds}/"
        live_prefix = "profiles/live/"

        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=BUCKET, Prefix=staged_prefix):
            for obj in page.get("Contents", []):
                src_key = obj["Key"]
                dst_key = live_prefix + src_key.removeprefix(staged_prefix)
                s3.copy_object(
                    Bucket=BUCKET,
                    CopySource={"Bucket": BUCKET, "Key": src_key},
                    Key=dst_key,
                )
                s3.delete_object(Bucket=BUCKET, Key=src_key)

    update_lookup_table = PythonOperator(
        task_id="update_lookup_table",
        python_callable=_swap_lookup_table,
        op_kwargs={"ds": "{{ ds }}"},
    )

    wait_for_partition >> spark_submit_pipeline >> update_lookup_table
