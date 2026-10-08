#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/ssh-private-key" >&2
  exit 1
fi
command -v ansible-playbook >/dev/null || { echo "Install Ansible first (see README.md)." >&2; exit 1; }
terraform -chdir=terraform output -json ansible_inventory > ansible/inventory.json
ansible-playbook -i ansible/inventory.json --private-key "$1" ansible/playbook.yml
