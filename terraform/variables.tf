variable "aws_region" {
  description = "Region for the regional resources (API Gateway, Lambda, DynamoDB, Cognito, S3)"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Prefix used to name all resources"
  type        = string
  default     = "records-api"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "enable_api_cache" {
  description = "Enable the API Gateway cache cluster (NOT free-tier eligible, billed hourly)"
  type        = bool
  default     = false
}

variable "waf_rate_limit" {
  description = "Max requests per 5 minutes per IP before WAF blocks"
  type        = number
  default     = 1000
}

variable "blocked_countries" {
  description = "ISO 3166-1 alpha-2 country codes to block at the edge (empty = no geo blocking)"
  type        = list(string)
  default     = []
}

variable "alarm_email" {
  description = "Email address subscribed to the alarm SNS topic (empty = no subscription)"
  type        = string
  default     = ""
}
