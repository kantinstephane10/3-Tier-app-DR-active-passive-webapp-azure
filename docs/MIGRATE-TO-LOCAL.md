# If the earlier remote-state version was already used

Do not run a fresh local APPLY against existing infrastructure. Existing resource IDs must remain in the state. No migration is needed if you have not deployed anything.

For an existing workload:

1. Stop its Jenkins deployments and retain a backup of the current workload state using the original state-access identity. Work in the original initialized Terraform directory; preserve its .terraform backend metadata.
2. Prepare the final local directory on the persistent Jenkins agent and arrange the original identity's access to the old backend. Move the original initialized directory to that agent if necessary, preserving configuration and metadata. Do not use init -reconfigure before migration because it discards the old-backend connection metadata.
3. Replace backend "azurerm" with the provided backend "local" pointing to /var/lib/jenkins/terraform-state/kt-lab/infrastructure.tfstate.
4. Run terraform init -migrate-state interactively with the original state-access identity. Review the copy prompt and migrate the existing state to the local file. Do not run APPLY during this step.
5. Confirm terraform state list contains the expected existing resources. Confirm the state file exists at the final path, is readable by the Jenkins agent account, and has restrictive permissions. Create its state-created marker with the backup-local-state.py helper. Do not delete the original state or storage account while verifying migration.
6. Run the updated Jenkins Pipeline with the latest deployed ROLLOUT and ACTION=PLAN. Review any changes before APPLY.

Bootstrap is a separate state. If the earlier bootstrap was applied, retain its state and existing backend storage resources. Do not copy that full state into the reduced bootstrap and apply: that would propose deletion of the old storage account and related role assignments. Transfer ownership of the existing workload resource groups/role assignments deliberately (using import or explicit state refactoring) while retaining the legacy state-storage resources until migration has been verified. Existing managed-identity Contributor assignments may coexist with the new service-principal assignments. Removal of legacy storage/RBAC is a separate cleanup action; this update does not perform it.

If a local file is lost, restore it from a known-good backup before planning. Do not reconstruct infrastructure by starting from an empty state. The supplied snapshots are local copies on the same disk; retain an independent backup of the agent/state directory.
