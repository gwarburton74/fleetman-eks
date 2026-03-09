# OIDC Provider for GitHub Actions

# Look up existing GitHub OIDC provider instead of creating a new one
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# IAM Role that GitHub Actions will assume
resource "aws_iam_role" "github_actions" {
  name = "github-actions-fleetman-eks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_username}/${var.github_repo}:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name    = "github-actions-fleetman-eks"
    Project = "fleetman-eks"
  }
}

# Attach AdministratorAccess for the sandbox
# (in production you'd scope this down significantly)
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}