# Controlled failover exercise

Run after the `edge` deployment succeeds. This is a manual drill, not an automatic remediation job.

1. Confirm both regional Application Gateway backend pools and web/app services are healthy. Confirm the SQL failover group secondary database is synchronized and has private endpoints in both regions. Check web/app placement: two instances and `zones=[1,2]` request zone spreading, but Flexible VMSS `zone_balance=false` does not guarantee one instance in each zone. Inspect actual VM zone placement before claiming zone resiliency.
2. Before moving traffic, use the SQL failover group listener in the real application, configure its Entra database user, and validate reads/writes. The bundled demo has no database operations, so its HTTP test measures the application routing path only.
3. If the secondary tier needs more capacity, change `standby_vm_size` to the primary SKU, keep `ROLLOUT=edge`, run PLAN, inspect it, then APPLY. VMSS template SKU updates with manual upgrade mode may require a separate controlled instance rollout; do not assume updating the model resizes existing instances. Explicitly inspect and roll existing Flexible instances using Azure-supported VM operations. Back up first and keep at least one healthy instance per tier during the rollout.
4. In Azure Portal > SQL failover groups, perform a planned failover to Central US. Do not use forced failover for this drill. Record UTC start/end time and query the data through the listener from an application VM.
5. In Front Door > Origin groups > regional, disable the primary origin. This simulates a routing outage without deleting resources. Front Door health probes and propagation are not instantaneous.
6. Repeatedly request the Front Door HTTPS URL. Confirm the JSON changes from `eastus2` to `centralus`. Record time to stable service. The database-connected field remains false until you replace the demo application.
7. Restore the primary origin after confirming its health. Priority 1 normally receives traffic again. Perform a planned SQL failback when appropriate and verify the listener.
8. Run Jenkins PLAN with ROLLOUT=edge to reconcile any portal drift intentionally. Keep the tested application release deployed in both regions.

A forced SQL failover can lose writes that were not replicated. Record RPO from actual database test records rather than assuming asynchronous replication has zero data loss. The SQL failover policy is deliberately Manual so application/data promotion can be coordinated.

# Backup restore exercise

Verify that each Flexible VM is protected and has at least one recovery point. In the primary Recovery Services vault use Cross Region Restore, choose the paired region, and restore disks or a VM into an isolated recovery resource group/network. Validate the recovered application. Restore does not automatically recreate VMSS membership, autoscale settings, Application Gateway registrations, or the full application release pipeline. Recovery copies are managed by Azure Backup, not a user-created second destination vault. Both regions also have their own vault to protect their local running VMs.
