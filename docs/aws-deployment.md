# Optional AWS EKS deployment

**Status: live AWS application, public API isolation, EBS persistence and monitoring verified from Windows PowerShell on 3 November 2026.**
The free [Kind quick start](../README.md#quick-start) remains the primary reviewer path.
AWS is optional and requires your own permitted account, temporary credentials and explicit approval of billable plans.

The AWS scripts intentionally provide **validation, private preparation, connection, read-only verification and cleanup gates only**.
They never run Terraform plan/apply/destroy, delete cloud resources or purge the backend.
The controlled commands below are for a separately approved Phase C, not instructions to execute during Phase B.
A successful static check is not evidence of a working EKS deployment.

## Architecture and boundaries

- Standard EKS 1.36; one On-Demand x86_64 `m7i-flex.large` (2 vCPUs / 8 GiB).
- Dedicated VPC, two public /24 subnets in different availability zones, internet gateway and public IPv4 assignment.
  No NAT gateway, SSH access, public NodePort, ECR repository, RDS, Secrets Manager or automatic GitHub CD.
- The worker group stays in the first subnet/AZ so replacement nodes can reattach the existing zonal EBS volume.
- Private EKS endpoint enabled; public EKS endpoint restricted to approved administrator IPv4 CIDRs (/32 preferred).
- AL2023 managed node image, encrypted 30 GiB gp3 root disk, IMDSv2, hop limit 1.
  The managed node AMI is selected by EKS at creation; its exact release still needs review in Phase C.
- Separate EKS Pod Identity roles for VPC CNI, EBS CSI and AWS Load Balancer Controller.
  Trust policies restrict cluster ARN, namespace and service account through session tags.
  The pinned Pod Identity agent is installed before CNI and worker creation; the node role already permits EKS Auth.
  Worker permissions use AWS worker-node and ECR pull policies; application containers receive no AWS credentials.
  The controller IAM policy is vendored unchanged from the [pinned v3.6.2 upstream policy](https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/v3.6.2/docs/install/iam_policy.json).
  It includes optional integration permissions; WAF, WAFv2 and Shield integrations are disabled in the chart.
- MySQL uses the existing pinned chart/image and a 2 GiB encrypted gp3 PVC, `WaitForFirstConsumer`, reclaim policy `Delete`.
  The StatefulSet retains PVCs when removed or scaled. Pod recreation keeps data; final namespace removal deletes PVCs.
- Prometheus/Grafana/exporter reuse the existing configuration. Monitoring storage is ephemeral, retention is two hours.
  Main workload memory limits total about 2.9 GiB; EKS add-ons, controllers and the OS also consume memory.
- API ingress is disabled by default. When approved, one internet-facing ALB routes **exactly /user**, including query strings.
  Its default backend returns 404; readiness health checks reach Actuator internally without publishing an Actuator listener rule.
  Client access defaults to explicit CIDRs; worldwide IPv4 API access requires `allow_unrestricted_api=true`.
- Application, MySQL, Grafana and Prometheus Services remain ClusterIP. Access monitoring through localhost port-forwarding.

This is a disposable demonstration, not a highly available production design. A node replacement or update can interrupt every workload.
Spot is deliberately excluded to avoid interruption during recording.

The initial IRSA deployment was blocked by an account service control policy denying
`iam:CreateOpenIDConnectProvider`. Pod Identity uses supported EKS associations instead of an IAM OIDC provider;
no account upgrade, organization-policy change or broader node permissions are required by this configuration.
Availability remains subject to the reviewer's own account policies. See
[AWS Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-identities.html).

## Account eligibility and cost

Phase A observed an active Free plan with $100 credit, expiring 30 April 2027.
Those observations are historical, not a current balance check. AdministratorAccess and an EC2 catalog
`FreeTierEligible` flag do **not** prove that the account permits EKS or managed node groups.
Confirm service entitlement in the account console before approving provisioning. Never upgrade the account implicitly.
Stockholm's standard On-Demand vCPU quota was 5; one node needs 2. Launch capacity and update surge remain separate constraints.
Frankfurt discovery was denied by an organization policy; do not switch there or assume it is empty.

Approximate Stockholm list prices observed on 3 November 2026, before credits, tax and traffic:

| Resource | USD/hour |
| --- | ---: |
| EKS standard support | 0.10000 |
| One m7i-flex.large | 0.10175 |
| ALB base | 0.02394 |
| ALB capacity, 0–1 LCU assumption | 0–0.00760 |
| Three public IPv4 addresses minimum: worker + two ALB AZs | 0.01500 |
| 32 GiB gp3 at $0.0836/GiB-month, using 730 hours/month | 0.00366 |
| Total with public ingress | about 0.244–0.252 |

Budget **about $0.25/hour or $6/day**, plus S3 storage/requests, transfer and applicable taxes.
Without ingress the ALB and its public IP charges do not apply. Partial-hour billing and deployment/cleanup time also matter.
EKS, EC2, EBS, ALB and IPv4 charges continue when application pods are idle.
S3 versions remain billable after compute teardown. No budget or automatic spending cap is created.

Sources: [EKS pricing](https://aws.amazon.com/eks/pricing/), [EC2 pricing](https://aws.amazon.com/ec2/pricing/on-demand/),
[EBS pricing](https://aws.amazon.com/ebs/pricing/), [IPv4 pricing](https://aws.amazon.com/vpc/pricing/),
[ALB pricing](https://aws.amazon.com/elasticloadbalancing/pricing/).

## Prerequisites and authentication

Use Terraform **1.15.8**, Helm **4.3.1**, AWS CLI **v2**, kubectl **1.35–1.37**, Git 2.x;
Bash additionally needs **Bash 4+ and jq 1.6+**. Windows scripts support PowerShell 5.1+.
Put the correct binaries on PATH. AWS scripts prefer the repository's ignored `.local/bin/kubectl` (or `kubectl.exe`)
when present, matching the Kind setup; otherwise install a supported kubectl on PATH.
Docker is optional for anonymous image inspection. Linux/macOS AWS lifecycle execution is pending live validation;
Git Bash syntax checks do not establish native Linux/macOS compatibility.

Authenticate with your own temporary-credential profile using your organization's approved login method.
Do not use root, paste access keys into scripts, read credential files into logs, or use `aws --debug`.
The default profile is rejected because it belongs to a different account on the development machine.
Use an independently confirmed expected account, not an account ID automatically accepted from STS.

Copy `terraform/aws/deployment.example.json` to ignored `.local/aws/deployment.json`.
Replace every placeholder, including documentation IP addresses, with your own values.
Keep public ingress false initially. Supply your durable IAM operator role ARN, not an STS assumed-role session ARN.
Keep `allow_unrestricted_api=false` unless you intentionally want everyone to reach the API.
Use a unique bucket name in your account. Do not commit this private file.

PowerShell, from the repository root:

```powershell
New-Item -ItemType Directory -Path .local/aws -Force | Out-Null
if (Test-Path .local/aws/deployment.json) { throw 'Private configuration already exists.' }
Copy-Item terraform/aws/deployment.example.json .local/aws/deployment.json
# Edit the new private file before Prepare. Do not overwrite an existing configuration.
.\scripts\aws-setup.ps1 -Mode Validate
.\scripts\aws-setup.ps1 -Mode Prepare
```

Bash:

```bash
umask 077
mkdir -p .local/aws
# Refuse to replace an existing private configuration:
(set -o noclobber; cat terraform/aws/deployment.example.json > .local/aws/deployment.json)
# Edit the new private file before prepare.
bash scripts/aws-setup.sh --mode validate
bash scripts/aws-setup.sh --mode prepare
```

Validate initializes providers with `-backend=false`; it does not contact a live backend.
Prepare verifies the account and role, then creates new private inputs and a partial backend file.
It refuses existing generated files and does not create state or plans. Review/archive those inputs manually before regenerating them.
On Windows, keep `.local/aws` restricted to your user with appropriate NTFS permissions; on Unix, use owner-only permissions.
Never include its contents in screenshots or uploads.

Before deployment, verify the chosen full SHA actually exists in public GHCR and includes linux/amd64.
Use a fresh Docker configuration directory for an anonymous check rather than logging out your normal credentials.
The chart overlay's sentinel tag is for rendering only; Terraform rejects it and requires a full 40-character SHA.
No AWS path uses `latest` or a local-image fallback.
Use an already published main-branch image SHA: local AWS feature commits do not have published images.
The infrastructure can be tested locally against that existing image without pushing this branch.

## State isolation, security and recovery

```text
terraform/cluster/          existing Kind root — unchanged
terraform/platform/         existing Kind root — unchanged
terraform/aws/bootstrap/    protected local bootstrap state
terraform/aws/cluster/      S3: crewmeister/aws/cluster.tfstate
terraform/aws/platform/     S3: crewmeister/aws/platform.tfstate
```

Use one AWS deployment per backend bucket and checkout. Never use a Kind workspace/state as AWS isolation.
Only the default workspace is supported. New roots use independent provider locks and exact provider versions.

Bootstrap's local backend is explicitly `.local/aws/bootstrap.tfstate`, relative to the repository root.
The bootstrap guard rejects an existing state for a different bucket and verifies backend protections when that state already exists.
It creates an owner-selected S3 bucket with versioning, AES256 encryption, blocked public access, TLS-only access
and restricted principals. The normal operator and an account-root recovery principal are admitted by the restriction;
this does not grant permissions by itself and is not a recommendation to operate as root.
The bucket blocks deletion of the bucket, state versions and current state objects. Lockfile deletion remains permitted.
Terraform also sets `prevent_destroy` and `force_destroy = false`.

Cluster/platform initialization receives bucket, region, explicit profile and allowed account IDs through ignored `backend.hcl`.
Each root hardcodes its own state key, encryption and native `use_lockfile = true`.
A generated IAM policy scopes state-object read/write and lock-object read/write/delete; attachment to an operator role
is a separately reviewed IAM decision, not an implicit change to an existing role.
The currently authenticated administrative role remains broad; resource policies do not turn it into a least-privilege provisioning role.
See [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3).

**State and saved plans can contain MySQL/Grafana passwords, even when outputs are sensitive.**
Never commit them, dump plan JSON into logs, or display Kubernetes Secret contents.
The existing ignore rules cover state/backups, plans, private tfvars, kubeconfigs and `.local`.

After each approved bootstrap change, make a new, non-overwriting backup of the bootstrap state to an encrypted,
access-controlled location outside the repository. Keep an additional encrypted recovery copy; NTFS/Unix permissions alone
do not encrypt a disk. Record the bucket, state keys, version IDs and operator role privately.
Do not auto-migrate bootstrap state or overwrite an existing state.
Recovery prefers a verified backup; inspect identity and resource inventory before restoring it.
Lost-state reconstruction/import requires a separate recovery review and approval.

S3 versioning supports recovery of cluster/platform state: preserve the current version first, inspect candidate versions privately,
confirm account/key/resource ownership, then restore only after explicit approval and with no concurrent Terraform operation.
Do not blindly force-unlock or copy another environment's state.

## Controlled first deployment — Phase C only

**The following operations have not been executed. Stop until service eligibility and the specific saved plans are approved.**
Do not bundle all stages into an unattended command. Saved-plan apply has no interactive confirmation;
owner approval must occur before executing it.

Use the prepared files. Do not add `-reconfigure`, `-migrate-state`, `-force-copy`, `-auto-approve`, or workspace switches.
If Terraform reports unexpected existing state/backend configuration, stop and investigate.

Set paths once in PowerShell:

PowerShell variables belong to the current terminal. Repeat this block after opening a new terminal.
Run native commands individually and stop on any failure; a failed guard must never be followed by apply.

```powershell
$env:TF_WORKSPACE = 'default'
$config = Get-Content .local/aws/deployment.json -Raw | ConvertFrom-Json
$privateDir = Join-Path (Get-Location) ".local/aws/$($config.cluster_name)"
```

Or in Bash:

```bash
export TF_WORKSPACE=default
private_dir="$PWD/.local/aws/$(jq -r .cluster_name .local/aws/deployment.json)"
```

### 1. Bootstrap

PowerShell:

```powershell
.\scripts\aws-setup.ps1 -Mode Guard -Stage bootstrap
terraform -chdir=terraform/aws/bootstrap init -input=false
terraform -chdir=terraform/aws/bootstrap plan -input=false "-var-file=$privateDir/bootstrap.tfvars.json" "-out=$privateDir/bootstrap.tfplan"
terraform -chdir=terraform/aws/bootstrap show "$privateDir/bootstrap.tfplan"
# STOP: review the plan and obtain approval before the next two commands.
.\scripts\aws-setup.ps1 -Mode Guard -Stage bootstrap
terraform -chdir=terraform/aws/bootstrap apply "$privateDir/bootstrap.tfplan"
```

Bash:

```bash
bash scripts/aws-setup.sh --mode guard --stage bootstrap
terraform -chdir=terraform/aws/bootstrap init -input=false
terraform -chdir=terraform/aws/bootstrap plan -input=false -var-file="$private_dir/bootstrap.tfvars.json" -out="$private_dir/bootstrap.tfplan"
terraform -chdir=terraform/aws/bootstrap show "$private_dir/bootstrap.tfplan"
# STOP: review and obtain approval before continuing.
bash scripts/aws-setup.sh --mode guard --stage bootstrap
terraform -chdir=terraform/aws/bootstrap apply "$private_dir/bootstrap.tfplan"
```

Acceptance: inspect bucket owner/region, versioning, encryption, policy, blocked public access and tags.
Back up bootstrap state before proceeding. No automatic migration or existing-state replacement occurs.

### 2. Cluster

PowerShell:

```powershell
.\scripts\aws-setup.ps1 -Mode Guard -Stage cluster
terraform -chdir=terraform/aws/cluster init -input=false "-backend-config=$privateDir/backend.hcl"
terraform -chdir=terraform/aws/cluster plan -input=false "-var-file=$privateDir/cluster.tfvars.json" "-out=$privateDir/cluster.tfplan"
terraform -chdir=terraform/aws/cluster show "$privateDir/cluster.tfplan"
# STOP for plan approval.
.\scripts\aws-setup.ps1 -Mode Guard -Stage cluster
terraform -chdir=terraform/aws/cluster apply "$privateDir/cluster.tfplan"
.\scripts\aws-setup.ps1 -Mode Connect
```

Bash:

```bash
bash scripts/aws-setup.sh --mode guard --stage cluster
terraform -chdir=terraform/aws/cluster init -input=false -backend-config="$private_dir/backend.hcl"
terraform -chdir=terraform/aws/cluster plan -input=false -var-file="$private_dir/cluster.tfvars.json" -out="$private_dir/cluster.tfplan"
terraform -chdir=terraform/aws/cluster show "$private_dir/cluster.tfplan"
# STOP for plan approval.
bash scripts/aws-setup.sh --mode guard --stage cluster
terraform -chdir=terraform/aws/cluster apply "$private_dir/cluster.tfplan"
bash scripts/aws-setup.sh --mode connect
```

Connect constructs only `.local/aws/<cluster-name>/<cluster-name>.kubeconfig`, never the default kubeconfig,
and refuses an existing dedicated file. Existing contexts remain untouched.
Record the resulting node AMI release, add-on versions and real timing.
Acceptance: one Ready node, compatible CNI/CoreDNS/kube-proxy and healthy EBS CSI controller/node components;
confirm no NAT gateway and that the API CIDR restriction is effective.

### 3. Platform

PowerShell:

```powershell
.\scripts\aws-setup.ps1 -Mode Guard -Stage platform
terraform -chdir=terraform/aws/platform init -input=false "-backend-config=$privateDir/backend.hcl"
terraform -chdir=terraform/aws/platform plan -input=false "-var-file=$privateDir/platform.tfvars.json" "-out=$privateDir/platform.tfplan"
terraform -chdir=terraform/aws/platform show "$privateDir/platform.tfplan"
# STOP for plan approval.
.\scripts\aws-setup.ps1 -Mode Guard -Stage platform
terraform -chdir=terraform/aws/platform apply "$privateDir/platform.tfplan"
.\scripts\aws-verify.ps1
```

Bash:

```bash
bash scripts/aws-setup.sh --mode guard --stage platform
terraform -chdir=terraform/aws/platform init -input=false -backend-config="$private_dir/backend.hcl"
terraform -chdir=terraform/aws/platform plan -input=false -var-file="$private_dir/platform.tfvars.json" -out="$private_dir/platform.tfplan"
terraform -chdir=terraform/aws/platform show "$private_dir/platform.tfplan"
# STOP for plan approval.
bash scripts/aws-setup.sh --mode guard --stage platform
terraform -chdir=terraform/aws/platform apply "$private_dir/platform.tfplan"
bash scripts/aws-verify.sh
```

The AWS platform reads only the separate AWS cluster state and checks cluster ARN, account, VPC, tags and readiness.
Helm/Kubernetes providers use the EKS endpoint/CA and short-lived `aws eks get-token` with explicit profile/region.
No static Kubernetes token is stored.
MySQL waits on the EBS StorageClass. Monitoring CRDs precede application/exporter ServiceMonitors.
Both datasource URLs and the existing pod hardening/probes are inherited unchanged.

The verification scripts check workload readiness, internal Services and encrypted EBS configuration.
They do not claim HTTP, write/persistence or dashboard acceptance; complete those checks below.

### 4. Functionality, monitoring and public endpoint

For PowerShell, define a helper in the current session:

```powershell
$kube = Join-Path $privateDir "$($config.cluster_name).kubeconfig"
$kubectl = 'kubectl'
if (Test-Path .local/bin/kubectl.exe) { $kubectl = (Resolve-Path .local/bin/kubectl.exe).Path }
function k { & $kubectl --kubeconfig $kube --context $config.cluster_name --namespace crewmeister @args; if ($LASTEXITCODE -ne 0) { throw 'kubectl failed' } }
k port-forward --address 127.0.0.1 service/crewmeister-app 18080:8080
```

Bash equivalent:

```bash
cluster_name="$(jq -r .cluster_name .local/aws/deployment.json)"
kube="$private_dir/$cluster_name.kubeconfig"
export PATH="$PWD/.local/bin:$PATH"
k() { kubectl --kubeconfig "$kube" --context "$cluster_name" --namespace crewmeister "$@"; }
k port-forward --address 127.0.0.1 service/crewmeister-app 18080:8080
```

Keep each forward in its own terminal with the same variables/helper. API checks in another terminal:

```powershell
Invoke-RestMethod 'http://127.0.0.1:18080/user?id=1'
Invoke-RestMethod -Method Post -ContentType 'application/json' -Body '{"name":"aws-demo"}' 'http://127.0.0.1:18080/user'
Invoke-RestMethod 'http://127.0.0.1:18080/actuator/health'
```

```bash
curl --fail 'http://127.0.0.1:18080/user?id=1'
curl --fail -H 'Content-Type: application/json' --data '{"name":"aws-demo"}' http://127.0.0.1:18080/user
curl --fail http://127.0.0.1:18080/actuator/health
```

For persistence acceptance, record the test user's actual ID from MySQL using authenticated in-pod SQL
(the existing Kind verification scripts illustrate using the pod's environment without printing the password).
Do not guess an ID. After explicit approval of the brief demo interruption, delete only `crewmeister-mysql-0`,
wait for its StatefulSet rollout, reconnect the application forward if necessary, and GET the recorded ID.
Confirm the same PVC/volume remains and the test record survives. This check passed during the Windows AWS validation.

Monitoring forwards:

```text
k port-forward --address 127.0.0.1 service/crewmeister-grafana 13000:80
k port-forward --address 127.0.0.1 service/crewmeister-monitoring-prometheus 19090:9090
```

Open Grafana at http://127.0.0.1:13000 and Prometheus at http://127.0.0.1:19090.
Grafana uses generated credentials in Kubernetes Secret `crewmeister-grafana-admin`; retrieve privately through an approved client,
never print the password into terminal output or recordings. There is no admin/admin default.
Confirm application and MySQL exporter targets are UP and the Crewmeister dashboard has data.

Enable ingress last using a **new reviewed platform plan** with `-var=enable_public_ingress=true`,
then apply only that approved saved plan. Initial private inputs are false for safety; after successful acceptance,
record the approved enabled state in your ignored deployment/platform inputs so subsequent plans preserve it.
The committed example and Terraform defaults remain false.
The chosen client CIDRs constrain the ALB security group.
To make only the application API reachable worldwide, explicitly set `allow_unrestricted_api=true` and
`client_access_cidrs=["0.0.0.0/0"]` in the ignored deployment configuration and generated platform inputs.
Review/apply a platform plan changing only the Ingress annotation. This never changes `api_access_cidrs`:
the EKS management endpoint remains restricted to administrator /32 addresses, and the ALB still rejects every
path except `/user`. The API has no authentication; public HTTP access is for temporary dummy-data demonstrations.
Without a certificate this is restricted HTTP for dummy demonstration data, not secure transport.
For HTTPS, supply an existing Stockholm ACM certificate and use its matching domain pointed at the ALB;
the configuration does not create DNS or a certificate. An ALB hostname will not match your custom-domain certificate.

Get the hostname with `terraform -chdir=terraform/aws/platform output -raw api_hostname`.
Acceptance from an allowed client: GET and POST `/user` work; `/user?id=1` works;
`/`, `/user/other`, `/actuator/health`, `/actuator/prometheus` and Grafana paths return 404.
In the default CIDR-restricted mode, the listener must be unreachable from an unapproved source.
With explicit worldwide access enabled, `/user` is reachable from any IPv4 source; the same path filtering still applies.
ALB internal health probes may reach readiness; that must not create a public Actuator route.
Existing application vulnerabilities remain unresolved: see [validation](validation.md) and the README limitations.
Use dummy data and keep exposure brief.

## Controlled teardown — separate destruction approval required

Do not run teardown during Phase B. Never use the Kind down scripts for AWS.
These steps delete demonstration data. Review account, region, state ownership and each destroy plan first.

1. Run the AWS identity/backend guard for platform.
2. Create a saved platform plan with `-var=enable_public_ingress=false`; review and obtain approval, then apply that plan.
   Wait until the Ingress, ALB, listener rules and target groups are actually removed **before** removing the controller.
3. Record the MySQL PVC, PV and EBS volume IDs privately. Create/review the platform destroy plan:
   `terraform -chdir=terraform/aws/platform plan -destroy -input=false -var-file=<absolute-platform.tfvars.json> -out=<absolute-platform-down.tfplan>`.
   Obtain separate approval, rerun the platform guard, then apply that saved destroy plan.
4. Confirm namespace removal has deleted retained PVCs and that the recorded data EBS volume is gone.
   If the namespace/PVC is stuck, investigate with the CSI driver and node still running; never force-remove finalizers to hide an EBS leak.
5. Run `aws-down.ps1 -Mode CheckClusterTeardown` or `bash scripts/aws-down.sh --mode check-cluster-teardown`.
   This gate refuses remaining project namespace/controller, tagged ALB/target groups or CSI data volumes.
6. Create/review the cluster destroy plan with the same pattern:
   `terraform -chdir=terraform/aws/cluster plan -destroy -input=false -var-file=<absolute-cluster.tfvars.json> -out=<absolute-cluster-down.tfplan>`.
   Obtain approval, rerun the cluster guard and teardown gate, then apply only that reviewed cluster-down plan.
7. Run `aws-down.ps1` or `bash scripts/aws-down.sh` for a read-only leftover audit.
   Both scripts require the same private config and default to audit; neither destroys resources.

PowerShell uses `$privateDir/platform.tfvars.json` and `$privateDir/cluster.tfvars.json`;
Bash uses `$private_dir/...` for the absolute paths above. Each saved plan belongs to its matching root.
Never execute a platform plan from the cluster root or reuse a plan after configuration/identity changes.

Check EKS/nodegroups, EC2/ASGs, EBS/root volumes/snapshots, load balancers/target groups, NAT gateways, Elastic IPs,
VPC ENIs/security groups and any CloudWatch logs. Use both ownership tags **and recorded state/resource IDs**:
tag-based discovery alone cannot prove there are no untagged leftovers.
The root has no configured NAT or paid control-plane log export, but still audit for unexpected resources.
Do not delete the default VPC, pre-existing IAM roles or unrelated resources.
A failed audit command is an incomplete audit, not a pass.

Keep the S3 backend and encrypted bootstrap backup after compute teardown.
Optional backend cleanup requires separate approval, proof that both AWS states are empty and recoverable backups.
Its deletion policy and Terraform protection must be deliberately reviewed/removed before purging versions or destroying bootstrap.
There is no automatic purge command. Do not delete a backend while infrastructure depends on it.

## Evidence and remaining validation

Phase B checks: Terraform formatting and backend-disabled validation of all three new roots;
application Helm lint/render; MySQL/monitoring/controller chart rendering; PowerShell parsing and Bash syntax;
offline regression checks for profile/CIDR/account rejection and private-file overwrite protection;
local Git diff/secret review. See the final Phase B report for actual executed results.

Live Windows checks passed: the existing partial deployment was completed using reviewed plans; one node and the
Pod Identity/CNI/EBS add-ons became ready; the public GHCR image ran; encrypted gp3 storage bound; GET/POST and
health/metrics worked; the same data/PVC survived MySQL pod recreation; Prometheus application/exporter targets
were UP; Grafana was healthy and its dashboard was provisioned. Test rows and temporary port-forwards were removed.

This was recovery and completion of an existing AWS deployment, not a fresh-account/fresh-clone AWS lifecycle test.
Node Kubernetes was 1.36.5 and the managed node release was 1.36.5-20261031.
The tested application image tag was `c6a1738c336e004f117af27cd52773e09aed0ffb`.
One successful Flyway migration was present in the database. Final cluster and platform plans both reported no changes.
Account restrictions allowed Pod Identity, managed nodes and encrypted EBS without an account upgrade.
The account still reported Free plan / Active after deployment.
This does not establish eligibility for other accounts or a guarantee about future policy changes.

Public API acceptance also passed: the ALB target was healthy; GET/POST and persisted readback worked through its
hostname; query strings were forwarded; `/`, `/user/other`, Actuator health/metrics and Grafana login/health paths
returned 404. The listener's default action was verified as fixed-response 404 and its security groups allowed only
the initially approved client /32. A request from a second, unapproved source IP was not performed; CIDR isolation was checked
through the actual AWS security-group configuration. HTTP is unencrypted and intended only for dummy demo data.

The owner subsequently approved worldwide API access. With `allow_unrestricted_api=true`, the ALB client CIDR
was changed to `0.0.0.0/0`; public GET/POST/readback and the management-path 404 checks passed again.
The EKS management endpoint remained restricted to its administrator /32. Worldwide access was checked through
the actual ALB security-group configuration; an independent second-network HTTP request was not performed.

Pending: complete teardown/leftover audit and a full Bash deployment.
PowerShell 5.1 live checks passed; Git Bash checks were static/offline only. WSL, native Linux and macOS cloud
lifecycle tests have not been run.

Record a short YouTube demonstration after live acceptance:
AWS resources and Terraform outputs; node/pod/Helm readiness; GET/POST; pod-recreation persistence;
Prometheus targets and Grafana dashboard; then teardown and the leftover audit.
Hide account/session details as appropriate, all passwords, Secret contents, state and private plans.
Do not claim Windows/Linux/macOS cloud deployment success until each has actually been exercised.

## Recovering an interrupted apply

Terraform preserves successfully created resources in state when a later operation fails.
An earlier saved plan is then stale: keep the state, stop any concurrent Terraform operation, and generate a new
uniquely named plan against the same AWS root and private inputs. Review remaining additions and any unexpected
changes before applying. Do not delete state, bypass the lock or recreate the whole environment to recover.

The EKS public API is restricted to a specific IPv4 /32. If your ISP/VPN changes that address, update the private
deployment configuration and generated cluster/platform CIDR inputs, preserving backups, then review/apply a
cluster plan that updates only the API CIDR. Update the ALB's client CIDR through a reviewed platform plan too
if ingress is enabled in restricted-client mode. Never open the Kubernetes management endpoint to 0.0.0.0/0.
Worldwide application API access is a separate explicit opt-in as described above.
