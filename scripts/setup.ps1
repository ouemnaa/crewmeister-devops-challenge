[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string]$Program, [string[]]$CommandArgs)

    & $Program @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "$Program failed with exit code $LASTEXITCODE."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$previousKubeconfig = $env:KUBECONFIG
$previousKindProvider = $env:KIND_EXPERIMENTAL_PROVIDER
$previousPath = $env:PATH
Push-Location $repoRoot

try {
    if (Test-Path -LiteralPath .local/bin -PathType Container) {
        $env:PATH = (Join-Path $repoRoot '.local/bin') + [System.IO.Path]::PathSeparator + $env:PATH
    }
    foreach ($tool in @('docker', 'terraform', 'kind', 'kubectl')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
            throw "Required tool is missing: $tool. See the README prerequisites."
        }
    }

    $terraformVersion = (Invoke-Checked terraform @('version', '-json') | ConvertFrom-Json).terraform_version
    if ($terraformVersion -ne '1.15.8') {
        throw "Terraform 1.15.8 is required; found $terraformVersion."
    }

    $kindVersion = Invoke-Checked kind @('version')
    if ($kindVersion -notmatch '^kind v0\.33\.0\s') {
        throw "Kind 0.33.0 is required; found $kindVersion."
    }

    $kubectlVersion = (Invoke-Checked kubectl @('version', '--client', '--output=json') | ConvertFrom-Json).clientVersion.gitVersion
    if ($kubectlVersion -notmatch '^v1\.(35|36|37)\.') {
        throw "kubectl must be within one minor of Kubernetes 1.36; found $kubectlVersion. Use 1.36.4."
    }

    if ((Invoke-Checked docker @('info', '--format', '{{.OSType}}')) -ne 'linux') {
        throw 'Docker must be running with Linux containers.'
    }
    $cgroupVersion = Invoke-Checked docker @('info', '--format', '{{.CgroupVersion}}')
    switch ($cgroupVersion) {
        '1' {
            $cgroupCompatibility = 'true'
            Write-Host 'Docker uses cgroup v1. Enabling the documented local compatibility setting; cgroup v2 is preferred.'
        }
        '2' { $cgroupCompatibility = 'false' }
        default { throw "Unsupported Docker cgroup version: $cgroupVersion." }
    }

    New-Item -ItemType Directory -Path .local -Force | Out-Null
    $env:KUBECONFIG = Join-Path $repoRoot '.local/crewmeister.kubeconfig'
    $env:KIND_EXPERIMENTAL_PROVIDER = 'docker'

    Invoke-Checked terraform @('-chdir=terraform/cluster', 'init', '-input=false')
    Invoke-Checked terraform @('-chdir=terraform/cluster', 'validate')

    $clusters = @(Invoke-Checked kind @('get', 'clusters'))
    $managedResources = @()
    if (Test-Path -LiteralPath terraform/cluster/terraform.tfstate) {
        $managedResources = @(Invoke-Checked terraform @('-chdir=terraform/cluster', 'state', 'list'))
    }
    if ($clusters -contains 'crewmeister' -and $managedResources -notcontains 'kind_cluster.crewmeister') {
        throw 'A crewmeister cluster already exists outside this Terraform state. Resolve that name conflict first.'
    }

    Invoke-Checked terraform @('-chdir=terraform/cluster', 'apply', '-input=false', '-auto-approve', "-var=cgroup_v1_compatibility=$cgroupCompatibility")
    $kubeconfig = Invoke-Checked terraform @('-chdir=terraform/cluster', 'output', '-raw', 'kubeconfig_path')
    $context = Invoke-Checked terraform @('-chdir=terraform/cluster', 'output', '-raw', 'context')
    Invoke-Checked kubectl @('--kubeconfig', $kubeconfig, '--context', $context, 'wait', '--for=condition=Ready', 'nodes', '--all', '--timeout=180s')
    Invoke-Checked kubectl @('--kubeconfig', $kubeconfig, '--context', $context, 'get', 'nodes')

    Write-Host "Cluster ready. Project kubeconfig: $kubeconfig"
    Write-Host 'The current setup provisions the cluster only; application deployment follows in the platform stage.'
} finally {
    $env:KUBECONFIG = $previousKubeconfig
    $env:KIND_EXPERIMENTAL_PROVIDER = $previousKindProvider
    $env:PATH = $previousPath
    Pop-Location
}
