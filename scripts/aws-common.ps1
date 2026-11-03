# Shared only by the AWS scripts; never sourced by the Kind lifecycle.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:AwsRepoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-AwsTool {
    param([string]$Name)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    # Use the repository's pinned kubectl, as the Kind scripts do. Keep test
    # functions available for offline safety checks; do not change session PATH.
    if ($Name -eq 'kubectl' -and (-not $command -or $command.CommandType -ne 'Function')) {
        foreach ($candidate in @('kubectl.exe','kubectl')) {
            $localTool = Join-Path $script:AwsRepoRoot ".local/bin/$candidate"
            if (Test-Path -LiteralPath $localTool -PathType Leaf) { return $localTool }
        }
    }
    if (-not $command) { throw "Missing prerequisite: $Name." }
    return $Name
}
function Invoke-AwsChecked {
    param([string]$Program, [string[]]$CommandArgs)
    $Program = Resolve-AwsTool $Program
    $ErrorActionPreference = 'Continue'
    $result = & $Program @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "$Program failed (exit $LASTEXITCODE)." }
    return $result
}
function Write-AwsPrivateFile {
    param([string]$Path, [string]$Content)
    # CreateNew also rejects races; UTF-8 without BOM works on PowerShell 5.1.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Content + "`n")
        $stream.Write($bytes, 0, $bytes.Length)
    } finally { $stream.Dispose() }
}
function Assert-AwsTools {
    if ($env:TF_WORKSPACE -and $env:TF_WORKSPACE -ne 'default') { throw 'AWS roots require the default workspace; isolation uses separate roots and keys.' }
    foreach ($stage in @('bootstrap','cluster','platform')) {
        $workspaceFile = Join-Path $script:AwsRepoRoot "terraform/aws/$stage/.terraform/environment"
        if ((Test-Path -LiteralPath $workspaceFile) -and (Get-Content -LiteralPath $workspaceFile -Raw).Trim() -ne 'default') { throw "Unexpected workspace in AWS $stage root." }
    }
    foreach ($tool in @('aws', 'terraform', 'helm', 'kubectl')) {
        $null = Resolve-AwsTool $tool
    }
    $version = Invoke-AwsChecked terraform @('version', '-json') | ConvertFrom-Json
    if ($version.terraform_version -ne '1.15.8') { throw 'Terraform 1.15.8 is required.' }
    if ((Invoke-AwsChecked aws @('--version')) -notmatch '^aws-cli/2\.') { throw 'AWS CLI v2 is required.' }
    if ((Invoke-AwsChecked helm @('version', '--short')) -notmatch '^v4\.3\.1\+') { throw 'Helm 4.3.1 is required.' }
    $kubectlVersion = Invoke-AwsChecked kubectl @('version', '--client', '--output=json') | ConvertFrom-Json
    if ($kubectlVersion.clientVersion.gitVersion -notmatch '^v1\.(35|36|37)\.') { throw 'kubectl 1.35-1.37 is required.' }
}
function Read-AwsConfig {
    param([string]$ConfigPath)
    $fullPath = [IO.Path]::GetFullPath((Join-Path $script:AwsRepoRoot $ConfigPath))
    $privateRoot = [IO.Path]::GetFullPath((Join-Path $script:AwsRepoRoot '.local/aws')) + [IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($privateRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Private configuration must be inside .local/aws/.' }
    $script:AwsConfig = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    $c = $script:AwsConfig
    if ($c.aws_profile -eq 'default' -or $c.aws_profile -notmatch '^[A-Za-z0-9_-]+$') { throw 'Supply an explicit non-default profile.' }
    if ($c.aws_region -ne 'eu-north-1') { throw 'Only the reviewed eu-north-1 region is accepted.' }
    if ($c.expected_account_id -notmatch '^[0-9]{12}$') { throw 'Supply your independently confirmed account ID.' }
    if ($c.cluster_name -notmatch '^crewmeister-aws(-[a-z0-9-]+)?$' -or $c.cluster_name.Length -gt 40) { throw 'Invalid AWS deployment name.' }
    if ($c.state_bucket -notmatch '^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$') { throw 'Supply a valid private backend bucket name.' }
    if ($c.operator_role_arn -notmatch "^arn:aws:iam::$($c.expected_account_id):role/.+$") { throw 'Supply an IAM role ARN in your expected account.' }
    if ($c.image_repository -notmatch '^ghcr.io/[a-z0-9._/-]+$' -or $c.image_tag -notmatch '^[0-9a-f]{40}$' -or $c.image_tag -eq ('0' * 40)) { throw 'Supply a public GHCR repository and a real full commit SHA.' }
    foreach ($field in @('api_access_cidrs', 'client_access_cidrs')) {
        if ($c.$field -isnot [Array]) { throw "$field must be a JSON array." }
        $cidrs = @($c.$field)
        if ($cidrs.Count -eq 0) { throw "$field must not be empty." }
        foreach ($cidr in $cidrs) {
            if ($cidr -notmatch '^(\d{1,3}\.){3}\d{1,3}/(2[4-9]|3[0-2])$') { throw "$field requires IPv4 /24 or narrower." }
            $ip = $null
            if (-not [Net.IPAddress]::TryParse(($cidr -split '/')[0], [ref]$ip)) { throw "Invalid CIDR in $field." }
            if ($cidr -like '203.0.113.*' -or $cidr -like '198.51.100.*' -or $cidr -like '192.0.2.*') { throw 'Replace documentation CIDRs with your approved public IP.' }
        }
    }
    if ($c.enable_public_ingress -isnot [bool]) { throw 'enable_public_ingress must be a JSON boolean.' }
    if ($null -ne $c.certificate_arn -and $c.certificate_arn -notmatch "^arn:aws:acm:eu-north-1:$($c.expected_account_id):certificate/[a-f0-9-]+$") { throw 'Certificate must belong to the approved account and region.' }
    $script:AwsPrivateDir = Join-Path $script:AwsRepoRoot ".local/aws/$($c.cluster_name)"
    $script:AwsKubeconfig = Join-Path $script:AwsPrivateDir "$($c.cluster_name).kubeconfig"
    foreach ($stage in @('cluster','platform')) {
        $metadataPath = Join-Path $script:AwsRepoRoot "terraform/aws/$stage/.terraform/terraform.tfstate"
        if (Test-Path -LiteralPath $metadataPath) {
            $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
            $backend = $metadata.backend
            if ($backend.type -ne 's3' -or $backend.config.bucket -ne $c.state_bucket -or $backend.config.region -ne $c.aws_region -or $backend.config.profile -ne $c.aws_profile -or $backend.config.key -ne "crewmeister/aws/$stage.tfstate" -or @($backend.config.allowed_account_ids) -notcontains $c.expected_account_id -or $backend.config.use_lockfile -ne $true) { throw "AWS $stage backend metadata does not match private configuration." }
        }
    }
}
function Invoke-AwsRead {
    param([string[]]$CommandArgs)
    $result = Invoke-AwsChecked aws ($CommandArgs + @('--profile', $script:AwsConfig.aws_profile, '--region', $script:AwsConfig.aws_region, '--output', 'json', '--no-cli-pager'))
    if ($result) { return ($result | ConvertFrom-Json) }
}
function Assert-AwsIdentity {
    $c = $script:AwsConfig
    $identity = Invoke-AwsRead @('sts', 'get-caller-identity')
    if ($identity.Account -ne $c.expected_account_id -or $identity.Arn -match ':root$') { throw 'AWS account mismatch or root identity; stopped.' }
    $roleName = ($c.operator_role_arn -split '/')[-1]
    $role = Invoke-AwsRead @('iam', 'get-role', '--role-name', $roleName)
    if ($role.Role.Arn -ne $c.operator_role_arn -or $identity.Arn -notlike "arn:aws:sts::$($c.expected_account_id):assumed-role/$roleName/*") { throw 'Authenticated operator role does not match private configuration.' }
}
function Assert-AwsBackend {
    $c = $script:AwsConfig
    $bucketArgs = @('--bucket', $c.state_bucket, '--expected-bucket-owner', $c.expected_account_id)
    $null = Invoke-AwsRead (@('s3api', 'head-bucket') + $bucketArgs)
    $location = Invoke-AwsRead (@('s3api', 'get-bucket-location') + $bucketArgs)
    $versioning = Invoke-AwsRead (@('s3api', 'get-bucket-versioning') + $bucketArgs)
    $encryption = Invoke-AwsRead (@('s3api', 'get-bucket-encryption') + $bucketArgs)
    $public = Invoke-AwsRead (@('s3api', 'get-public-access-block') + $bucketArgs)
    $tags = Invoke-AwsRead (@('s3api', 'get-bucket-tagging') + $bucketArgs)
    $policy = Invoke-AwsRead (@('s3api', 'get-bucket-policy') + $bucketArgs)
    $statements = ($policy.Policy | ConvertFrom-Json).Statement
    if ($location.LocationConstraint -ne $c.aws_region -or $versioning.Status -ne 'Enabled') { throw 'Backend region/versioning mismatch.' }
    if ($encryption.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm -ne 'AES256') { throw 'Backend encryption mismatch.' }
    foreach ($flag in @('BlockPublicAcls','IgnorePublicAcls','BlockPublicPolicy','RestrictPublicBuckets')) {
        if ($public.PublicAccessBlockConfiguration.$flag -ne $true) { throw 'Backend public access protection missing.' }
    }
    if (@($tags.TagSet | Where-Object { $_.Key -eq 'Project' -and $_.Value -eq $c.cluster_name }).Count -ne 1) { throw 'Backend ownership tag mismatch.' }
    foreach ($sid in @('RequireTLS','RestrictPrincipals','ProtectBucketAndStateVersions','ProtectCurrentStates')) {
        if (@($statements | Where-Object { $_.Sid -eq $sid -and $_.Effect -eq 'Deny' }).Count -ne 1) { throw "Backend protection missing: $sid." }
    }
}
function Assert-AwsCluster {
    $c = $script:AwsConfig
    $cluster = (Invoke-AwsRead @('eks', 'describe-cluster', '--name', $c.cluster_name)).cluster
    if ($cluster.arn -ne "arn:aws:eks:$($c.aws_region):$($c.expected_account_id):cluster/$($c.cluster_name)" -or $cluster.status -ne 'ACTIVE' -or $cluster.tags.Project -ne $c.cluster_name -or $cluster.version -ne '1.36') { throw 'Cluster identity, ownership, readiness or version mismatch.' }
    $vpc = (Invoke-AwsRead @('ec2', 'describe-vpcs', '--vpc-ids', $cluster.resourcesVpcConfig.vpcId)).Vpcs[0]
    if ($vpc.IsDefault -or @($vpc.Tags | Where-Object { $_.Key -eq 'Project' -and $_.Value -eq $c.cluster_name }).Count -ne 1) { throw 'Cluster VPC ownership mismatch.' }
    return $cluster
}
function Invoke-AwsKube {
    param([string[]]$CommandArgs)
    return Invoke-AwsChecked kubectl (@('--kubeconfig', $script:AwsKubeconfig, '--context', $script:AwsConfig.cluster_name, '--namespace', 'crewmeister') + $CommandArgs)
}
function Assert-AwsKubeconfig {
    param($Cluster)
    if (-not (Test-Path -LiteralPath $script:AwsKubeconfig -PathType Leaf)) { throw 'Dedicated kubeconfig missing; run setup -Mode Connect after approved deployment.' }
    $view = Invoke-AwsKube @('config', 'view', '--raw', '--minify', '--output=json') | ConvertFrom-Json
    $entry = $view.clusters[0].cluster
    if ($entry.server -ne $Cluster.endpoint -or $entry.'certificate-authority-data' -ne $Cluster.certificateAuthority.data) { throw 'Dedicated kubeconfig endpoint or CA does not match AWS.' }
    $exec = $view.users[0].user.exec
    $expectedArgs = @('eks','get-token','--cluster-name',$script:AwsConfig.cluster_name,'--profile',$script:AwsConfig.aws_profile,'--region',$script:AwsConfig.aws_region)
    if ($exec.command -ne 'aws' -or (($exec.args -join '|') -ne ($expectedArgs -join '|'))) { throw 'Kubeconfig credential command mismatch; regenerate the dedicated file safely.' }
}
function Invoke-AwsStaticValidation {
    Assert-AwsTools
    foreach ($stage in @('bootstrap','cluster','platform')) {
        $root = Join-Path $script:AwsRepoRoot "terraform/aws/$stage"
        Invoke-AwsChecked terraform @("-chdir=$root", 'fmt', '-check') | Out-Host
        Invoke-AwsChecked terraform @("-chdir=$root", 'init', '-backend=false', '-input=false', '-lockfile=readonly') | Out-Host
        Invoke-AwsChecked terraform @("-chdir=$root", 'validate') | Out-Host
    }
    $chart = Join-Path $script:AwsRepoRoot 'helm/crewmeister-app'
    Invoke-AwsChecked helm @('lint', $chart, '--values', "$chart/values-aws.yaml", '--strict') | Out-Host
    $null = Invoke-AwsChecked helm @('template', 'crewmeister-app', $chart, '--namespace', 'crewmeister', '--values', "$chart/values-aws.yaml")
    Write-Host 'Static validation passed. No backend, Kubernetes or AWS resource changes were requested.'
}
