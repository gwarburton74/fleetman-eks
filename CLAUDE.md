# AI Assistant Rules — fleetman-eks

## Context
This repo was built with heavy use of AI coding assistants (Claude, GitHub Copilot) for
Terraform, Kubernetes manifests, and CI/CD pipeline authoring. This file documents rules
added after catching AI-generated mistakes, so future sessions don't repeat them.

## Rules

### 1. Always verify security group requirements for Helm-deployed webhooks
When AI generates Terraform for a Helm chart that includes an admission webhook (e.g.,
Vault Agent Injector), it will often provision the chart correctly but miss the underlying
network path the webhook needs to function — in this case, an inbound rule on the EKS node
security group allowing traffic on port 8080 from the cluster security group.

**What went wrong:** The Vault Agent Injector webhook was deployed successfully via Helm,
but pod injection silently failed because the EKS control plane couldn't reach the webhook
on the node security group. This wasn't caught until testing secret injection on a live pod.

**Rule:** Any time a Helm chart introduces a mutating/validating webhook, explicitly check
for and codify the required security group rule in Terraform (see
`aws_security_group_rule.vault_webhook` in `terraform/eks.tf`) rather than relying on the
Helm chart or AI-generated IaC to have inferred it. Never leave this as a manual
post-deploy step.