output "cloudfront_url" {
  description = "Public entry point (frontend + /api/*)"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "api_invoke_url" {
  description = "Direct API Gateway URL (requires a Cognito token)"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "cognito_hosted_ui_domain" {
  value = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "dynamodb_table" {
  value = aws_dynamodb_table.records.name
}
