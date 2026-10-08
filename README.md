# Silipos website preview

Edit files in `html/` to test static HTML, CSS, JavaScript, and images.

## Local preview

Start Docker Desktop, then run from this directory:

```sh
docker compose up -d
```

Open http://localhost:8080. File edits appear on refresh without rebuilding.
Stop with `docker compose down`. Nginx disables browser caching for previews.

## AWS setup

Terraform creates a dedicated VPC, public subnet, internet gateway, restricted
security group, SSH key pair, and one Ubuntu 24.04 `t3.micro` EC2 instance in
`us-east-1`. Ansible installs Ubuntu's Docker package, copies the website, starts
Nginx, and verifies HTTP. EC2, EBS, public IPv4, and data transfer can incur charges.

Requirements: Terraform >=1.6, AWS CLI with authenticated credentials, an SSH key,
and Ansible. On macOS:

```sh
brew install ansible
ansible-galaxy collection install -r ansible/requirements.yml
```

Choose the intended AWS account explicitly:

```sh
export AWS_PROFILE=your-profile
aws sts get-caller-identity
```

If using SSO, run `aws sso login --profile "$AWS_PROFILE"` first.
Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars` and set
your real public IPv4 address as a `/32` and an existing SSH public key path.
The example IP is a placeholder. Both SSH and HTTP are limited to this CIDR.
If needed, create a dedicated key with `ssh-keygen -t ed25519 -f ~/.ssh/silipos-preview`.
Never put private keys or AWS credentials in this repository.

```sh
terraform -chdir=terraform init
terraform -chdir=terraform fmt -check
terraform -chdir=terraform validate
terraform -chdir=terraform plan -out=preview.tfplan
terraform -chdir=terraform apply preview.tfplan
bash scripts/deploy.sh ~/.ssh/silipos-preview
terraform -chdir=terraform output -raw preview_url
```

Use the private key corresponding to the public key configured in Terraform.
On first SSH connection, verify the server fingerprint against a trusted source
such as the AWS EC2 console system log before accepting it. SSH host-key checking
remains enabled. If Ansible cannot prompt, connect once with
`ssh -i ~/.ssh/silipos-preview ubuntu@SERVER_IP`, verify and accept the key, then deploy.

## Update the AWS preview

Edit `html/`, then rerun:

```sh
bash scripts/deploy.sh ~/.ssh/silipos-preview
```

Copying overwrites changed files and adds new files. Deleted local files are not
automatically removed from the server; remove those intentionally over SSH.
Nginx configuration changes restart the container. HTML changes need only a refresh.
The image uses the `stable-alpine` tag; pin a tested digest for reproducible releases.

## Operations

This is a restricted HTTP preview. Add a domain, TLS, and an appropriate production
deployment process before using it as a public production website. Public IPs can
change after EC2 stop/start; regenerate inventory by rerunning the deployment script.
Update `allowed_cidr` and apply Terraform if your network's public IP changes.

Terraform state is local and ignored by Git. Keep it backed up securely; losing it
makes managing or removing resources harder. Commit `.terraform.lock.hcl` after init.

To remove the AWS preview and its uploaded files:

```sh
terraform -chdir=terraform destroy
```

## GitHub Actions pipeline

`.github/workflows/preview.yml` runs validation on pull requests, pushes to `main`,
and manual runs. It builds the Dockerfile, starts Nginx, checks that the served
index matches `html/index.html`, checks a missing URL returns 404, and validates
Compose and Ansible syntax. After validation, pushes to `main` and manual runs on `main` create or update the
EC2 server with Terraform, deploy the tested image, and verify HTTP. PRs never
provision AWS resources. The server remains running until the separate manual
**Destroy website preview** workflow is run.
The image is transferred as a GitHub Actions artifact and loaded into Docker on
EC2. No container registry or registry password is needed. Each image is tagged
with its Git commit SHA. CI deployments contain the website inside the image,
so deleted files disappear on the next deployment. Local Compose still mounts
`html/` for immediate edits. The manual deployment script uses the original
file-copy approach; use the pipeline consistently for image-based releases.

### One-time setup for workflow-managed infrastructure

Bootstrap an AWS OIDC role and a private, encrypted, versioned S3 state bucket
once locally using the `terraform` profile:

```sh
export AWS_PROFILE=terraform
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
terraform -chdir=terraform/bootstrap output
```

If this account already has a GitHub OIDC provider (including one created by the
original root configuration), reuse it by passing
`-var='github_oidc_provider_arn=arn:aws:iam::340752808446:oidc-provider/token.actions.githubusercontent.com'`
to both bootstrap plan and apply. Do not create a duplicate provider. Bootstrap
uses separate local state; back it up securely. For this repository, set the
following in `terraform/bootstrap/terraform.tfvars` so the trust policy matches
GitHub's immutable OIDC identity:

```hcl
github_oidc_subject = "repo:RyanLeary2764@204479055/Test_Web_Server_Reusable@1409531879:environment:preview"
```

See [GitHub's OIDC trust-policy documentation](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws).

 Its role can create and delete
EC2 networking and instances throughout `us-east-1`; use a dedicated lab account.
It has no IAM administration permission.

In GitHub Settings → Environments, create `preview` and restrict deployment
branches to `main`. Configure these environment settings:

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `AWS_PROVISION_ROLE_ARN` | Bootstrap `provision_role_arn` output |
| Variable | `TF_STATE_BUCKET` | Bootstrap `state_bucket` output |
| Variable | `PREVIEW_ALLOWED_CIDR` | Your actual public IPv4 followed by `/32` |
| Secret | `PREVIEW_SSH_PRIVATE_KEY` | Dedicated unencrypted SSH private key |

Set repository Actions variable `PREVIEW_DEPLOY_ENABLED` to `true` after setup.
The previous static host, security group, deployment role, and known-hosts settings
are unused. The workflow derives the public key from the private key and verifies
server host keys using authenticated EC2 console output, failing closed if the
keys are unavailable. Keep the same SSH secret for subsequent deployments.

Push to `main` or run **Actions → Website preview → Run workflow** on `main`.
Terraform stores state at `s3://TF_STATE_BUCKET/preview/terraform.tfstate` with
S3 locking. Both workflows share a concurrency group and backend. Later deploys
reuse that state instead of creating duplicate infrastructure. SSH access for the
runner is removed after deployment; HTTP remains restricted to your configured
CIDR. The preview URL appears in the deployment run summary.

To remove the preview server and network, run **Actions → Destroy website preview
→ Run workflow** on `main` and type `destroy`. The bootstrap role and state bucket
remain available so the next deployment can recreate the server. AWS resources
continue incurring charges until destruction succeeds. Deployment failures retain
infrastructure in state so you can retry deployment or run the destroy workflow.
After forced cancellation or runner loss, check for leftover runner SSH rules.

The workflows use isolated copies of the root Terraform files, excluding local
state, local tfvars, and the old deployment IAM resources. Any server you already
created locally remains separate: these workflows will not destroy it. To retire
that stack, review `terraform -chdir=terraform plan -destroy` locally. If bootstrap
reuses its OIDC provider, preserve the provider before destroying the old stack;
do not delete an OIDC provider used by the new workflow role. Migrating the existing
server into the shared backend requires a separate state migration rather than
running the new pipeline against empty state.

Backend reference: [Terraform S3 backend and locking](https://developer.hashicorp.com/terraform/language/backend/s3).
