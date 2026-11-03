#!/usr/bin/env bash
# Shared only by AWS scripts. All cloud calls here are read-only.
set -euo pipefail
umask 077
aws_repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

aws_fail() { echo "$*" >&2; exit 1; }
aws_tools() {
    (( BASH_VERSINFO[0] >= 4 )) || aws_fail 'Bash 4 or newer is required.'
    [[ -z "${TF_WORKSPACE:-}" || "${TF_WORKSPACE:-}" == default ]] || aws_fail 'AWS roots require the default workspace.'
    local stage workspace_file
    for stage in bootstrap cluster platform; do
        workspace_file="$aws_repo_root/terraform/aws/$stage/.terraform/environment"
        [[ ! -f "$workspace_file" || "$(cat "$workspace_file")" == default ]] || aws_fail "Unexpected AWS $stage workspace."
    done
    for tool in aws terraform helm kubectl jq; do
        command -v "$tool" >/dev/null 2>&1 || aws_fail "Missing prerequisite: $tool."
    done
    [[ "$(terraform version -json | jq -r .terraform_version)" == 1.15.8 ]] || aws_fail 'Terraform 1.15.8 is required.'
    [[ "$(aws --version)" == aws-cli/2.* ]] || aws_fail 'AWS CLI v2 is required.'
    [[ "$(helm version --short)" == v4.3.1+* ]] || aws_fail 'Helm 4.3.1 is required.'
    kubectl version --client --output=json | jq -e '.clientVersion.gitVersion | test("^v1\\.(35|36|37)\\.")' >/dev/null || aws_fail 'kubectl 1.35-1.37 is required.'
    [[ "$(jq --version)" =~ ^jq-1\.([6-9]|[1-9][0-9]) ]] || aws_fail 'jq 1.6 or newer is required.'
}
aws_config() {
    local relative="${1:-.local/aws/deployment.json}"
    [[ "$relative" == .local/aws/* && "$relative" != *..* ]] || aws_fail 'Config must be a repository-relative file inside .local/aws/.'
    aws_config_file="$aws_repo_root/$relative"
    jq -e '
      (.aws_profile | test("^[A-Za-z0-9_-]+$")) and .aws_profile != "default" and
      .aws_region == "eu-north-1" and
      (.expected_account_id | test("^[0-9]{12}$")) and
      (.cluster_name | test("^crewmeister-aws(-[a-z0-9-]+)?$")) and (.cluster_name | length <= 40) and
      (.state_bucket | test("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$"))
    ' "$aws_config_file" >/dev/null || aws_fail 'Invalid private AWS configuration.'
    # Account matching is kept separate to avoid trusting a discovered account as the expected value.
    aws_profile="$(jq -r .aws_profile "$aws_config_file")"
    aws_region="$(jq -r .aws_region "$aws_config_file")"
    expected_account="$(jq -r .expected_account_id "$aws_config_file")"
    cluster_name="$(jq -r .cluster_name "$aws_config_file")"
    state_bucket="$(jq -r .state_bucket "$aws_config_file")"
    operator_role="$(jq -r .operator_role_arn "$aws_config_file")"
    [[ "$operator_role" == arn:aws:iam::"$expected_account":role/* ]] || aws_fail 'IAM role must belong to the expected account.'
    jq -e '
      (.image_repository | test("^ghcr.io/[a-z0-9._/-]+$")) and
      (.image_tag | test("^[0-9a-f]{40}$")) and .image_tag != "0000000000000000000000000000000000000000" and
      (.enable_public_ingress | type == "boolean") and
      ([.api_access_cidrs, .client_access_cidrs] | all(.[];
        type == "array" and length > 0 and all(.[];
          test("^([0-9]{1,3}\\.){3}[0-9]{1,3}/(2[4-9]|3[0-2])$") and
          (split("/")[0] | split(".") | all(.[]; tonumber >= 0 and tonumber <= 255)) and
          (test("^(203\\.0\\.113|198\\.51\\.100|192\\.0\\.2)\\.") | not)
        )))
    ' "$aws_config_file" >/dev/null || aws_fail 'Replace example CIDRs/image values and use explicit IPv4 /24 or narrower.'
    local certificate
    certificate="$(jq -r '.certificate_arn // empty' "$aws_config_file")"
    [[ -z "$certificate" || "$certificate" =~ ^arn:aws:acm:eu-north-1:$expected_account:certificate/[a-f0-9-]+$ ]] || aws_fail 'Certificate account/region mismatch.'
    aws_private_dir="$aws_repo_root/.local/aws/$cluster_name"
    aws_kubeconfig="$aws_private_dir/$cluster_name.kubeconfig"
    aws_cmd=(aws --profile "$aws_profile" --region "$aws_region" --output json --no-cli-pager)
    local stage metadata
    for stage in cluster platform; do
        metadata="$aws_repo_root/terraform/aws/$stage/.terraform/terraform.tfstate"
        if [[ -f "$metadata" ]]; then
            jq -e --arg bucket "$state_bucket" --arg region "$aws_region" --arg profile "$aws_profile" --arg key "crewmeister/aws/$stage.tfstate" --arg account "$expected_account" '
              .backend | .type == "s3" and .config.bucket == $bucket and .config.region == $region and
              .config.profile == $profile and .config.key == $key and .config.use_lockfile == true and
              (.config.allowed_account_ids | index($account) != null)
            ' "$metadata" >/dev/null || aws_fail "AWS $stage backend metadata mismatch."
        fi
    done
}
aws_read() { "${aws_cmd[@]}" "$@"; }
aws_identity() {
    local identity role_name role
    identity="$(aws_read sts get-caller-identity)"
    [[ "$(jq -r .Account <<<"$identity")" == "$expected_account" ]] || aws_fail 'AWS account mismatch; stopped.'
    role_name="${operator_role##*/}"
    [[ "$(jq -r .Arn <<<"$identity")" == arn:aws:sts::"$expected_account":assumed-role/"$role_name"/* ]] || aws_fail 'Authenticated role mismatch or root identity.'
    role="$(aws_read iam get-role --role-name "$role_name")"
    [[ "$(jq -r .Role.Arn <<<"$role")" == "$operator_role" ]] || aws_fail 'Durable operator role mismatch.'
}
aws_backend() {
    local location versioning encryption public tags policy sid
    local bucket_args=(--bucket "$state_bucket" --expected-bucket-owner "$expected_account")
    aws_read s3api head-bucket "${bucket_args[@]}" >/dev/null
    location="$(aws_read s3api get-bucket-location "${bucket_args[@]}")"
    [[ "$(jq -r .LocationConstraint <<<"$location")" == "$aws_region" ]] || aws_fail 'Backend region mismatch.'
    versioning="$(aws_read s3api get-bucket-versioning "${bucket_args[@]}")"
    [[ "$(jq -r .Status <<<"$versioning")" == Enabled ]] || aws_fail 'Backend versioning missing.'
    encryption="$(aws_read s3api get-bucket-encryption "${bucket_args[@]}")"
    jq -e '.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm == "AES256"' <<<"$encryption" >/dev/null || aws_fail 'Backend encryption mismatch.'
    public="$(aws_read s3api get-public-access-block "${bucket_args[@]}")"
    jq -e '.PublicAccessBlockConfiguration | .BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets' <<<"$public" >/dev/null || aws_fail 'Backend public access protection missing.'
    tags="$(aws_read s3api get-bucket-tagging "${bucket_args[@]}")"
    jq -e --arg project "$cluster_name" '.TagSet | any(.[]; .Key == "Project" and .Value == $project)' <<<"$tags" >/dev/null || aws_fail 'Backend ownership mismatch.'
    policy="$(aws_read s3api get-bucket-policy "${bucket_args[@]}")"
    for sid in RequireTLS RestrictPrincipals ProtectBucketAndStateVersions ProtectCurrentStates; do
        jq -e --arg sid "$sid" '.Policy | fromjson | .Statement | any(.[]; .Sid == $sid and .Effect == "Deny")' <<<"$policy" >/dev/null || aws_fail "Backend protection missing: $sid."
    done
}
aws_cluster() {
    aws_cluster_json="$(aws_read eks describe-cluster --name "$cluster_name")"
    jq -e --arg arn "arn:aws:eks:$aws_region:$expected_account:cluster/$cluster_name" --arg project "$cluster_name" '
      .cluster | .arn == $arn and .status == "ACTIVE" and .tags.Project == $project and .version == "1.36"
    ' <<<"$aws_cluster_json" >/dev/null || aws_fail 'Cluster identity, ownership, readiness or version mismatch.'
    local vpc
    vpc="$(aws_read ec2 describe-vpcs --vpc-ids "$(jq -r .cluster.resourcesVpcConfig.vpcId <<<"$aws_cluster_json")")"
    jq -e --arg project "$cluster_name" '.Vpcs[0] | (.IsDefault | not) and (.Tags | any(.[]; .Key == "Project" and .Value == $project))' <<<"$vpc" >/dev/null || aws_fail 'Cluster VPC ownership mismatch.'
}
aws_kube() { kubectl --kubeconfig "$aws_kubeconfig" --context "$cluster_name" --namespace crewmeister "$@"; }
aws_check_kubeconfig() {
    [[ -f "$aws_kubeconfig" ]] || aws_fail 'Dedicated kubeconfig missing; run setup --mode connect after approved deployment.'
    local view
    view="$(aws_kube config view --raw --minify --output=json)"
    jq -e --arg server "$(jq -r .cluster.endpoint <<<"$aws_cluster_json")" --arg ca "$(jq -r .cluster.certificateAuthority.data <<<"$aws_cluster_json")" --arg name "$cluster_name" --arg profile "$aws_profile" --arg region "$aws_region" '
      .clusters[0].cluster.server == $server and .clusters[0].cluster["certificate-authority-data"] == $ca and
      .users[0].user.exec.command == "aws" and
      .users[0].user.exec.args == ["eks","get-token","--cluster-name",$name,"--profile",$profile,"--region",$region]
    ' <<<"$view" >/dev/null || aws_fail 'Dedicated kubeconfig endpoint, CA or credential command mismatch.'
}
aws_static() {
    aws_tools
    local stage
    for stage in bootstrap cluster platform; do
        terraform -chdir="$aws_repo_root/terraform/aws/$stage" fmt -check
        terraform -chdir="$aws_repo_root/terraform/aws/$stage" init -backend=false -input=false -lockfile=readonly
        terraform -chdir="$aws_repo_root/terraform/aws/$stage" validate
    done
    helm lint "$aws_repo_root/helm/crewmeister-app" --values "$aws_repo_root/helm/crewmeister-app/values-aws.yaml" --strict
    helm template crewmeister-app "$aws_repo_root/helm/crewmeister-app" --namespace crewmeister --values "$aws_repo_root/helm/crewmeister-app/values-aws.yaml" >/dev/null
    echo 'Static validation passed; no backend, Kubernetes or AWS resource changes requested.'
}
aws_arguments() {
    aws_mode="$1"; shift
    aws_config_path='.local/aws/deployment.json'
    aws_stage=bootstrap
    while (($#)); do
        [[ $# -ge 2 ]] || aws_fail 'Each option needs a value.'
        case "$1" in
            --mode) aws_mode="$2" ;;
            --config) aws_config_path="$2" ;;
            --stage) aws_stage="$2" ;;
            *) aws_fail "Unknown option: $1" ;;
        esac
        shift 2
    done
}
