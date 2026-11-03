# Offline regression checks: every external tool/AWS call is stubbed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$sourceRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Isolate metadata too: these checks must also run after a real S3 backend has
# been initialized in the checkout, without consulting its account settings.
$repo = Join-Path $sourceRepo ('.local/aws-validation/ps-guards-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $repo 'scripts') -Force | Out-Null
foreach ($scriptName in @('aws-common.ps1','aws-setup.ps1')) {
    Copy-Item -LiteralPath (Join-Path $sourceRepo "scripts/$scriptName") -Destination (Join-Path $repo "scripts/$scriptName")
}
$name = "crewmeister-aws-tests-$PID"
$relative = ".local/aws/$name-input.json"
$fixture = Join-Path $repo $relative
$privateDir = Join-Path $repo ".local/aws/$name"
if ((Test-Path -LiteralPath $fixture) -or (Test-Path -LiteralPath $privateDir)) { throw 'Test fixture already exists; refusing to overwrite.' }
New-Item -ItemType Directory -Path (Split-Path -Parent $fixture) -Force | Out-Null
$global:AwsGuardAccount = '111122223333'
$global:AwsGuardCalls = 0
function aws {
    $global:LASTEXITCODE = 0
    if ($args -contains '--version') { return 'aws-cli/2.38.4 test-only' }
    $global:AwsGuardCalls++
    if ($args[0] -eq 'sts' -and $args[1] -eq 'get-caller-identity') { return ('{"Account":"' + $global:AwsGuardAccount + '","Arn":"arn:aws:sts::111122223333:assumed-role/Testing/session"}') }
    if ($args[0] -eq 'iam' -and $args[1] -eq 'get-role') { return '{"Role":{"Arn":"arn:aws:iam::111122223333:role/Testing"}}' }
    throw 'Unexpected AWS operation in offline test.'
}
function terraform { $global:LASTEXITCODE=0; if ($args[0] -eq 'version') { return '{"terraform_version":"1.15.8"}' }; throw 'Unexpected Terraform operation.' }
function helm { $global:LASTEXITCODE=0; if ($args[0] -eq 'version') { return 'v4.3.1+test' }; throw 'Unexpected Helm operation.' }
function kubectl { $global:LASTEXITCODE=0; if ($args[0] -eq 'version') { return '{"clientVersion":{"gitVersion":"v1.36.4"}}' }; throw 'Unexpected Kubernetes operation.' }
$config = @{
    aws_profile='testing'; aws_region='eu-north-1'; expected_account_id='111122223333'
    cluster_name=$name; state_bucket='crewmeister-offline-test'
    operator_role_arn='arn:aws:iam::111122223333:role/Testing'
    api_access_cidrs=@('8.8.8.8/32'); client_access_cidrs=@('8.8.8.8/32')
    image_repository='ghcr.io/example/assessment'; image_tag=('1' * 40)
    enable_public_ingress=$false; certificate_arn=$null
}
function Save-Fixture { [IO.File]::WriteAllText($fixture, ($config | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false))) }
function Expect-Rejected {
    param([string]$Pattern)
    $rejected = $false
    try { & "$repo/scripts/aws-setup.ps1" -Mode Prepare -ConfigPath $relative }
    catch { if ($_.Exception.Message -notmatch $Pattern) { throw }; $rejected = $true }
    if (-not $rejected) { throw "Expected rejection: $Pattern" }
}
$config.aws_profile='default'; Save-Fixture
Expect-Rejected 'non-default'
if ($global:AwsGuardCalls -ne 0) { throw 'Default profile reached AWS.' }
$config.aws_profile='testing'; $config.api_access_cidrs=@('0.0.0.0/0'); Save-Fixture
Expect-Rejected 'CIDR|/24'
if ($global:AwsGuardCalls -ne 0) { throw 'Open API CIDR reached AWS.' }
$config.api_access_cidrs=@('8.8.8.8/32'); Save-Fixture
$global:AwsGuardAccount='999999999999'
Expect-Rejected 'account mismatch'
if (Test-Path -LiteralPath $privateDir) { throw 'Wrong-account preparation wrote files.' }
$global:AwsGuardAccount='111122223333'
& "$repo/scripts/aws-setup.ps1" -Mode Prepare -ConfigPath $relative
$before = Get-FileHash -LiteralPath (Join-Path $privateDir 'cluster.tfvars.json')
Expect-Rejected 'already exist'
$after = Get-FileHash -LiteralPath (Join-Path $privateDir 'cluster.tfvars.json')
if ($before.Hash -ne $after.Hash) { throw 'Existing private inputs were overwritten.' }
$generated = Get-Content -LiteralPath (Join-Path $privateDir 'backend.hcl') -Raw
if ($generated -notmatch 'allowed_account_ids' -or $generated -match 'access_key|secret_key|token') { throw 'Unsafe generated backend configuration.' }
Write-Host 'PASS: default profile, world-open CIDR, wrong account, private preparation and overwrite protection (offline stubs).'
