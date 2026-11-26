resource "aws_dynamodb_table" "records" {
  name         = "${local.name_prefix}-records"
  billing_mode = "PAY_PER_REQUEST" # on-demand capacity
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "owner"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "N"
  }

  # GSI: list all records that belong to one user, newest first
  global_secondary_index {
    name            = "owner-index"
    hash_key        = "owner"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  # DynamoDB Streams -> triggers the stream-processor Lambda
  stream_enabled   = true
  stream_view_type = "NEW_AND_OLD_IMAGES"

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }
}
