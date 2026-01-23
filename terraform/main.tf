############################################
# PROVIDER & COMMON
############################################
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile != "" ? var.aws_profile : null
}

locals {
  tags = {
    Project = var.project
    Owner   = "rishi"
    Env     = "dev"
  }
}

############################################
# BUCKETS
############################################

# Unique suffix to avoid bucket name collisions
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

# Raw bucket (Firehose target)
resource "aws_s3_bucket" "raw" {
  bucket = "${var.project}-raw-${random_string.suffix.result}"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Processed bucket (Lambda output)
resource "aws_s3_bucket" "processed" {
  bucket = "${var.project}-processed-${random_string.suffix.result}"
  tags   = local.tags
}

resource "aws_s3_bucket_versioning" "processed" {
  bucket = aws_s3_bucket.processed.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "processed" {
  bucket                  = aws_s3_bucket.processed.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Athena results live in the processed bucket under a prefix
resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project}-athena-${random_string.suffix.result}"
  tags   = local.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

############################################
# FIREHOSE → RAW BUCKET
############################################

# Role for Firehose to write to S3 + CloudWatch
resource "aws_iam_role" "firehose_role" {
  name               = "${var.project}-firehose-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.firehose_trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "firehose_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "firehose_policy_doc" {
  statement {
    sid     = "S3Access"
    actions = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject"]
    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*"
    ]
  }

  statement {
    sid       = "CWLogs"
    actions   = ["logs:PutLogEvents"]
    resources = ["*"]
  }

  statement {
    sid       = "KMSOptional"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "firehose_policy" {
  name   = "${var.project}-firehose-policy-${random_string.suffix.result}"
  policy = data.aws_iam_policy_document.firehose_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "firehose_attach" {
  role       = aws_iam_role.firehose_role.name
  policy_arn = aws_iam_policy.firehose_policy.arn
}

# Firehose Delivery Stream
resource "aws_kinesis_firehose_delivery_stream" "clickstream" {
  name        = "${var.project}-firehose-${random_string.suffix.result}"
  destination = "extended_s3"
  tags        = local.tags

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose_role.arn
    bucket_arn         = aws_s3_bucket.raw.arn
    buffering_size     = 5
    buffering_interval = 60
    compression_format = "GZIP"

    # Partition by date using Firehose timestamp placeholders
    prefix              = "raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "firehose-errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
    # NOTE: no data_format_conversion_configuration block here
  }

  depends_on = [aws_iam_role_policy_attachment.firehose_attach]
}

############################################
# LAMBDA (Transforms JSON → Parquet) + NOTIFICATION
############################################

# Lambda Execution Role
resource "aws_iam_role" "lambda_role" {
  name               = "${var.project}-lambda-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_policy_doc" {
  statement {
    sid     = "S3RW"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*",
      aws_s3_bucket.processed.arn,
      "${aws_s3_bucket.processed.arn}/*"
    ]
  }

  statement {
    sid       = "CWLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project}-lambda-policy-${random_string.suffix.result}"
  policy = data.aws_iam_policy_document.lambda_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# Package Lambda (reads local file lambda/handler.py)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "transform" {
  function_name = "${var.project}-transform-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_role.arn
  filename      = data.archive_file.lambda_zip.output_path
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 512
 source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  environment {
    variables = {
      PROCESSED_BUCKET = aws_s3_bucket.processed.bucket
    }
  }
  tags = local.tags

  depends_on = [aws_iam_role_policy_attachment.lambda_attach]
}

# Allow S3 to invoke Lambda
resource "aws_lambda_permission" "from_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.transform.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw.arn
}

# S3 Notification: trigger Lambda on new objects under raw/
resource "aws_s3_bucket_notification" "raw_notif" {
  bucket = aws_s3_bucket.raw.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.transform.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
  }

  depends_on = [aws_lambda_permission.from_s3]
}

############################################
# GLUE CRAWLER + DATABASE
############################################

resource "aws_glue_catalog_database" "db" {
  name = "${var.project}_db_${random_string.suffix.result}"
}

# Role for Glue Crawler
resource "aws_iam_role" "glue_role" {
  name               = "${var.project}-glue-role-${random_string.suffix.result}"
  assume_role_policy = data.aws_iam_policy_document.glue_trust.json
  tags               = local.tags
}

data "aws_iam_policy_document" "glue_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "glue_policy_doc" {
  statement {
    sid     = "S3ReadProcessed"
    actions = ["s3:GetObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.processed.arn,
      "${aws_s3_bucket.processed.arn}/*"
    ]
  }

  statement {
    sid       = "GlueCatalog"
    actions   = ["glue:*"]
    resources = ["*"]
  }

  statement {
    sid       = "CWLogs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "glue_policy" {
  name   = "${var.project}-glue-policy-${random_string.suffix.result}"
  policy = data.aws_iam_policy_document.glue_policy_doc.json
}

resource "aws_iam_role_policy_attachment" "glue_attach" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_policy.arn
}

resource "aws_glue_crawler" "processed_crawler" {
  name          = "${var.project}-crawler-${random_string.suffix.result}"
  role          = aws_iam_role.glue_role.arn
  database_name = aws_glue_catalog_database.db.name

  s3_target {
    path = "s3://${aws_s3_bucket.processed.bucket}/processed/"
  }

  schedule   = "cron(0/30 * * * ? *)" # every 30 minutes (adjust as you like)
  tags       = local.tags
  depends_on = [aws_iam_role_policy_attachment.glue_attach]
}

############################################
# ATHENA WORKGROUP
############################################

resource "aws_athena_workgroup" "wg" {
  count = var.create_athena_workgroup ? 1 : 0

  name = "${var.project}_wg_${random_string.suffix.result}"
  configuration {
    enforce_workgroup_configuration = true
    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/${var.athena_results_prefix}"
    }
  }
  tags = local.tags
}

############################################
# OUTPUTS
############################################

output "raw_bucket" {
  value = aws_s3_bucket.raw.bucket
}

output "processed_bucket" {
  value = aws_s3_bucket.processed.bucket
}

output "athena_results_bucket" {
  value = aws_s3_bucket.athena_results.bucket
}

output "firehose_name" {
  value = aws_kinesis_firehose_delivery_stream.clickstream.name
}

output "glue_database" {
  value = aws_glue_catalog_database.db.name
}
output "athena_workgroup" {
  value = var.create_athena_workgroup ? aws_athena_workgroup.wg[0].name : "primary"
}