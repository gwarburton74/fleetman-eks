# Vault Integration Runbook — fleetman-eks
**Project:** github.com/gwarburton74/fleetman-eks  
**Region:** us-east-1 | **Cluster:** fleetman-eks  
**Objective:** Full Vault install → init → auth → KV-v2 → Agent Injector verification

---

## Before You Start

### Prerequisites

**vault-local alias** must be in your `~/.bashrc` — this routes local vault CLI commands to the cluster without overwriting your production `VAULT_ADDR`:

```bash
alias vault-local='VAULT_ADDR="http://127.0.0.1:8200" VAULT_TOKEN=$(cat ~/vault-init-keys.json | jq -r .root_token) vault'
```

If you just added it, reload your shell:
```bash
source ~/.bashrc
```

**Pre-destroy checklist** (for next teardown — skip on first run):
```bash
# Delete services first to let EKS clean up its ELBs before terraform destroy
kubectl delete svc --all -n default
# Wait 30 seconds, then run terraform destroy
```

---

## Phase 0: Spin Up the Cluster

```bash
cd ~/git/fleetman-eks/terraform
terraform apply
```

Wait for `Apply complete!` — EKS provisioning typically takes 12–18 minutes.

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --region us-east-1 \
  --name fleetman-eks

# Verify nodes are Ready
kubectl get nodes
```

Expected: 2 nodes in `Ready` state before proceeding.

---

## Phase 1: Create gp3 Storage Class

Vault's PVC will use this. Must exist before Helm install.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  encrypted: "true"
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
EOF
```

```bash
# Remove default annotation from gp2 if it exists
kubectl patch storageclass gp2 \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

kubectl get storageclass
```

Expected: `gp3` shows `(default)`.

---

## Phase 2: ~~Fix the Node Security Group for Vault Webhook~~  ✅ Codified in Terraform

> This step is no longer manual. `aws_security_group_rule.vault_webhook` in `eks.tf`
> automatically opens port 8080 from the cluster security group to the node security group
> on every `terraform apply`. No action required.

The EKS control plane can only reach nodes on specific webhook ports. The Vault Agent Injector runs on port **8080**, which is not allowed by default. You must add it manually (until this is codified in Terraform).

```bash
# Get the current VPC ID
VPC_ID=$(aws eks describe-cluster \
  --name fleetman-eks \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.vpcId' \
  --output text)

echo $VPC_ID

# Get the node security group ID
NODE_SG=$(aws ec2 describe-security-groups \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?contains(GroupName,`node`)].GroupId' \
  --output text)

echo $NODE_SG

# Get the cluster security group ID
CLUSTER_SG=$(aws eks describe-cluster \
  --name fleetman-eks \
  --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
  --output text)

echo $CLUSTER_SG

# Add the rule
aws ec2 authorize-security-group-ingress \
  --region us-east-1 \
  --group-id $NODE_SG \
  --protocol tcp \
  --port 8080 \
  --source-group $CLUSTER_SG
```

No output = success. Verify:

```bash
aws ec2 describe-security-groups \
  --region us-east-1 \
  --group-ids $NODE_SG \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`8080`]' \
  --output table
```

Expected: a rule showing port 8080 from the cluster security group.

---

## Phase 3: Install Vault via Helm

```bash
# Create namespace
kubectl create namespace vault

# Add HashiCorp repo (idempotent)
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install using existing values file
helm install vault hashicorp/vault \
  --namespace vault \
  --values ~/git/fleetman-eks/helm/vault-values.yaml \
  --wait --timeout 5m
```

**Verify the install:**

```bash
kubectl get pods -n vault
kubectl get svc -n vault
helm status vault -n vault
```

Expected:
- `vault-0` — `0/1 Running` (normal pre-init)
- `vault-agent-injector-*` — `1/1 Running`
- `helm status` shows `STATUS: deployed` and `REVISION: 1`

> ⚠️ If `helm status` shows `STATUS: failed`, do a full uninstall and reinstall — do not try to patch it:
> ```bash
> helm uninstall vault -n vault
> kubectl delete namespace vault
> # Wait for namespace to fully terminate, then repeat Phase 3
> ```

```bash
# Confirm the mutating webhook was registered
kubectl get mutatingwebhookconfigurations
```

Expected: `vault-agent-injector-cfg` in the list with AGE of a few seconds.

---

## Phase 4: Initialize and Unseal Vault

> ⚠️ New cluster = new init. Old unseal keys are gone. Save what's generated here.

```bash
# Init with 5 key shares, threshold of 3
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=5 \
  -key-threshold=3 \
  -format=json > ~/vault-init-keys.json

cat ~/vault-init-keys.json
```

> **Save `~/vault-init-keys.json` somewhere safe. This is the only time you'll see these.**

```bash
# Extract keys from the saved JSON and unseal
UNSEAL_KEY_1=$(cat ~/vault-init-keys.json | jq -r '.unseal_keys_b64[0]')
UNSEAL_KEY_2=$(cat ~/vault-init-keys.json | jq -r '.unseal_keys_b64[1]')
UNSEAL_KEY_3=$(cat ~/vault-init-keys.json | jq -r '.unseal_keys_b64[2]')
ROOT_TOKEN=$(cat ~/vault-init-keys.json | jq -r '.root_token')

kubectl exec -n vault vault-0 -- vault operator unseal $UNSEAL_KEY_1
kubectl exec -n vault vault-0 -- vault operator unseal $UNSEAL_KEY_2
kubectl exec -n vault vault-0 -- vault operator unseal $UNSEAL_KEY_3
```

```bash
# Verify sealed: false
kubectl exec -n vault vault-0 -- vault status
```

Expected: `Sealed: false`.

```bash
# Kill any existing port-forward on 8200 from a previous session
pkill -f "port-forward.*8200"

# Port-forward in background for local CLI access
kubectl port-forward -n vault vault-0 8200:8200 &
PF_PID=$!

# Login using vault-local alias
vault-local login $ROOT_TOKEN
```

> **Note:** All `vault-local` commands route to the port-forwarded local Vault. Your shell's `VAULT_ADDR` is never modified.

---

## Phase 5: Configure Kubernetes Auth Method

```bash
# Enable Kubernetes auth
vault-local auth enable kubernetes

# Get cluster info for Vault to verify JWTs
KUBE_HOST=$(kubectl config view --raw \
  --minify \
  --flatten \
  -o jsonpath='{.clusters[].cluster.server}')

# Write k8s auth config
vault-local write auth/kubernetes/config \
  kubernetes_host="$KUBE_HOST"
```

```bash
# Verify
vault-local read auth/kubernetes/config
```

---

## Phase 6: Enable KV-v2 and Create Policy + Role

### 6a — Enable KV-v2

```bash
vault-local secrets enable -path=fleetman kv-v2

# Write a test secret
vault-local kv put fleetman/config \
  db_url="postgresql://fleetman-db:5432/fleetman" \
  api_key="test-api-key-replace-me"

# Verify
vault-local kv get fleetman/config
```

### 6b — Create Fleetman Policy

```bash
vault-local policy write fleetman - <<'EOF'
path "fleetman/data/*" {
  capabilities = ["read", "list"]
}

path "fleetman/metadata/*" {
  capabilities = ["read", "list"]
}
EOF
```

### 6c — Create Kubernetes Role

```bash
vault-local write auth/kubernetes/role/fleetman \
  bound_service_account_names=fleetman-sa \
  bound_service_account_namespaces=default \
  policies=fleetman \
  ttl=1h

# Verify
vault-local read auth/kubernetes/role/fleetman
```

### 6d — Create Service Account

```bash
kubectl create serviceaccount fleetman-sa -n default
```

---

## Phase 7: Injection Verification

### 7a — Create the Test Deployment File

This file lives in the repo at `k8s/vault-test-deployment.yaml`. Create it if it doesn't exist:

```bash
cat <<'EOF' > ~/git/fleetman-eks/k8s/vault-test-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vault-inject-test
  namespace: default
  labels:
    app: vault-inject-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vault-inject-test
  template:
    metadata:
      labels:
        app: vault-inject-test
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "fleetman"
        vault.hashicorp.com/agent-inject-secret-config: "fleetman/data/config"
        vault.hashicorp.com/agent-inject-template-config: |
          {{- with secret "fleetman/data/config" -}}
          DB_URL={{ .Data.data.db_url }}
          API_KEY={{ .Data.data.api_key }}
          {{- end }}
    spec:
      serviceAccountName: fleetman-sa
      containers:
        - name: app
          image: alpine:latest
          command: ["sh", "-c", "while true; do sleep 30; done"]
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "100m"
              memory: "128Mi"
EOF
```

### 7b — Apply and Watch

```bash
kubectl apply -f ~/git/fleetman-eks/k8s/vault-test-deployment.yaml
kubectl get pods -l app=vault-inject-test -w
```

Expected: `2/2 Running` — the `2` means both the app container and the vault-agent sidecar are running. If you see `1/1`, see Troubleshooting below.

### 7c — Verify Secret Was Written

```bash
POD=$(kubectl get pod -l app=vault-inject-test -o jsonpath='{.items[0].metadata.name}')
kubectl exec $POD -c app -- cat /vault/secrets/config
```

Expected output:
```
DB_URL=postgresql://fleetman-db:5432/fleetman
API_KEY=test-api-key-replace-me
```

### 7d — Check Vault Agent Logs

```bash
kubectl logs $POD -c vault-agent
```

Look for: `successfully renewed` or `authenticated successfully`.

---

## Phase 8: Cleanup and Commit

```bash
# Remove test deployment
kubectl delete deployment vault-inject-test

# Kill the port-forward
kill $PF_PID

# Commit
cd ~/git/fleetman-eks
git add k8s/vault-test-deployment.yaml
git add -A
git commit -m "feat: complete Vault Agent Injector integration

- Install Vault via Helm with gp3 storage class
- Initialize and unseal Vault (production mode)
- Configure Kubernetes auth method with EKS OIDC
- Enable KV-v2 secrets engine at fleetman/ path
- Create fleetman policy and role bound to fleetman-sa
- Fix control plane to node security group rule for port 8080
- Verify sidecar injection and secret delivery end-to-end
- Add vault-test-deployment.yaml to k8s/

Closes Vault integration milestone."

git push origin main
```

---

## Troubleshooting

### Sidecar not injected (pod shows 1/1 instead of 2/2)

Work through these in order:

**1 — Check the injector pod is running**
```bash
kubectl get pods -n vault
```
Expected: `vault-agent-injector-*` at `1/1 Running`.

**2 — Check injector logs — use the pod name directly**
```bash
# Get the actual pod name first
kubectl get pods -n vault

# Then use it directly (label selector is unreliable)
kubectl logs -n vault <vault-agent-injector-pod-name> --since=5m
```

If logs are empty after a pod creation event, the API server is not calling the webhook at all — almost certainly the port 8080 security group rule is missing (go to step 3).

If logs show TLS errors or crash loops, do a full helm uninstall/reinstall (see below).

**3 — Verify the port 8080 security group rule exists**
```bash
VPC_ID=$(aws eks describe-cluster \
  --name fleetman-eks --region us-east-1 \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)

NODE_SG=$(aws ec2 describe-security-groups \
  --region us-east-1 \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'SecurityGroups[?contains(GroupName,`node`)].GroupId' \
  --output text)

aws ec2 describe-security-groups \
  --region us-east-1 \
  --group-ids $NODE_SG \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`8080`]' \
  --output table
```

If this returns nothing, the rule is missing — go back to Phase 2.

**4 — Verify webhook caBundle is populated**
```bash
kubectl get mutatingwebhookconfigurations vault-agent-injector-cfg \
  -o jsonpath='{.webhooks[0].clientConfig.caBundle}' | wc -c
```
Should return `1140` or similar. If it returns `1` or `4`, the caBundle is empty — do a full helm uninstall/reinstall.

**5 — Verify the service account exists**
```bash
kubectl get serviceaccount fleetman-sa -n default
```
If not found: `kubectl create serviceaccount fleetman-sa -n default`, then delete and recreate the test pod.

**6 — Force a fresh pod**
```bash
kubectl delete pod -l app=vault-inject-test
kubectl get pods -l app=vault-inject-test -w
```

### Auth failures in vault-agent logs (403, invalid JWT)

```bash
CA_CERT=$(kubectl config view --raw --minify --flatten \
  -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)

vault-local write auth/kubernetes/config \
  kubernetes_host="$KUBE_HOST" \
  kubernetes_ca_cert="$CA_CERT" \
  issuer="https://oidc.eks.us-east-1.amazonaws.com/id/$(aws eks describe-cluster \
    --name fleetman-eks \
    --region us-east-1 \
    --query 'cluster.identity.oidc.issuer' \
    --output text | cut -d'/' -f5)"
```

### kubectl connection drops during long sessions

EKS tokens expire after about an hour. Refresh:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name fleetman-eks

kubectl config use-context arn:aws:eks:us-east-1:659468809437:cluster/fleetman-eks
```

### helm uninstall / clean reinstall

Required when `helm status vault -n vault` shows `STATUS: failed`:

```bash
helm uninstall vault -n vault
kubectl delete namespace vault
kubectl get namespace vault -w   # wait for Terminating to disappear
kubectl create namespace vault
helm install vault hashicorp/vault \
  --namespace vault \
  --values ~/git/fleetman-eks/helm/vault-values.yaml \
  --wait --timeout 5m
```

---

## Quick Reference — Session Commands

```bash
# Refresh kubeconfig (run if kubectl stops responding)
aws eks update-kubeconfig --region us-east-1 --name fleetman-eks

# Kill stale port-forward
pkill -f "port-forward.*8200"

# Port-forward Vault
kubectl port-forward -n vault vault-0 8200:8200 &

# Check Vault status
kubectl exec -n vault vault-0 -- vault status

# List secrets
vault-local kv list fleetman/

# Check injector pod (get name first, then use directly)
kubectl get pods -n vault
kubectl logs -n vault <injector-pod-name> --tail=30

# Check webhook
kubectl get mutatingwebhookconfigurations
```

---

## Key Lessons Learned

- **Port 8080 must be explicitly allowed** from the cluster security group to the node security group. EKS only opens specific webhook ports by default (443, 4443, 6443, 8443, 9443). This needs to be added to Terraform.
- **A failed helm upgrade leaves a corrupted state** — `STATUS: failed` in `helm status` means do a full uninstall/reinstall, not an upgrade.
- **Use the pod name directly for injector logs** — the label selector `app.name=vault-agent-injector` is incorrect; use `kubectl get pods -n vault` to get the actual pod name.
- **Delete LoadBalancer services before terraform destroy** — `kubectl delete svc --all -n default`, wait 30 seconds, then destroy. Skipping this leaves orphaned ELBs, EIPs, and security groups that block VPC deletion.
- **EKS tokens expire after ~1 hour** — refresh kubeconfig with `aws eks update-kubeconfig` if kubectl stops responding mid-session.

---

*Runbook version: April 2026 | fleetman-eks Vault integration | WSL2/Ubuntu 24.04*
