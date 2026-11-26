resource "aws_s3_bucket" "frontend" {
  bucket        = "${local.name_prefix}-frontend-${local.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Only CloudFront (via Origin Access Control) may read the bucket
data "aws_iam_policy_document" "frontend" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend.json

  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.frontend.id
  key          = "index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Records App</title></head>
    <body>
      <h1>Records App</h1>
      <p>Static page served from S3 through CloudFront.</p>
      <p>The REST API is available under <code>/api/records</code> and requires a Cognito token.</p>
    </body>
    </html>
  HTML
}
