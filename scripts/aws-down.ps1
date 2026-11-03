[CmdletBinding()]
param(
    [ValidateSet('Audit','CheckClusterTeardown')][string]$Mode = 'Audit',
    [string]$ConfigPath = '.local/aws/deployment.json'
)
. "$PSScriptRoot/aws-common.ps1"
Assert-AwsTools
Read-AwsConfig $ConfigPath
Assert-AwsIdentity
$c = $script:AwsConfig
$filter = "Name=tag:Project,Values=$($c.cluster_name)"
if ($Mode -eq 'CheckClusterTeardown') {
    Assert-AwsBackend
    $cluster = Assert-AwsCluster
    Assert-AwsKubeconfig $cluster
    $namespace = Invoke-AwsKube @('get','namespace','crewmeister','--ignore-not-found','--output=name')
    $controller = Invoke-AwsKube @('--namespace','kube-system','get','deployment','aws-load-balancer-controller','--ignore-not-found','--output=name')
    $loadBalancers = Invoke-AwsRead @('resourcegroupstaggingapi','get-resources','--resource-type-filters','elasticloadbalancing:loadbalancer','elasticloadbalancing:targetgroup','--tag-filters',"Key=Project,Values=$($c.cluster_name)")
    $dataVolumes = Invoke-AwsRead @('ec2','describe-volumes','--filters',$filter,'Name=tag:ebs.csi.aws.com/cluster,Values=true')
    if ($namespace -or $controller -or @($loadBalancers.ResourceTagMappingList).Count -or @($dataVolumes.Volumes).Count) { throw 'Platform, load balancer resources or CSI data volumes remain. Do not destroy the cluster.' }
    Write-Host 'Cluster teardown prerequisites passed. State-recorded IDs still require review; no destroy plan or destruction was run.'
    return
}
foreach ($query in @(
    @('ec2','describe-instances','--filters',$filter,'--query','Reservations[].Instances[].{Id:InstanceId,State:State.Name}'),
    @('ec2','describe-volumes','--filters',$filter,'--query','Volumes[].{Id:VolumeId,State:State}'),
    @('ec2','describe-snapshots','--owner-ids','self','--filters',$filter,'--query','Snapshots[].SnapshotId'),
    @('ec2','describe-addresses','--filters',$filter,'--query','Addresses[].AllocationId'),
    @('ec2','describe-nat-gateways','--filter',$filter,'--query','NatGateways[].{Id:NatGatewayId,State:State}'),
    @('ec2','describe-vpcs','--filters',$filter,'--query','Vpcs[].VpcId'),
    @('resourcegroupstaggingapi','get-resources','--tag-filters',"Key=Project,Values=$($c.cluster_name)",'--query','ResourceTagMappingList[].ResourceARN')
)) {
    Write-Host "Audit: $($query[1])"
    Invoke-AwsRead $query | ConvertTo-Json -Depth 8 | Write-Host
}
$clusters = Invoke-AwsRead @('eks','list-clusters')
if (@($clusters.clusters) -contains $c.cluster_name) { Write-Host "EKS cluster remains: $($c.cluster_name)" }
Write-Host 'Audit only: nothing was destroyed. Results can include the deliberately retained S3 backend and IAM resources.'
Write-Host 'Before declaring cleanup complete, also inspect state-recorded IDs and VPC ENIs/ASGs for resources missing tags.'
Write-Host 'Use the separately approved, staged teardown procedure in docs/aws-deployment.md.'
