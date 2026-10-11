#!/usr/bin/env bash
set -euo pipefail
for provider in Microsoft.Network Microsoft.Compute Microsoft.Storage Microsoft.Authorization Microsoft.Sql Microsoft.RecoveryServices Microsoft.Insights Microsoft.Cdn Microsoft.ManagedIdentity; do
  az provider register --namespace "$provider" --wait
 done
