#!/usr/bin/env bash
set -euo pipefail
: "${TF_STATE_BUCKET:?Set the TF_STATE_BUCKET environment variable}"
: "${PREVIEW_ALLOWED_CIDR:?Set PREVIEW_ALLOWED_CIDR to your public IPv4 /32}"
: "${SSH_PRIVATE_KEY:?Set the PREVIEW_SSH_PRIVATE_KEY environment secret}"
mkdir -p "$RUNNER_TEMP/preview-infra"
cp terraform/{main,variables,versions,outputs}.tf "$RUNNER_TEMP/preview-infra/"
cp terraform/.terraform.lock.hcl "$RUNNER_TEMP/preview-infra/"
umask 077
printf '%s\n' "$SSH_PRIVATE_KEY" > "$RUNNER_TEMP/preview-key"
ssh-keygen -y -f "$RUNNER_TEMP/preview-key" > "$RUNNER_TEMP/preview-key.pub"
cat > "$RUNNER_TEMP/preview-infra/backend.tf" <<'EOF'
terraform {
  backend "s3" {
    key          = "preview/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
EOF
cat > "$RUNNER_TEMP/preview-infra/ci-outputs.tf" <<'EOF'
output "preview_security_group_id" {
  value = aws_security_group.preview.id
}
EOF
echo "TF_VAR_ssh_public_key_path=$RUNNER_TEMP/preview-key.pub" >> "$GITHUB_ENV"
echo "TF_VAR_allowed_cidr=$PREVIEW_ALLOWED_CIDR" >> "$GITHUB_ENV"
