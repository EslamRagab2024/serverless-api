resource "aws_cognito_user_pool" "main" {
  name                     = "${local.name_prefix}-users"
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  generate_secret = false # public SPA client

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH", # handy for testing with the AWS CLI
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Hosted UI (authorization code flow)
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid", "email"]
  supported_identity_providers         = ["COGNITO"]
  callback_urls                        = ["https://${aws_cloudfront_distribution.main.domain_name}/"]
  logout_urls                          = ["https://${aws_cloudfront_distribution.main.domain_name}/"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "${local.name_prefix}-${local.account_id}"
  user_pool_id = aws_cognito_user_pool.main.id
}
