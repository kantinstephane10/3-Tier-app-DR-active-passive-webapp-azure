#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release unzip git python3
sudo install -d -m 0755 /etc/apt/keyrings
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o "$TASK_TMP/microsoft.asc"
gpg --dearmor < "$TASK_TMP/microsoft.asc" > "$TASK_TMP/microsoft.gpg"
sudo install -m 0644 "$TASK_TMP/microsoft.gpg" /etc/apt/keyrings/microsoft.gpg
TASK_DIST=$(lsb_release -cs)
TASK_ARCH=$(dpkg --print-architecture)
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ %s main\n' "$TASK_ARCH" "$TASK_DIST" | sudo tee /etc/apt/sources.list.d/azure-cli.list >/dev/null
sudo apt-get update
sudo apt-get install -y azure-cli
TASK_VERSION=1.12.2
TASK_ZIP="terraform_${TASK_VERSION}_linux_amd64.zip"
cd "$TASK_TMP"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TASK_VERSION}/${TASK_ZIP}"
curl -fsSLO "https://releases.hashicorp.com/terraform/${TASK_VERSION}/terraform_${TASK_VERSION}_SHA256SUMS"
grep "$TASK_ZIP" "terraform_${TASK_VERSION}_SHA256SUMS" | sha256sum -c -
unzip -q "$TASK_ZIP" terraform
sudo install -m 0755 terraform /usr/local/bin/terraform
terraform version
az version
