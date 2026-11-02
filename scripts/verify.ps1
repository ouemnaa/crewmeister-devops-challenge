[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$previousPath = $env:PATH
$previousKindProvider = $env:KIND_EXPERIMENTAL_PROVIDER
$forward = $null
$postAttempted = $false
$name = 'verify-' + [guid]::NewGuid().ToString('N')
$logPrefix = Join-Path $repoRoot ".local/verify-$name"
$kubeArgs = @('--kubeconfig', (Join-Path $repoRoot '.local/crewmeister.kubeconfig'), '--context', 'kind-crewmeister', '--namespace', 'crewmeister')
Push-Location $repoRoot

function Invoke-Checked {
    param([string]$Program, [string[]]$CommandArgs)
    & $Program @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE." }
}

function Query-MySql {
    param([string]$Sql)
    $command = 'MYSQL_PWD=$MYSQL_PASSWORD mysql --protocol=TCP --host=127.0.0.1 --user=$MYSQL_USER --database=$MYSQL_DATABASE --batch --skip-column-names'
    $result = $Sql | & kubectl @kubeArgs exec -i crewmeister-mysql-0 --container=mysql -- bash -ec $command
    if ($LASTEXITCODE -ne 0) { throw 'MySQL verification query failed.' }
    return $result
}

try {
    if (Test-Path -LiteralPath .local/bin -PathType Container) {
        $env:PATH = (Join-Path $repoRoot '.local/bin') + [System.IO.Path]::PathSeparator + $env:PATH
    }
    foreach ($tool in @('docker', 'kind', 'kubectl')) {
        if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required tool is missing: $tool." }
    }
    $env:KIND_EXPERIMENTAL_PROVIDER = 'docker'
    if (@(Invoke-Checked kind @('get', 'clusters')) -notcontains 'crewmeister') { throw 'Project cluster is absent. Run setup first.' }
    Invoke-Checked kubectl ($kubeArgs + @('get', 'node', 'crewmeister-control-plane', '--output=name'))
    Invoke-Checked kubectl ($kubeArgs + @('wait', '--for=condition=Ready', 'nodes', '--all', '--timeout=180s'))
    Invoke-Checked kubectl ($kubeArgs + @('rollout', 'status', 'statefulset/crewmeister-mysql', '--timeout=300s'))
    Invoke-Checked kubectl ($kubeArgs + @('rollout', 'status', 'deployment/crewmeister-app', '--timeout=300s'))
    $pvc = Invoke-Checked kubectl ($kubeArgs + @('get', 'pvc', 'db-volume-crewmeister-mysql-0', '--output=jsonpath={.status.phase}'))
    if ($pvc -ne 'Bound') { throw 'MySQL PVC is not Bound.' }
    $services = Invoke-Checked kubectl ($kubeArgs + @('get', 'service', 'crewmeister-app', 'crewmeister-mysql', '--output=json')) | ConvertFrom-Json
    if (@($services.items | Where-Object { $_.spec.type -ne 'ClusterIP' }).Count -ne 0) { throw 'Project services must be internal ClusterIP services.' }
    if ((Query-MySql 'SELECT 1;') -ne '1') { throw 'MySQL is not responding.' }

    $kubectlPath = (Get-Command kubectl -CommandType Application | Select-Object -First 1).Source
    $forward = Start-Process -FilePath $kubectlPath -ArgumentList ($kubeArgs + @('port-forward', '--address', '127.0.0.1', 'service/crewmeister-app', ':8080')) -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput "$logPrefix.log" -RedirectStandardError "$logPrefix.err" -PassThru
    $baseUrl = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if ($forward.HasExited) { throw "Port forwarding failed. See $logPrefix.err." }
        $log = Get-Content -LiteralPath "$logPrefix.log" -Raw -ErrorAction SilentlyContinue
        if ($log -match 'Forwarding from 127\.0\.0\.1:(\d+)') { $baseUrl = "http://127.0.0.1:$($Matches[1])"; break }
        Start-Sleep -Seconds 1
    }
    if (-not $baseUrl) { throw 'Port forwarding did not become ready.' }
    if ((Invoke-RestMethod "$baseUrl/user?id=1" -TimeoutSec 10) -ne 'Greetings from Crewmeister, Alice!') { throw 'Seeded GET /user failed.' }
    $postAttempted = $true
    $body = @{ name = $name } | ConvertTo-Json -Compress
    $created = Invoke-RestMethod "$baseUrl/user" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 10
    if ($created -ne "Greetings from Crewmeister, $name!") { throw 'POST /user failed.' }
    $id = Query-MySql "SELECT id FROM user WHERE name = '$name';"
    if ($id -notmatch '^\d+$') { throw 'POST /user did not persist a record.' }
    if ((Invoke-RestMethod "$baseUrl/user?id=$id" -TimeoutSec 10) -ne $created) { throw 'Created user could not be retrieved.' }
    foreach ($path in @('/actuator/health', '/actuator/health/readiness', '/actuator/health/liveness')) {
        if ((Invoke-RestMethod "$baseUrl$path" -TimeoutSec 10).status -ne 'UP') { throw "Health check failed: $path." }
    }
    $metrics = (Invoke-WebRequest "$baseUrl/actuator/prometheus" -UseBasicParsing -TimeoutSec 10).Content
    if ($metrics -notmatch 'jvm_memory_used_bytes' -or $metrics -notmatch 'http_server_requests_seconds_count') { throw 'Expected JVM and HTTP metrics are missing.' }
} finally {
    # Stop forwarding even if database cleanup fails.
    try {
        if ($postAttempted) { Query-MySql "DELETE FROM user WHERE name = '$name';" | Out-Null }
    } finally {
        if ($forward -and -not $forward.HasExited) { Stop-Process -Id $forward.Id }
        $env:PATH = $previousPath
        $env:KIND_EXPERIMENTAL_PROVIDER = $previousKindProvider
        Pop-Location
    }
}

Write-Host 'Verification passed: cluster, workloads, storage, services, GET/POST persistence, health, and metrics.'
