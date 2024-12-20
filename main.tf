# Create an AWS S3 bucket named "static-assets-bucket" with a "project_env" tag

resource "aws_s3_bucket" "static_assets" {
  bucket = "static-assets-bucket"
  tags = {
    project_env = "development"
  }
}

# Configure public access settings for the S3 bucket

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Define a policy allowing public read access to objects in the S3 bucket

resource "aws_s3_bucket_policy" "public_read_policy" {
  bucket = aws_s3_bucket.static_assets.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = "*",
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.static_assets.arn}/*" 
      }
    ]
  })
}

# Enable server-side encryption for the S3 bucket using AES256 algorithm

resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Enable versioning for the S3 bucket

resource "aws_s3_bucket_versioning" "versioning_config" {
  bucket = aws_s3_bucket.static_assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Upload the "index.html" file to the S3 bucket as the default file

resource "aws_s3_object" "upload_index" {
  depends_on = [
    aws_s3_bucket.static_assets
  ]
  bucket = aws_s3_bucket.static_assets.id
  key = "index.html"
  source = "./index.html"
  server_side_encryption = "AES256"
  content_type = "text/html"
}

# Define an origin access identity for CloudFront to access the S3 bucket securely

resource "aws_cloudfront_origin_access_identity" "cdn_access" {
  comment = "CloudFront Origin Access Identity for secure S3 access"
}


resource "aws_cloudfront_distribution" "cdn_distribution" {
  depends_on = [
    aws_s3_bucket.static_assets,
    aws_cloudfront_origin_access_identity.cdn_access
  ]
  enabled = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.static_assets.arn
    viewer_protocol_policy = "https-only"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  origin {
    domain_name = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id = aws_s3_bucket.static_assets.arn
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.cdn_access.cloudfront_access_identity_path
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "bucket_access_policy" {
  depends_on = [
    aws_cloudfront_distribution.cdn_distribution,
    aws_s3_bucket.static_assets
  ]

  statement {
    sid       = "RestrictAccess"
    effect    = "Allow"
    actions   = ["s3:GetObject"]

    principals {
      identifiers = ["*"]
      type        = "AWS"
    }

    resources = [
      aws_s3_bucket.static_assets.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:Referer"
      values   = [aws_cloudfront_distribution.cdn_distribution.arn]
    }
  }
}
