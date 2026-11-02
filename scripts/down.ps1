[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$previousPath = $env:PATH
$previousKubeconfig = $env:KUBECONFIG
$previousProvider = $env:KIND_EXPERIMENTAL_PROVIDER
$kubeconfig = Join-Path $repoRoot '.local/crewmeister.kubeconfig'
$runId = [guid]::NewGuid().ToString('N')
$platformPlan = "../../.local/down-$runId-platform.tfplan"
$clusterPlan = "../../.local/down-$runId-cluster.tfplan"
Push-Location $repoRoot

function Invoke-Checked {
    param([string]$Program, [string[]]$CommandArgs)
    & $Program @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE." }
}

function Assert-State {
    param([string]$Stage, [string]$Expression)
    $result = $Expression | & terraform "-chdir=terraform/$Stage" console
    if ($LASTEXITCODE -ne 0 -or ($result | Out-String).Trim() -ne 'true') {
        throw "Refusing teardown: $Stage state does not match the project identity."
    }
}

try {
    if (Test-Path -LiteralPath .local/bin -PathType Container) {
        $env:PATH = (Join-Path $repoRoot '.local/bin') + [System.IO.Path]::PathSeparator + $env:PATH
    }
    foreach ($tool in @('docker', 'terraform', 'kind', 'kubectl')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required tool is missing: $tool." }
    }
    $env:KUBECONFIG = $kubeconfig
    $env:KIND_EXPERIMENTAL_PROVIDER = 'docker'
    $clusterResources = @()
    $platformResources = @()
    foreach ($stage in @('cluster', 'platform')) {
        if (Test-Path -LiteralPath "terraform/$stage/terraform.tfstate") {
            Invoke-Checked terraform @("-chdir=terraform/$stage", 'init', '-input=false', '-lockfile=readonly') | Out-Null
            $resources = @(Invoke-Checked terraform @("-chdir=terraform/$stage", 'state', 'list'))
            if ($stage -eq 'cluster') { $clusterResources = $resources } else { $platformResources = $resources }
        }
    }
    $clusters = @(Invoke-Checked kind @('get', 'clusters'))
    $projectNodes = @(Invoke-Checked docker @('ps', '-a', '--filter', 'label=io.x-k8s.kind.cluster=crewmeister', '--format', '{{.Names}}'))
    if ($clusterResources.Count -eq 0) {
        if ($platformResources.Count -ne 0 -or $clusters -contains 'crewmeister' -or $projectNodes.Count -ne 0) {
            throw 'Refusing teardown: project infrastructure exists without matching cluster state. Preserve state and resolve ownership first.'
        }
        Write-Host 'Project infrastructure is already absent.'
        return
    }
    if ($clusterResources.Count -ne 1 -or $clusterResources[0] -ne 'kind_cluster.crewmeister') { throw 'Refusing teardown: unexpected cluster resources.' }
    if ($clusters -notcontains 'crewmeister') { throw 'Project cluster is missing but state remains. Restore or recover it before teardown.' }
    Assert-State cluster 'kind_cluster.crewmeister.name == "crewmeister" && kind_cluster.crewmeister.context_name == "kind-crewmeister" && kind_cluster.crewmeister.kubeconfig_path == abspath("${path.module}/../../.local/crewmeister.kubeconfig")'

    $guards = @{
        'helm_release.application' = 'helm_release.application.name == "crewmeister-app" && helm_release.application.namespace == "crewmeister"'
        'helm_release.mysql' = 'helm_release.mysql.name == "crewmeister-mysql" && helm_release.mysql.namespace == "crewmeister"'
        'kubernetes_namespace_v1.crewmeister' = 'kubernetes_namespace_v1.crewmeister.metadata[0].name == "crewmeister"'
        'kubernetes_secret_v1.database' = 'kubernetes_secret_v1.database.metadata[0].name == "crewmeister-database" && kubernetes_secret_v1.database.metadata[0].namespace == "crewmeister"'
        'kubernetes_secret_v1.mysql_root' = 'kubernetes_secret_v1.mysql_root.metadata[0].name == "crewmeister-mysql-root" && kubernetes_secret_v1.mysql_root.metadata[0].namespace == "crewmeister"'
        'random_password.database' = 'true'
        'random_password.mysql_root' = 'true'
    }
    $checks = @('true')
    foreach ($resource in $platformResources) {
        if (-not $guards.ContainsKey($resource)) { throw "Refusing teardown: unexpected platform resource $resource." }
        $checks += "($($guards[$resource]))"
    }
    if ($platformResources.Count -gt 0) { Assert-State platform ($checks -join ' && ') }

    # Match the live API to both Docker's project node and Terraform's recorded CA.
    $nodes = @(Invoke-Checked docker @('ps', '-a', '--filter', 'label=io.x-k8s.kind.cluster=crewmeister', '--format', '{{.Names}}'))
    if ($nodes.Count -ne 1 -or $nodes[0] -ne 'crewmeister-control-plane') { throw 'Refusing teardown: unexpected project node containers.' }
    $kubeArgs = @('--kubeconfig', $kubeconfig, '--context', 'kind-crewmeister')
    $server = Invoke-Checked kubectl ($kubeArgs + @('config', 'view', '--minify', '--output=jsonpath={.clusters[0].cluster.server}'))
    $binding = Invoke-Checked docker @('port', 'crewmeister-control-plane', '6443/tcp')
    if ($binding -notmatch '^127\.0\.0\.1:\d+$' -or $server -ne "https://$binding") { throw 'Refusing teardown: kubeconfig does not point to the project Docker API port.' }
    $ca = Invoke-Checked kubectl ($kubeArgs + @('config', 'view', '--minify', '--raw', '--output=jsonpath={.clusters[0].cluster.certificate-authority-data}'))
    if ($ca -notmatch '^[A-Za-z0-9+/=]+$') { throw 'Refusing teardown: invalid project CA data.' }
    Assert-State cluster ('kind_cluster.crewmeister.endpoint == "' + $server + '" && base64encode(kind_cluster.crewmeister.cluster_ca_certificate) == "' + $ca + '"')
    Invoke-Checked kubectl ($kubeArgs + @('get', 'node', 'crewmeister-control-plane', '--request-timeout=10s', '--output=name')) | Out-Null

    Write-Host 'Removing the verified Crewmeister platform and cluster. Database data will be deleted.'
    if ($platformResources.Count -gt 0) {
        Invoke-Checked terraform @('-chdir=terraform/platform', 'plan', '-destroy', '-input=false', "-out=$platformPlan", "-var=kubeconfig_path=$kubeconfig", '-var=kube_context=kind-crewmeister') | Out-Null
    }
    Invoke-Checked terraform @('-chdir=terraform/cluster', 'plan', '-destroy', '-input=false', "-out=$clusterPlan") | Out-Null
    if ($platformResources.Count -gt 0) {
        Invoke-Checked terraform @('-chdir=terraform/platform', 'apply', '-input=false', '-auto-approve', $platformPlan)
    }
    Invoke-Checked terraform @('-chdir=terraform/cluster', 'apply', '-input=false', '-auto-approve', $clusterPlan)
    $remaining = @(Invoke-Checked docker @('ps', '-a', '--filter', 'label=io.x-k8s.kind.cluster=crewmeister', '--format', '{{.Names}}'))
    if ($remaining.Count -ne 0 -or @(Invoke-Checked kind @('get', 'clusters')) -contains 'crewmeister') { throw 'Project cluster removal could not be confirmed.' }
    Write-Host 'Teardown complete. Project infrastructure removed; cached images and local Terraform files retained.'
} finally {
    foreach ($plan in @(".local/down-$runId-platform.tfplan", ".local/down-$runId-cluster.tfplan")) {
        if (Test-Path -LiteralPath $plan) { Remove-Item -LiteralPath $plan }
    }
    $env:PATH = $previousPath
    $env:KUBECONFIG = $previousKubeconfig
    $env:KIND_EXPERIMENTAL_PROVIDER = $previousProvider
    Pop-Location
}
