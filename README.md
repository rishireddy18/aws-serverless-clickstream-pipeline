
# Assignment 1 – AWS Data Pipeline

## Overview
This project provisions an end-to-end AWS data pipeline using Terraform and AWS services.  
The pipeline ingests JSON events, stores them in an S3 data lake, transforms them with Lambda, catalogs them in Glue, and makes them queryable in Athena with a curated Parquet layer.

## Architecture
- **Terraform** for infrastructure as code  
- **Kinesis Firehose** for ingestion into S3 raw bucket  
- **Lambda** for transformation into processed bucket  
- **S3 Buckets**
  - `assign1-raw-x5bfjv` – raw data
  - `assign1-processed-x5bfjv` – processed data
  - `assign1-athena-x5bfjv` – Athena query results
- **Glue Data Catalog** – database `assign1_db_x5bfjv`
- **Athena** – SQL queries, views, curated Parquet table

## Deliverables
- Terraform code (`terraform/`) for provisioning all resources  
- Lambda function (`lambda/`) for JSON transformation  
- Athena bootstrap SQL (`athena/assignment1_athena_bootstrap.sql`)  
- Screenshots (`screenshots/`) showing ingestion, storage, and queries  
- Documentation (`README.md`) with architecture and usage details

## Validation
1. Events are ingested through Firehose and appear in the raw S3 bucket.  
2. Lambda processes the events and outputs to the processed S3 bucket.  
3. Glue crawlers and Athena views make the data queryable.  
4. Curated Parquet tables in Athena support optimized analytics queries.  

## Evidence
Screenshots include:
- Firehose ingestion with RecordId  
- S3 raw bucket with ingested files  
- S3 processed bucket with transformed files  
- Athena queries on processed events and curated daily table

## creating an external table
CREATE EXTERNAL TABLE IF NOT EXISTS assign1_db_x5bfjv.events (
    user   STRING,
    ts     TIMESTAMP,
    page   STRING,
    debug  BOOLEAN
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 's3://assign1-processed-x5bfjv/'
TBLPROPERTIES ('parquet.compression'='SNAPPY');

## previewing latest data
SELECT *
FROM assign1_db_x5bfjv.events
WHERE dt = CAST(current_date AS VARCHAR)
LIMIT 10;

## daily page hits
SELECT dt,
       page,
       COUNT(*) AS hits
FROM assign1_db_x5bfjv.events
WHERE dt BETWEEN '2025-09-20' AND '2025-09-22'
GROUP BY dt, page
ORDER BY dt, hits DESC;

## unique users per day
SELECT dt,
       COUNT(DISTINCT user) AS unique_users
FROM assign1_db_x5bfjv.events
GROUP BY dt
ORDER BY dt;
=======
# AWS Serverless Clickstream Pipeline

This project implements a fully serverless data engineering pipeline on AWS to ingest, transform, catalog, and analyze high-volume clickstream events. The solution uses managed AWS services and Infrastructure as Code (Terraform) to create a scalable and cost-efficient analytics pipeline.

## Architecture

![Architecture](diagrams/architecture.png)

## Data Flow

1. Clickstream events (JSON) are ingested using Amazon Kinesis Data Firehose.
2. Firehose delivers raw events into an S3 bucket partitioned by date (year/month/day).
3. An AWS Lambda function is triggered to transform raw JSON into optimized Parquet format.
4. Transformed data is written to a curated S3 bucket with partitioned layout.
5. AWS Glue Crawler catalogs the processed data into the Glue Data Catalog.
6. Amazon Athena is used to query the final dataset for analytics.

## Technologies Used

- Amazon Kinesis Data Firehose
- Amazon S3
- AWS Lambda
- AWS Glue (Crawler + Data Catalog)
- Amazon Athena
- Terraform (Infrastructure as Code)
- Python

## Repository Structure

```text
aws-serverless-clickstream-pipeline/
├── terraform/        # Terraform IaC
├── lambda/           # Lambda transformation code
├── diagrams/         # Architecture diagram
├── sql/              # Athena queries
├── sample-data/      # Sample clickstream events
├── screenshots/      # Validation screenshots
├── README.md

