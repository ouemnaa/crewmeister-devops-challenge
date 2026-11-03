[CmdletBinding()]
param(
    [ValidateSet('Validate','Prepare','Connect','Guard')][string]$Mode = 'Validate',
    [ValidateSet('bootstrap','cluster','platform')][string]$Stage = 'bootstrap',
    [string]$ConfigPath = '.local/aws/deployment.json'
)
. "$PSScriptRoot/aws-common.ps1"
if ($Mode -eq 'Validate') { Invoke-AwsStaticValidation; return }
Assert-AwsTools
Read-AwsConfig $ConfigPath
Assert-AwsIdentity
$c = $script:AwsConfig
if ($Mode -eq 'Guard') {
    if ($Stage -eq 'bootstrap') {
        $bootstrapState = Join-Path $script:AwsRepoRoot '.local/aws/bootstrap.tfstate'
        if (Test-Path -LiteralPath $bootstrapState) {
            $state = Get-Content -LiteralPath $bootstrapState -Raw | ConvertFrom-Json
            $buckets = @($state.resources | Where-Object { $_.mode -eq 'managed' -and $_.type -eq 'aws_s3_bucket' -and $_.name -eq 'state' })
            if ($buckets.Count -ne 1 -or @($buckets[0].instances).Count -ne 1 -or $buckets[0].instances[0].attributes.bucket -ne $c.state_bucket) { throw 'Existing bootstrap state does not match the selected bucket; recovery review is required.' }
            Assert-AwsBackend
        }
    }
    if ($Stage -ne 'bootstrap') { Assert-AwsBackend }
    if ($Stage -eq 'platform') {
        $cluster = Assert-AwsCluster
        Assert-AwsKubeconfig $cluster
        $null = Invoke-AwsKube @('--namespace','kube-system','rollout','status','deployment/ebs-csi-controller','--timeout=180s')
    }
    Write-Host "Identity and $Stage prerequisites checked. No Terraform operation was performed; review the separate plan and obtain approval."
    return
}
if ($Mode -eq 'Connect') {
    Assert-AwsBackend
    $cluster = Assert-AwsCluster
    if (Test-Path -LiteralPath $script:AwsKubeconfig) { throw 'Refusing to overwrite an existing dedicated kubeconfig. Verify it or archive it yourself.' }
    New-Item -ItemType Directory -Path $script:AwsPrivateDir -Force | Out-Null
    # Construct only this cluster's config; no update to ~/.kube/config.
    $kubeconfig = @{
        apiVersion = 'v1'; kind = 'Config'; 'current-context' = $c.cluster_name
        clusters = @(@{name=$c.cluster_name; cluster=@{server=$cluster.endpoint; 'certificate-authority-data'=$cluster.certificateAuthority.data}})
        contexts = @(@{name=$c.cluster_name; context=@{cluster=$c.cluster_name; user=$c.cluster_name}})
        users = @(@{name=$c.cluster_name; user=@{exec=@{
            apiVersion='client.authentication.k8s.io/v1beta1'; command='aws'; interactiveMode='Never'
            args=@('eks','get-token','--cluster-name',$c.cluster_name,'--profile',$c.aws_profile,'--region',$c.aws_region)
        }}})
    }
    Write-AwsPrivateFile $script:AwsKubeconfig ($kubeconfig | ConvertTo-Json -Depth 12)
    Assert-AwsKubeconfig $cluster
    Write-Host "Created dedicated kubeconfig: $script:AwsKubeconfig"
    return
}
# Preparation creates only new private configuration; never state or plans.
$paths = @('bootstrap.tfvars.json','cluster.tfvars.json','platform.tfvars.json','backend.hcl') | ForEach-Object { Join-Path $script:AwsPrivateDir $_ }
foreach ($path in $paths) { if (Test-Path -LiteralPath $path) { throw 'Preparation files already exist; review/archive them manually. Nothing was overwritten.' } }
New-Item -ItemType Directory -Path $script:AwsPrivateDir -Force | Out-Null
$common = @{aws_profile=$c.aws_profile; aws_region=$c.aws_region; expected_account_id=$c.expected_account_id; cluster_name=$c.cluster_name}
$bootstrap = $common.Clone(); $bootstrap.state_bucket=$c.state_bucket; $bootstrap.deployment_principal_arn=$c.operator_role_arn
$cluster = $common.Clone(); $cluster.operator_role_arn=$c.operator_role_arn; $cluster.api_access_cidrs=@($c.api_access_cidrs)
$platform = $common.Clone()
foreach ($field in @('state_bucket','image_repository','image_tag','client_access_cidrs','enable_public_ingress','certificate_arn')) { $platform[$field]=$c.$field }
Write-AwsPrivateFile $paths[0] ($bootstrap | ConvertTo-Json -Depth 5)
Write-AwsPrivateFile $paths[1] ($cluster | ConvertTo-Json -Depth 5)
Write-AwsPrivateFile $paths[2] ($platform | ConvertTo-Json -Depth 5)
$backend = @(
    "bucket = $($c.state_bucket | ConvertTo-Json -Compress)"
    "region = $($c.aws_region | ConvertTo-Json -Compress)"
    "profile = $($c.aws_profile | ConvertTo-Json -Compress)"
    "allowed_account_ids = [$($c.expected_account_id | ConvertTo-Json -Compress)]"
    'workspace_key_prefix = "disabled-workspaces"'
)
Write-AwsPrivateFile $paths[3] ($backend -join "`n")
Write-Host 'Private inputs prepared. No backend was initialized and no plan/apply was run.'
Write-Host 'Next: review docs/aws-deployment.md and obtain separate Phase C approval.'
