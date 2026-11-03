[CmdletBinding()]
param([string]$ConfigPath = '.local/aws/deployment.json')
. "$PSScriptRoot/aws-common.ps1"
Assert-AwsTools
Read-AwsConfig $ConfigPath
Assert-AwsIdentity
Assert-AwsBackend
$cluster = Assert-AwsCluster
Assert-AwsKubeconfig $cluster
Invoke-AwsKube @('wait','--for=condition=Ready','nodes','--all','--timeout=180s') | Out-Host
foreach ($daemon in @('aws-node','ebs-csi-node','eks-pod-identity-agent')) {
    Invoke-AwsKube @('--namespace','kube-system','rollout','status',"daemonset/$daemon",'--timeout=180s') | Out-Host
}
foreach ($workload in @('statefulset/crewmeister-mysql','deployment/crewmeister-app','statefulset/prometheus-crewmeister-monitoring-prometheus','deployment/crewmeister-grafana','deployment/crewmeister-mysql-exporter','deployment/aws-load-balancer-controller')) {
    if ($workload -eq 'deployment/aws-load-balancer-controller') {
        Invoke-AwsKube @('--namespace','kube-system','rollout','status',$workload,'--timeout=300s') | Out-Host
    } else { Invoke-AwsKube @('rollout','status',$workload,'--timeout=300s') | Out-Host }
}
$pvc = Invoke-AwsKube @('get','pvc','db-volume-crewmeister-mysql-0','--output=json') | ConvertFrom-Json
if ($pvc.status.phase -ne 'Bound' -or $pvc.spec.storageClassName -ne 'crewmeister-gp3') { throw 'MySQL EBS PVC is not Bound to crewmeister-gp3.' }
$services = Invoke-AwsKube @('get','service','crewmeister-app','crewmeister-mysql','crewmeister-grafana','crewmeister-monitoring-prometheus','--output=json') | ConvertFrom-Json
if (@($services.items | Where-Object { $_.spec.type -ne 'ClusterIP' }).Count) { throw 'Application/database/monitoring services must remain ClusterIP.' }
$application = Invoke-AwsKube @('get','deployment','crewmeister-app','--output=json') | ConvertFrom-Json
$container = @($application.spec.template.spec.containers | Where-Object { $_.name -eq 'application' })
if ($container.Count -ne 1 -or $container[0].image -ne "$($script:AwsConfig.image_repository):$($script:AwsConfig.image_tag)") { throw 'Deployed application image does not match the configured GHCR SHA.' }
$sc = Invoke-AwsKube @('get','storageclass','crewmeister-gp3','--output=json') | ConvertFrom-Json
if ($sc.provisioner -ne 'ebs.csi.aws.com' -or $sc.reclaimPolicy -ne 'Delete' -or $sc.parameters.encrypted -ne 'true') { throw 'EBS storage configuration mismatch.' }
Invoke-AwsKube @('get','nodes','-o','wide') | Out-Host
Invoke-AwsKube @('get','pods,pvc,ingress') | Out-Host
Write-Host 'Read-only infrastructure checks passed. API writes, persistence recreation and HTTP/monitoring checks remain explicit acceptance checks in docs/aws-deployment.md.'
