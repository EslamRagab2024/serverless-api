# Lambda source code is embedded here so the project only needs .tf files.

locals {
  crud_code = <<-PY
    """CRUD handler for the records API (API Gateway REST proxy integration).

    Every record belongs to the authenticated Cognito user (the `sub` claim),
    so users can only read/modify their own data.
    """
    import json
    import os
    import time
    import uuid
    from decimal import Decimal

    import boto3
    from boto3.dynamodb.conditions import Key
    from botocore.exceptions import ClientError

    # Optional: end-to-end X-Ray tracing of DynamoDB calls.
    # Works when the aws-xray-sdk package is added (e.g. as a Lambda layer).
    try:
        from aws_xray_sdk.core import patch_all

        patch_all()
    except ImportError:
        pass

    TABLE = boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


    class _JSONEncoder(json.JSONEncoder):
        def default(self, o):
            if isinstance(o, Decimal):
                return int(o) if o % 1 == 0 else float(o)
            return super().default(o)


    def _response(status, body=None):
        return {
            "statusCode": status,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps(body if body is not None else {}, cls=_JSONEncoder),
        }


    def _parse_body(event):
        try:
            data = json.loads(event.get("body") or "{}")
        except json.JSONDecodeError:
            raise ValueError("Body must be valid JSON")
        if not isinstance(data, dict):
            raise ValueError("Body must be a JSON object")
        return data


    def create_record(owner, event):
        data = _parse_body(event)
        title = str(data.get("title", "")).strip()
        if not title:
            raise ValueError("'title' is required")

        item = {
            "id": str(uuid.uuid4()),
            "owner": owner,
            "title": title,
            "description": str(data.get("description", "")),
            "done": bool(data.get("done", False)),
            "created_at": int(time.time() * 1000),
        }
        TABLE.put_item(Item=item)
        return _response(201, item)


    def list_records(owner):
        result = TABLE.query(
            IndexName="owner-index",
            KeyConditionExpression=Key("owner").eq(owner),
            ScanIndexForward=False,  # newest first
        )
        return _response(200, {"items": result["Items"]})


    def get_record(owner, record_id):
        item = TABLE.get_item(Key={"id": record_id}).get("Item")
        if not item or item["owner"] != owner:
            return _response(404, {"message": "Record not found"})
        return _response(200, item)


    def update_record(owner, record_id, event):
        data = _parse_body(event)
        allowed = {k: data[k] for k in ("title", "description", "done") if k in data}
        if not allowed:
            raise ValueError("Provide at least one of: title, description, done")

        names = {f"#{k}": k for k in allowed}
        values = {f":{k}": v for k, v in allowed.items()}
        values[":owner"] = owner
        names["#owner"] = "owner"

        try:
            result = TABLE.update_item(
                Key={"id": record_id},
                UpdateExpression="SET " + ", ".join(f"#{k} = :{k}" for k in allowed),
                ConditionExpression="attribute_exists(id) AND #owner = :owner",
                ExpressionAttributeNames=names,
                ExpressionAttributeValues=values,
                ReturnValues="ALL_NEW",
            )
        except ClientError as err:
            if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return _response(404, {"message": "Record not found"})
            raise
        return _response(200, result["Attributes"])


    def delete_record(owner, record_id):
        try:
            TABLE.delete_item(
                Key={"id": record_id},
                ConditionExpression="attribute_exists(id) AND #owner = :owner",
                ExpressionAttributeNames={"#owner": "owner"},
                ExpressionAttributeValues={":owner": owner},
            )
        except ClientError as err:
            if err.response["Error"]["Code"] == "ConditionalCheckFailedException":
                return _response(404, {"message": "Record not found"})
            raise
        return _response(204)


    def lambda_handler(event, context):
        claims = (event.get("requestContext", {}).get("authorizer") or {}).get("claims") or {}
        owner = claims.get("sub")
        if not owner:
            return _response(401, {"message": "Unauthorized"})

        method = event.get("httpMethod")
        record_id = (event.get("pathParameters") or {}).get("id")

        try:
            if record_id is None:
                if method == "POST":
                    return create_record(owner, event)
                if method == "GET":
                    return list_records(owner)
            else:
                if method == "GET":
                    return get_record(owner, record_id)
                if method == "PUT":
                    return update_record(owner, record_id, event)
                if method == "DELETE":
                    return delete_record(owner, record_id)
            return _response(405, {"message": "Method not allowed"})
        except ValueError as err:
            return _response(400, {"message": str(err)})
        except ClientError as err:
            print(f"DynamoDB error: {err}")
            return _response(500, {"message": "Internal server error"})
  PY

  stream_code = <<-PY
    """Downstream processor triggered by DynamoDB Streams.

    Logs every change (INSERT / MODIFY / REMOVE). This is the extension point for
    real downstream work: audit trail, notifications, search indexing, etc.
    """
    import json


    def lambda_handler(event, context):
        for record in event.get("Records", []):
            change = {
                "event": record["eventName"],
                "keys": record["dynamodb"].get("Keys"),
                "new_image": record["dynamodb"].get("NewImage"),
                "old_image": record["dynamodb"].get("OldImage"),
            }
            print(json.dumps(change))

        return {"processed": len(event.get("Records", []))}
  PY
}

data "archive_file" "crud" {
  type        = "zip"
  output_path = "${path.module}/build/crud.zip"

  source {
    content  = local.crud_code
    filename = "handler.py"
  }
}

data "archive_file" "stream" {
  type        = "zip"
  output_path = "${path.module}/build/stream.zip"

  source {
    content  = local.stream_code
    filename = "handler.py"
  }
}

resource "aws_cloudwatch_log_group" "crud" {
  name              = "/aws/lambda/${local.name_prefix}-crud"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "stream" {
  name              = "/aws/lambda/${local.name_prefix}-stream"
  retention_in_days = 14
}

resource "aws_lambda_function" "crud" {
  function_name    = "${local.name_prefix}-crud"
  role             = aws_iam_role.crud.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.crud.output_path
  source_code_hash = data.archive_file.crud.output_base64sha256
  timeout          = 10
  memory_size      = 256

  tracing_config {
    mode = "Active" # X-Ray
  }

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.records.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.crud]
}

resource "aws_lambda_function" "stream" {
  function_name    = "${local.name_prefix}-stream"
  role             = aws_iam_role.stream.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.stream.output_path
  source_code_hash = data.archive_file.stream.output_base64sha256
  timeout          = 30
  memory_size      = 128

  depends_on = [aws_cloudwatch_log_group.stream]
}

# DynamoDB Streams -> stream processor
resource "aws_lambda_event_source_mapping" "stream" {
  event_source_arn  = aws_dynamodb_table.records.stream_arn
  function_name     = aws_lambda_function.stream.arn
  starting_position = "LATEST"
  batch_size        = 100
}

# Allow API Gateway to invoke the CRUD function
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crud.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}
