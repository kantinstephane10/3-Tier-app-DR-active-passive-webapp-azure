# Kantin Tongue — Azure Terraform + Jenkins, local state

This version uses Azure service principal credentials exposed as Jenkins environment variables. Terraform stores its state on the Jenkins agent's local disk. No Azure state storage account or remote backend is created.

The infrastructure modules and rollout stages remain foundation -> primary -> dr -> edge. `PLAN` generates the plan; `APPLY` applies that build's saved plan. The project has not been deployed to Azure from this workspace. Local formatting, script syntax and state helper checks passed; provider execution here is restricted, so Jenkins must pass provider validation and its Azure-authenticated plan.

## 1. Use one persistent Jenkins agent

Use your existing Jenkins installation or an Ubuntu 24.04 machine. The agent can be on-premises or in Azure; managed identity is no longer required.

Assign the label `terraform-local` to **only one persistent agent**. Use one Pipeline job for this environment, keep its state on that same host, and do not use an ephemeral container/agent that loses its disk between builds. The Jenkinsfile disables concurrent builds; local file locking cannot coordinate different computers.

If Jenkins is not installed, from the extracted project run:

```bash
bash scripts/install-jenkins-ubuntu.sh
bash scripts/install-agent-tools-ubuntu.sh
```

For an existing agent run only the tools script. Confirm Java 21, Terraform 1.12.2, Azure CLI, Git and Python are available. The install script assumes an amd64 Ubuntu host.

For the supplied Jenkins installation, access localhost:8080 through SSH forwarding:

```bash
ssh -i /path/to/key.pem -L 8080:127.0.0.1:8080 YOUR_USER@JENKINS_HOST
```

Open http://localhost:8080, obtain `sudo cat /var/lib/jenkins/secrets/initialAdminPassword`, install suggested plugins and create the administrator account. Confirm Pipeline, Git, Credentials Binding and Timestamper plugins are installed.

## 2. Prepare local state storage

On the agent, run:

```bash
bash scripts/prepare-local-state.sh jenkins
```

If the agent runs under a different operating-system account, pass that account instead of jenkins. These backend paths are on the agent, not your workstation:

| File | Purpose |
|---|---|
| /var/lib/jenkins/terraform-state/kt-lab/infrastructure.tfstate | Workload state |
| /var/lib/jenkins/terraform-state/kt-lab/bootstrap.tfstate | Resource-group/RBAC bootstrap state |
| /var/lib/jenkins/terraform-state/kt-lab/backups/ | Latest 20 local workload-state snapshots |

Both roots declare `backend "local"`. State directories are mode 0700; state snapshots are mode 0600. The pipeline never deletes this directory during workspace cleanup. Back up this directory and the agent disk using your own local backup process; snapshots on the same disk do not survive loss of that disk.

The `state-created` marker makes the pipeline stop if a previously created workload state file goes missing. Keep the marker alongside the state. Use the default Terraform workspace. For another environment use another state path and job; do not reuse this lab state path.

## 3. Create the Azure service principal

In Azure Portal:

1. Microsoft Entra ID -> App registrations -> New registration.
2. Name: azure-terraform-jenkins. Choose your tenant's single-tenant account type; leave redirect URI empty.
3. Register. Copy **Application (client) ID** and **Directory (tenant) ID**.
4. Certificates & secrets -> Client secrets -> New client secret. Choose an expiry, create it, and copy its **Value** when displayed. Use the Value, not Secret ID.
5. Subscriptions -> your subscription -> copy Subscription ID.

Obtain the service principal's **Enterprise Application object ID** as an operator:

```bash
az login
az account set --subscription YOUR_SUBSCRIPTION_ID
az ad sp show --id YOUR_CLIENT_ID --query id -o tsv
```

This object ID is used for RBAC. It differs from the Application/client ID used for login. The Entra administrator for the SQL database is your admin user/group; do not substitute the Jenkins service principal for that administrator unless you intentionally design it that way.

## 4. Bootstrap resource groups and scoped permissions once

The bootstrap creates only primary, secondary and global resource groups and grants the service principal Contributor on them. It creates no storage account, state container, storage role or managed identity. Run it using an operator allowed to create resource groups and role assignments.

Because the backend directories belong to the Jenkins OS account, run bootstrap under that account with the **operator's interactive Azure login**, then clear that login. Example for a host account named jenkins, from the extracted project:

```bash
sudo cp -a . /var/lib/jenkins/bootstrap-kt-lab
sudo chown -R jenkins:jenkins /var/lib/jenkins/bootstrap-kt-lab
sudo -u jenkins -H bash
```

Inside that shell:

```bash
umask 077
cd /var/lib/jenkins/bootstrap-kt-lab
az login --use-device-code
az account set --subscription YOUR_SUBSCRIPTION_ID
bash scripts/register-providers.sh
cp bootstrap/terraform.tfvars.example bootstrap/terraform.tfvars
```

Edit bootstrap/terraform.tfvars with your subscription ID, prefix kt-lab, and the service principal object ID returned in step 3. Then:

```bash
terraform -chdir=bootstrap init
terraform -chdir=bootstrap validate
terraform -chdir=bootstrap plan -out=bootstrap.tfplan
terraform -chdir=bootstrap apply bootstrap.tfplan
terraform -chdir=bootstrap output resource_groups
az logout
az account clear
exit
```

The service principal cannot grant roles itself. Register providers with the operator because the workload provider deliberately disables automatic registration. RBAC propagation can take time after bootstrap; wait and retry if the first Pipeline login/plan is denied access to the new resource groups.

If you already deployed the earlier version, follow `docs/MIGRATE-TO-LOCAL.md` before bootstrapping or applying. Do not create a second empty state for existing infrastructure.

## 5. Add Jenkins Azure credentials as environment variables

Manage Jenkins -> Credentials -> System -> Global credentials -> Add Credentials. Add four **Secret text** credentials:

| Credential ID | Value | Pipeline environment variable |
|---|---|---|
| azure-client-id | Application/client ID | ARM_CLIENT_ID |
| azure-client-secret | Client secret Value | ARM_CLIENT_SECRET |
| azure-tenant-id | Directory/tenant ID | ARM_TENANT_ID |
| azure-subscription-id | Subscription ID | ARM_SUBSCRIPTION_ID |

The Jenkinsfile uses:

```groovy
environment {
    ARM_CLIENT_ID       = credentials('azure-client-id')
    ARM_CLIENT_SECRET   = credentials('azure-client-secret')
    ARM_TENANT_ID       = credentials('azure-tenant-id')
    ARM_SUBSCRIPTION_ID = credentials('azure-subscription-id')
    TF_VAR_subscription_id = credentials('azure-subscription-id')
    TF_VAR_tenant_id       = credentials('azure-tenant-id')
}
```

Terraform's Azure provider reads the ARM_* variables. TF_VAR_* supplies the root's subscription/tenant inputs. The pipeline also signs Azure CLI in as the same service principal for VM smoke tests and backup operations. Shell tracing is disabled around the login and secrets are expanded by the shell, not interpolated into Groovy.

Do not paste the client secret into a plain global environment property or commit it in a Jenkinsfile. Jenkins credentials still expose it as an environment variable at runtime, while retaining encrypted credential storage and console masking. Use only trusted code on the credentialed node and update the secret before it expires.

## 6. Fill deployment inputs and push the repository

```bash
cp environments/lab/config.tfvars.example environments/lab/config.tfvars
ssh-keygen -t ed25519 -f ~/.ssh/kt-lab -C 'Kantin Tongue Azure lab'
cat ~/.ssh/kt-lab.pub
```

Fill in the SSH public key, unique lowercase suffix, SQL admin login and SQL admin object ID. The configuration example contains no Azure credentials or subscription/tenant IDs; Jenkins supplies those separately. The default primary SKU is Standard_D2s_v5, standby SKU Standard_B2s, and SQL BC_Gen5_2 with zone redundancy. SQL, gateways, Front Door, NAT and Bastion have ongoing charges: price the selected SKUs before choosing APPLY.

Add a Jenkins **Secret file** credential:

- ID: azure-lab-tfvars.
- File: your completed config.tfvars.

There is no backend credential/file to upload. Do not create azure-lab-backend.

Push the modules, Jenkinsfile, scripts, docs and lock files to your Git repository. The gitignore excludes local config, state, plans and keys. Store a read-only checkout credential in Jenkins for a private repository. Never run the credentialed pipeline against an untrusted Jenkinsfile or contributed pull-request branch.

## 7. Configure the Pipeline job

New Item -> azure-three-tier-lab -> Pipeline.

- Pipeline script from SCM -> Git.
- Repository URL and read-only checkout credential.
- Branch: */main.
- Script path: Jenkinsfile.
- Node label terraform-local must point to the prepared state-owning agent.

The first run loads the parameters. If Build with Parameters is not visible yet, run Build Now once; defaults are foundation/PLAN.

Pipeline stages: checkout -> local state checks -> Azure login/config -> fmt/init/validate -> plan -> deletion check -> saved-plan apply -> backup reconciliation -> Front Door origin protection -> smoke test -> local state snapshot/temporary-file cleanup.

## 8. Roll out in cumulative stages

| ROLLOUT | Resources added |
|---|---|
| foundation | East US 2 VNet, subnets, NSGs, NAT, Bastion |
| primary | Primary web/app Flexible VMSS, Application Gateway, internal LB, private SQL and backup |
| dr | Central US stack, smaller standby compute, SQL failover group, private endpoints and VNet peering |
| edge | Front Door Premium, WAF, priorities and optional owned-domain DNS |

For each stage choose ACTION=PLAN, inspect Console Output, then choose the same ROLLOUT with ACTION=APPLY. An APPLY build makes and applies its own saved plan. Keep the highest deployed ROLLOUT selected after promotion. The plan checker stops deletions/replacements, including accidental rollback to an earlier stage.

## 9. Deploy foundation, primary and DR in order

### Foundation

ROLLOUT=foundation; ACTION=PLAN, then APPLY.

In Azure Portal open `rg-kt-lab-primary` and inspect:

- VNet `vnet-kt-lab-primary`, address `10.10.0.0/16`.
- AzureBastionSubnet `10.10.0.0/26`.
- ingress `10.10.1.0/24`.
- web `10.10.10.0/24`.
- app `10.10.20.0/24`.
- database `10.10.30.0/24`.
- NSGs on ingress/web/app/database.
- NAT associations on web/app; Bastion uses its dedicated subnet.

At this stage there are no application VMs or databases.

### Primary region

ROLLOUT=primary; ACTION=PLAN, then APPLY.

Verify:

1. Application Gateway backend health shows the web VMs healthy after cloud-init completes.
2. Two web and two app Flexible VMSS instances exist; inspect each VM's actual zone and private address.
3. The smoke test passes the web -> internal LB -> app path.
4. SQL primary server has public network disabled and Entra administrator set.
5. The SQL private endpoint connection is Approved; private DNS is linked to the primary VNet.
6. In Bastion, connect to an **app VM**, not the web tier. Test SQL hostname resolution and TCP 1433:

```bash
getent ahostsv4 YOUR_PRIMARY_SQL_SERVER.database.windows.net
python3 -c 'import socket; s=socket.create_connection(("YOUR_PRIMARY_SQL_SERVER.database.windows.net",1433),10); print("SQL TCP reachable"); s.close()'
```

7. Use an Entra-authenticated SQL client from a permitted application subnet to run `SELECT @@SERVERNAME, DB_NAME();`. TCP success alone does not verify SQL authentication or queries. An Azure portal public query editor cannot bypass the private-only network configuration.
8. Recovery Services vault -> Backup items -> Azure Virtual Machine: each Flexible instance is protected. Wait for the first scheduled backup or trigger Backup now and verify its recovery point.

The origin is not open to your browser by default: its NSG permits Front Door traffic and required Azure control traffic. The Jenkins private smoke test checks the regional application until Front Door is deployed.

### Secondary region and SQL replication

ROLLOUT=dr; ACTION=PLAN, then APPLY.

Verify matching Central US resources, `10.20.0.0/16`, private DNS links and bidirectional global VNet peering. The secondary compute uses a smaller VM SKU but keeps two instances per tier. In SQL failover groups, verify the partner server and synchronized secondary database. SQL failover is Manual for a coordinated drill. The real application should connect using the failover group listener, not a region-specific SQL name.

After adding the failover group, the demo VMSS template's database endpoint display changes; existing instances are not automatically rebuilt. This demo does not query SQL. Replace it with your real application and roll out its failover-listener configuration consistently before testing database failover.

## 10. Deploy edge routing and test failover

ROLLOUT=edge; ACTION=PLAN, then APPLY.

Jenkins prints the front_door_url output. Open it over HTTPS. Expect JSON containing owner Kantin Tongue and region eastus2. `database_connected=false` is intentional because this infrastructure demo does not run SQL queries.

Verify in Azure Portal:

- Front Door Premium origin group has primary priority 1 and secondary priority 2.
- Both origins are healthy.
- WAF policy is enabled, attached and in Prevention mode.
- Existing web VM nginx configurations contain the Front Door ID guard; newly created instances inherit it from the updated template.
- Direct requests to the public origin from your laptop fail because of the ingress NSG. The main application route also rejects requests lacking the specific Front Door ID header.

Use `docs/FAILOVER.md` for the controlled SQL/application drill. The built-in HTTP demo can validate region switching but cannot demonstrate database RPO until database reads/writes are added.

## 11. Optional Azure DNS/custom domain

Use a domain you own. Do not copy the domain shown in the original image unless it belongs to you.

After edge succeeds using its default hostname, set dns_zone_name to your domain and dns_host_label to app in your Jenkins tfvars credential. DNS zone creation/delegation and domain verification require a one-time staged operation:

1. On the same persistent agent with the configured service principal, initialize the local backend, supply the same config.tfvars and stage=edge.
2. Create the DNS zone first using this explicit bootstrap target:

```bash
terraform -chdir=environments/lab plan -var-file=config.tfvars -var=stage=edge -target='module.dns[0].azurerm_dns_zone.this' -out=dns-zone.tfplan
terraform -chdir=environments/lab apply dns-zone.tfplan
terraform -chdir=environments/lab output dns_name_servers
```

3. Change the domain's authoritative nameservers at your registrar to the returned Azure nameservers. Verify delegation using your DNS tooling.
4. Create the custom-domain registration and verification records:

```bash
terraform -chdir=environments/lab plan -var-file=config.tfvars -var=stage=edge -target='module.dns[0].azurerm_dns_txt_record.validation' -target='module.dns[0].azurerm_dns_cname_record.this' -out=dns-validation.tfplan
terraform -chdir=environments/lab apply dns-validation.tfplan
```

5. Wait until Front Door custom domain validation reports Approved. Then rerun Jenkins edge PLAN/APPLY to attach its HTTPS route and WAF. Wait for managed certificate provisioning and verify `https://app.YOUR_DOMAIN`.

These targets are limited to DNS bootstrap because registrar delegation is external to Terraform. Return to full plans immediately afterward; never routinely deploy with -target. If a target apply reports outputs not yet available, inspect the completed DNS resources and return to the full edge plan after domain validation.

## 12. Ongoing backup, costs and cleanup

Run ACTION=BACKUP_RECONCILE with the latest deployed ROLLOUT regularly, particularly after autoscale creates new VMs. Reconciliation enables backup; successful recovery points are a separate verification. A dedicated scheduled Jenkins job can run only reconciliation under the same identity. Avoid scheduling APPLY while learning.

Monitor actual costs in Azure Cost Management. Stopping VMs does not stop charges for SQL, Application Gateway, Front Door, NAT, Bastion, disks and backup retention.

When you deliberately finish the lab, use a separate trusted operator cleanup process: disable protection and choose retention/deletion intentionally; inspect soft-deleted backups; then plan/apply a Terraform destroy using the latest rollout stage and same configuration on the state-owning agent. The deployment Jenkinsfile intentionally has no destroy action. Retain both local state files until the workload and resource groups are removed. Backups may retain charges during soft-delete/retention periods.

## Security and critical-only approval

Install the pinned scanners and configure trusted Jenkins approvers as described in [PIPELINE-SECURITY.md](docs/PIPELINE-SECURITY.md). Gitleaks scans secrets; Trivy scans Terraform source and the saved plan. LOW/MEDIUM/HIGH findings continue automatically. CRITICAL findings require an authorized, recorded risk acceptance before APPLY or BACKUP_RECONCILE. PLAN only reports. Scanner execution errors stop the build.

## Verification status

Formatting/parsing, script syntax, cloud-init rendering, plan deletion checks, local-state snapshot retention and local-backend path behavior have been checked. Provider schema execution, Jenkins runtime and Azure plan/apply have not run here because this workspace prohibits the provider's Unix socket. They remain mandatory Pipeline gates. No Azure resources were created from this workspace.

## Official references

- Service principal environment authentication: https://learn.microsoft.com/en-us/azure/developer/terraform/authenticate/authenticate-to-azure-with-service-principle
- Jenkins credentials binding: https://www.jenkins.io/doc/pipeline/steps/credentials-binding/
- Terraform local backend: https://developer.hashicorp.com/terraform/language/backend/local
- Jenkins Linux installation: https://www.jenkins.io/doc/book/installing/linux/
- Azure VM backup support: https://learn.microsoft.com/en-us/azure/backup/backup-support-matrix-iaas
