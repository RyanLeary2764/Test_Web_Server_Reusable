variable "github_repository" {
  description = "GitHub OWNER/REPO for preview deployment; empty disables the OIDC role."
  type        = string
  default     = ""
  validation {
    condition     = var.github_repository == "" || can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use OWNER/REPO or an empty string."
  }
}
variable "github_oidc_provider_arn" {
  description = "Existing account GitHub OIDC provider ARN; empty creates one if github_repository is set."
  type        = string
  default     = ""
}
resource "aws_iam_openid_connect_provider" "github" {
  count          = var.github_repository != "" && var.github_oidc_provider_arn == "" ? 1 : 0
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
locals {
  github_oidc_arn = var.github_oidc_provider_arn != "" ? var.github_oidc_provider_arn : try(aws_iam_openid_connect_provider.github[0].arn, "")
}
resource "aws_iam_role" "github_deploy" {
  count       = var.github_repository != "" ? 1 : 0
  name_prefix = "${var.project_name}-github-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_oidc_arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:preview"
        }
      }
    }]
  })
}
resource "aws_iam_role_policy" "github_deploy" {
  count = var.github_repository != "" ? 1 : 0
  role  = aws_iam_role.github_deploy[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
      Resource = aws_security_group.preview.arn
    }]
  })
}
output "github_deploy_role_arn" {
  value = try(aws_iam_role.github_deploy[0].arn, null)
}
output "preview_security_group_id" {
  value = aws_security_group.preview.id
}
output "preview_host" {
  value = aws_instance.preview.public_ip
}
