data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------- CRUD function role (least privilege) ----------
resource "aws_iam_role" "crud" {
  name               = "${local.name_prefix}-crud-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "crud" {
  statement {
    sid = "TableAccess"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [
      aws_dynamodb_table.records.arn,
      "${aws_dynamodb_table.records.arn}/index/owner-index",
    ]
  }
}

resource "aws_iam_role_policy" "crud" {
  name   = "dynamodb-access"
  role   = aws_iam_role.crud.id
  policy = data.aws_iam_policy_document.crud.json
}

resource "aws_iam_role_policy_attachment" "crud_logs" {
  role       = aws_iam_role.crud.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "crud_xray" {
  role       = aws_iam_role.crud.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# ---------- Stream processor role ----------
resource "aws_iam_role" "stream" {
  name               = "${local.name_prefix}-stream-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "stream" {
  statement {
    sid = "ReadStream"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
      "dynamodb:ListStreams",
    ]
    resources = [aws_dynamodb_table.records.stream_arn]
  }
}

resource "aws_iam_role_policy" "stream" {
  name   = "stream-read"
  role   = aws_iam_role.stream.id
  policy = data.aws_iam_policy_document.stream.json
}

resource "aws_iam_role_policy_attachment" "stream_logs" {
  role       = aws_iam_role.stream.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
