resource "aws_api_gateway_rest_api" "api" {
  name = "${local.name_prefix}-api"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Cognito JWT authorizer
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.api.id
  type            = "COGNITO_USER_POOLS"
  provider_arns   = [aws_cognito_user_pool.main.arn]
  identity_source = "method.request.header.Authorization"
}

# /api  ->  /api/records  ->  /api/records/{id}
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "records" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "records"
}

resource "aws_api_gateway_resource" "record" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.records.id
  path_part   = "{id}"
}

locals {
  api_methods = {
    list_records  = { resource_id = aws_api_gateway_resource.records.id, http_method = "GET" }
    create_record = { resource_id = aws_api_gateway_resource.records.id, http_method = "POST" }
    get_record    = { resource_id = aws_api_gateway_resource.record.id, http_method = "GET" }
    update_record = { resource_id = aws_api_gateway_resource.record.id, http_method = "PUT" }
    delete_record = { resource_id = aws_api_gateway_resource.record.id, http_method = "DELETE" }
  }
}

resource "aws_api_gateway_method" "this" {
  for_each = local.api_methods

  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = each.value.resource_id
  http_method   = each.value.http_method
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "this" {
  for_each = local.api_methods

  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = each.value.resource_id
  http_method             = aws_api_gateway_method.this[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.crud.invoke_arn
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  # Redeploy whenever the API definition changes
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.records.id,
      aws_api_gateway_resource.record.id,
      aws_api_gateway_method.this,
      aws_api_gateway_integration.this,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  deployment_id = aws_api_gateway_deployment.main.id
  stage_name    = var.environment

  xray_tracing_enabled = true

  # Response caching (optional - cache clusters are billed hourly)
  cache_cluster_enabled = var.enable_api_cache
  cache_cluster_size    = var.enable_api_cache ? "0.5" : null
}

resource "aws_api_gateway_method_settings" "all" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = aws_api_gateway_stage.main.stage_name
  method_path = "*/*"

  settings {
    metrics_enabled        = true
    caching_enabled        = var.enable_api_cache
    cache_ttl_in_seconds   = 60
    throttling_rate_limit  = 50
    throttling_burst_limit = 100
  }
}
