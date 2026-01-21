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
