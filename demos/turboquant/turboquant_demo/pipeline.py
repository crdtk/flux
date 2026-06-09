"""Offline feature pipeline: batch BERT inference over customer return history.

Reads return events (customer_id, return_text) from Parquet, runs
extract_fit_signal via pandas_udf (model loads once per partition),
aggregates a fit profile per customer, and writes the lookup table
that serves the 95% fast path at 2 ms.

Run locally:
    python -m turboquant_demo.pipeline --generate   # generate sample data + build profiles
    python -m turboquant_demo.pipeline              # build profiles from data/returns.parquet

Run on Databricks / spark-submit:
    spark-submit turboquant_demo/pipeline.py \\
        --input  s3://bucket/returns/ \\
        --output s3://bucket/profiles/
"""
from __future__ import annotations

import argparse

import pandas as pd
from pyspark.sql import SparkSession
from pyspark.sql.functions import avg, col, collect_list, count, pandas_udf, struct
from pyspark.sql.types import ArrayType, DoubleType, StringType, StructField, StructType

from turboquant_demo.bert import extract_fit_signal

# _get_clf() in bert.py is a module-level lazy singleton.
# PySpark initialises each partition in a separate worker process;
# the model loads once per process, not once per row.
_SIGNAL_SCHEMA = StructType([
    StructField("direction",  StringType(),         nullable=False),
    StructField("confidence", DoubleType(),          nullable=False),
    StructField("regions",    ArrayType(StringType()), nullable=False),
    StructField("latency_ms", DoubleType(),          nullable=False),
])


@pandas_udf(_SIGNAL_SCHEMA)
def _encode(texts: pd.Series) -> pd.DataFrame:
    return pd.DataFrame([extract_fit_signal(t) for t in texts])


def build_profiles(input_path: str, output_path: str) -> None:
    spark = (
        SparkSession.builder
        .appName("turboquant-feature-pipeline")
        .config("spark.sql.execution.arrow.pyspark.enabled", "true")
        .getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    profiles = (
        spark.read.parquet(input_path)
        .withColumn("signal", _encode(col("return_text")))
        .select(
            "customer_id",
            col("signal.direction").alias("direction"),
            col("signal.confidence").alias("confidence"),
            col("signal.regions").alias("regions"),
        )
        .groupBy("customer_id")
        .agg(
            collect_list(struct("direction", "confidence", "regions")).alias("signals"),
            count("*").alias("n_returns"),
            avg("confidence").alias("avg_confidence"),
        )
    )

    profiles.write.mode("overwrite").parquet(output_path)
    print(f"Profiles written: {profiles.count()} customers → {output_path}")
    spark.stop()


def generate_sample_data(path: str, n_customers: int = 200, n_returns: int = 1_000) -> None:
    """Write synthetic return events to Parquet for local testing."""
    import random
    random.seed(42)

    _TEXTS = [
        "too tight in the thighs but waist was fine",
        "runs very large, should have ordered a size down",
        "tight across the shoulders, everything else was okay",
        "perfect fit, definitely keeping these",
        "the chest was a bit snug but the length was great",
        "waist fits but too long in the legs",
        "extremely loose overall, not my style",
        "fits my waist but I can't button it after lunch",
        "bought both M and L — the M looks better but L is more comfortable",
        "first time buying this brand, not sure about European sizing",
    ]

    spark = SparkSession.builder.appName("turboquant-sample-gen").getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    rows = [
        {"customer_id": f"c{random.randint(1, n_customers):04d}", "return_text": random.choice(_TEXTS)}
        for _ in range(n_returns)
    ]
    spark.createDataFrame(rows).write.mode("overwrite").parquet(path)
    spark.stop()
    print(f"Sample data written: {n_returns} returns → {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="TurboQuant offline feature pipeline")
    parser.add_argument("--input",    default="data/returns.parquet")
    parser.add_argument("--output",   default="data/profiles.parquet")
    parser.add_argument("--generate", action="store_true",
                        help="generate sample data before running")
    args = parser.parse_args()

    if args.generate:
        generate_sample_data(args.input)
    build_profiles(args.input, args.output)
