[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot

function Invoke-Checked {
    param([string]$Program, [string[]]$CommandArgs)
    # Native stderr may contain progress; use the process exit code for failure.
    $ErrorActionPreference = 'Continue'
    & $Program @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE." }
}

try {
    New-Item -ItemType Directory -Path .local -Force | Out-Null
    $mode = if ($env:CREWMEISTER_IMAGE_MODE) { $env:CREWMEISTER_IMAGE_MODE } else { 'auto' }
    $repository = if ($env:CREWMEISTER_IMAGE_REPOSITORY) { $env:CREWMEISTER_IMAGE_REPOSITORY } else { 'ghcr.io/ouemnaa/crewmeister-devops-challenge' }
    $tag = if ($env:CREWMEISTER_IMAGE_TAG) { $env:CREWMEISTER_IMAGE_TAG } else { Invoke-Checked git @('rev-parse', 'HEAD') }
    if (@('auto', 'local', 'registry') -cnotcontains $mode) { throw 'CREWMEISTER_IMAGE_MODE must be auto, local, or registry.' }
    if ($repository -cnotmatch '^[a-z0-9][a-z0-9./:_-]*$') { throw 'Invalid image repository.' }
    if ($tag -cnotmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$') { throw 'Invalid image tag.' }

    $sourcePaths = @('Dockerfile', '.dockerignore', 'pom.xml', 'mvnw', '.mvn', 'src')
    $sourceChanges = @(Invoke-Checked git (@('status', '--porcelain', '--untracked-files=normal', '--') + $sourcePaths))
    $useRegistry = $false
    if ($mode -eq 'registry' -or ($mode -eq 'auto' -and $sourceChanges.Count -eq 0)) {
        Write-Host "Checking registry image ${repository}:$tag"
        $docker = (Get-Command docker -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $pull = Start-Process -FilePath $docker -ArgumentList @('pull', "${repository}:$tag") -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput .local/image-pull.log -RedirectStandardError .local/image-pull.err -Wait -PassThru
        $useRegistry = $pull.ExitCode -eq 0
        if (-not $useRegistry -and $mode -eq 'registry') { throw 'Registry image could not be pulled. See .local/image-pull.err.' }
    }

    if ($useRegistry) {
        $pullPolicy = 'IfNotPresent'
    } else {
        Write-Host 'Building the current checkout locally and loading it into Kind.'
        $files = @(Invoke-Checked git (@('ls-files', '--cached', '--others', '--exclude-standard', '--') + $sourcePaths))
        $manifest = @(
            foreach ($file in $files) {
                if (Test-Path -LiteralPath $file -PathType Leaf) {
                    $hash = Invoke-Checked git @('hash-object', '--', $file)
                    "$file $hash"
                }
            }
        )
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText((Join-Path $repoRoot '.local/image-sources'), ($manifest -join "`n") + "`n", $utf8)
        $sourceHash = Invoke-Checked git @('hash-object', '--', '.local/image-sources')
        $repository = 'crewmeister-app'
        $tag = "local-$sourceHash"
        $pullPolicy = 'Never'
        Invoke-Checked docker @('build', '--tag', "${repository}:$tag", '.')
    }

    Invoke-Checked kind @('load', 'docker-image', "${repository}:$tag", '--name', 'crewmeister')
    $configuration = @{
        image_repository = $repository
        image_tag = $tag
        image_pull_policy = $pullPolicy
    } | ConvertTo-Json
    [System.IO.File]::WriteAllText((Join-Path $repoRoot '.local/image.auto.tfvars.json'), $configuration + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Image ready: ${repository}:$tag ($pullPolicy)"
} finally {
    Pop-Location
}
