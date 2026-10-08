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
Compose and Ansible syntax. After validation, pushes to `main` and manual runs
on `main` deploy the tested image with Ansible. PRs never run the deployment job.

The image is transferred as a GitHub Actions artifact and loaded into Docker on
EC2. No container registry or registry password is needed. Each image is tagged
with its Git commit SHA. CI deployments contain the website inside the image,
so deleted files disappear on the next deployment. Local Compose still mounts
`html/` for immediate edits. The manual deployment script uses the original
file-copy approach; use the pipeline consistently for image-based releases.

### One-time setup

1. This project uses https://github.com/RyanLeary2764/Test_Web_Server_Reusable
   with `main` as the deployment branch.
2. Set `github_repository = "RyanLeary2764/Test_Web_Server_Reusable"` in `terraform/terraform.tfvars`.
   If this AWS account already has a GitHub OIDC provider, set
   `github_oidc_provider_arn` to its ARN so Terraform reuses it.
3. Initialize, plan, and apply Terraform as described above. Terraform remains a
   separate infrastructure step; the pipeline manages Docker and Ansible.
4. In GitHub **Settings → Environments**, create `preview` and restrict deployment
   branches to `main`. The AWS trust policy permits this repository's `preview`
   environment. Restricting its branches is part of the access setup.
5. Add these environment variables and secrets:

| Kind | Name | Value |
| --- | --- | --- |
| Variable | `AWS_DEPLOY_ROLE_ARN` | `terraform -chdir=terraform output -raw github_deploy_role_arn` |
| Variable | `PREVIEW_SECURITY_GROUP_ID` | `terraform -chdir=terraform output -raw preview_security_group_id` |
| Variable | `PREVIEW_HOST` | `terraform -chdir=terraform output -raw preview_host` |
| Secret | `PREVIEW_SSH_PRIVATE_KEY` | Full unencrypted CI SSH private key matching Terraform's public key |
| Secret | `PREVIEW_SSH_KNOWN_HOSTS` | Verified known-hosts entry for the exact `PREVIEW_HOST` IPv4 address |

Use a dedicated CI SSH key. Verify the server's host key using the AWS EC2 console
system log or another trusted channel before saving its known-hosts entry. The
pipeline enforces host-key checking and does not blindly trust `ssh-keyscan`.

AWS authentication uses OIDC, so no AWS access-key secrets are required. The role
can add/remove ingress only on this preview server's security group. Each run
allows SSH from the GitHub runner's current IPv4 `/32` and removes that rule in an
`always()` cleanup step. HTTP remains limited to your Terraform `allowed_cidr`.
After a forced termination or runner loss, check for and remove any leftover
runner SSH rule. A stopped/restarted or replaced EC2 instance may require updating
`PREVIEW_HOST` and the verified known-hosts secret.

After infrastructure and environment settings are ready, create the **repository**
Actions variable `PREVIEW_DEPLOY_ENABLED` with value `true`. Until then, the build
and validation job runs and deployment is skipped. Set it to `false` to pause
deployments.

Push an edit to `html/` on `main` to deploy, or use **Actions → Website preview →
Run workflow** on `main`. A failed HTTP check fails deployment but does not roll
back automatically. To restore an earlier site, revert the change on `main` and
let the pipeline deploy the reverted content. Old image tags remain on the host;
periodically remove unused images with `docker image prune -a` after checking
which versions you need to retain.

Reference: [GitHub OIDC for AWS](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
and [environment deployment restrictions](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments).
