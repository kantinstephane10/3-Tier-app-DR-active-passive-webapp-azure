# Security checks and critical-only approval

Owner: Kantin Tongue.

Install scanners once on the persistent Jenkins agent:

```bash
sudo bash scripts/install-security-tools-ubuntu.sh
```

The installer pins Gitleaks 8.30.1 and Trivy 0.75.0 and verifies release checksums. The pipeline verifies these versions. Permit outbound HTTPS for official releases and Trivy checks downloads; maintain scanner versions through reviewed changes.

In Jenkins, install the Pipeline: Input Step and HTML Publisher plugins. Replace `SECURITY_APPROVERS = 'security-approvers'` in the Jenkinsfile with an existing Jenkins group or comma-separated trusted user IDs. This is trusted pipeline configuration, not a build parameter. Jenkins administrators can also approve input steps. Disable shallow SCM checkout so Gitleaks can inspect the complete available Git history. Protect the deployment branch, Jenkinsfile, scanner configuration and agent against untrusted edits.

| Result | Behavior |
| --- | --- |
| LOW / MEDIUM / HIGH | Report and continue automatically |
| CRITICAL | Pause APPLY or BACKUP_RECONCILE for authorized approval |
| Detected secret | Treat as CRITICAL; requires approval |
| Unrated misconfiguration | Treat as CRITICAL; requires approval |
| Missing tool, wrong version, invalid output, scanner error or incomplete history | Fail build; no security waiver |
| Terraform validation, destructive-plan guard, plan hash or apply failure | Fail build; no security waiver |

Gitleaks scans Git history and the working directory with secret redaction. Trivy scans Terraform source and the resolved Terraform plan. Both scanners finish before the risk decision. Scanner nonzero exit codes are not blindly ignored: Gitleaks uses a distinct findings exit code (10), while Trivy returns zero for findings and nonzero for execution errors. Findings are classified from validated JSON.

PLAN runs all applicable scans and produces reports without waiting for approval, because it performs no deployment. APPLY collects source, secrets and plan findings and then requests approval only when critical findings exist. BACKUP_RECONCILE uses source/secret results and requests the same gate before its Azure mutation. Rejection, cancellation, a blank justification or the 30-minute gate timeout stops the build. Every new build scans again and requires its own approval; there is no global bypass switch.

Review the findings on the build's **Security Scan Report** page. It shows the counts per severity and a table with one row per finding: severity (colour coded), phase (`source` or `plan`), tool, check ID (linked to the rule's documentation), title, file, line, resource and the scanner's suggested fix. The same table is printed in Console Output after each scan, and `source.json`, `plan.json`, `summary.json` and `index.html` are archived as build artifacts. Reports contain rule metadata and locations only; code snippets, credentials and Terraform values are omitted. If the page looks unstyled, that is Jenkins' default Content Security Policy; the table uses plain HTML attributes and stays readable. An accepted exception creates `approval.json` with the approver, justification, commit, build, rollout, action, timestamp and saved-plan SHA-256. Do not put secrets into the justification. The saved plan's hash is rechecked immediately before apply. Reports remain available even when approval is rejected or a later stage fails. Raw scanner files are private temporary files deleted after scanning; the existing pipeline cleanup removes the raw Terraform plan and credential file.

Approval accepts the risk for that build; it does not remediate a finding. For a secret finding, rotate/revoke the credential and remove it from the repository and history as appropriate. Prefer fixing critical issues and rebuilding. HIGH findings remain visible and may represent significant risks even though this policy allows them to continue.

No cloud backend is introduced. Azure credentials remain Jenkins-bound ARM_* environment variables. Persistent local state stays outside the workspace. Gitleaks/Trivy do not provide application dependency or running-VM vulnerability coverage in this project; add those scans when application dependency manifests or built images exist. Git history scanning covers the checked-out repository's history, not every remote branch.

Official references:
- https://github.com/gitleaks/gitleaks
- https://trivy.dev/docs/latest/coverage/iac/terraform/
- https://plugins.jenkins.io/pipeline-input-step/
