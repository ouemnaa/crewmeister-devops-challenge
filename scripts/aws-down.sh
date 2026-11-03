#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/aws-common.sh"
aws_arguments audit "$@"
[[ "$aws_mode" == audit || "$aws_mode" == check-cluster-teardown ]] || aws_fail 'Only audit/check-cluster-teardown modes exist; destruction needs separate approval.'
aws_tools
aws_config "$aws_config_path"
aws_identity
filter="Name=tag:Project,Values=$cluster_name"
if [[ "$aws_mode" == check-cluster-teardown ]]; then
    aws_backend; aws_cluster; aws_check_kubeconfig
    namespace="$(aws_kube get namespace crewmeister --ignore-not-found --output=name)"
    controller="$(aws_kube --namespace kube-system get deployment aws-load-balancer-controller --ignore-not-found --output=name)"
    [[ -z "$namespace" ]] || aws_fail 'Platform namespace remains; do not destroy cluster.'
    [[ -z "$controller" ]] || aws_fail 'Load balancer controller remains; destroy platform first.'
    balancers="$(aws_read resourcegroupstaggingapi get-resources --resource-type-filters elasticloadbalancing:loadbalancer elasticloadbalancing:targetgroup --tag-filters "Key=Project,Values=$cluster_name")"
    jq -e '.ResourceTagMappingList | length == 0' <<<"$balancers" >/dev/null || aws_fail 'Project load balancer resources remain.'
    volumes="$(aws_read ec2 describe-volumes --filters "$filter" 'Name=tag:ebs.csi.aws.com/cluster,Values=true')"
    jq -e '.Volumes | length == 0' <<<"$volumes" >/dev/null || aws_fail 'Project CSI data volumes remain.'
    echo 'Cluster teardown prerequisites passed. Review state-recorded IDs; no destroy plan or destruction run.'
    exit
fi
echo 'Project-owned EC2 instances:'
aws_read ec2 describe-instances --filters "$filter" --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name}'
echo 'Project-owned EBS volumes:'
aws_read ec2 describe-volumes --filters "$filter" --query 'Volumes[].{Id:VolumeId,State:State}'
echo 'Project-owned snapshots:'
aws_read ec2 describe-snapshots --owner-ids self --filters "$filter" --query 'Snapshots[].SnapshotId'
echo 'Project-owned Elastic IPs:'
aws_read ec2 describe-addresses --filters "$filter" --query 'Addresses[].AllocationId'
echo 'Project-owned NAT gateways (none expected):'
aws_read ec2 describe-nat-gateways --filter "$filter" --query 'NatGateways[].{Id:NatGatewayId,State:State}'
echo 'Project-owned VPCs:'
aws_read ec2 describe-vpcs --filters "$filter" --query 'Vpcs[].VpcId'
echo 'Tagged resources, including load balancers, target groups and retained backend:'
aws_read resourcegroupstaggingapi get-resources --tag-filters "Key=Project,Values=$cluster_name" --query 'ResourceTagMappingList[].ResourceARN'
clusters="$(aws_read eks list-clusters)"
jq --arg name "$cluster_name" '.clusters | map(select(. == $name))' <<<"$clusters"
echo 'Audit only: nothing destroyed. Retained backend/IAM resources may appear.'
echo 'Also inspect state-recorded IDs and VPC ENIs/ASGs for resources missing tags.'
echo 'Follow the separately approved staged teardown in docs/aws-deployment.md.'
