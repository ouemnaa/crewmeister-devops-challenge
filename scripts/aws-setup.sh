#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/aws-common.sh"
aws_arguments validate "$@"
case "$aws_mode" in
    validate) aws_static; exit ;;
    prepare|connect|guard) ;;
    *) aws_fail 'Allowed modes: validate, prepare, connect, guard. No provisioning mode exists in Phase B.' ;;
esac
aws_tools
aws_config "$aws_config_path"
aws_identity
if [[ "$aws_mode" == guard ]]; then
    case "$aws_stage" in
        bootstrap)
            if [[ -f "$aws_repo_root/.local/aws/bootstrap.tfstate" ]]; then
                jq -e --arg bucket "$state_bucket" '
                  [.resources[] | select(.mode == "managed" and .type == "aws_s3_bucket" and .name == "state")] |
                  length == 1 and (.[0].instances | length == 1) and .[0].instances[0].attributes.bucket == $bucket
                ' "$aws_repo_root/.local/aws/bootstrap.tfstate" >/dev/null || aws_fail 'Existing bootstrap state bucket mismatch; recovery review required.'
                aws_backend
            fi ;;
        cluster) aws_backend ;;
        platform)
            aws_backend; aws_cluster; aws_check_kubeconfig
            aws_kube --namespace kube-system rollout status deployment/ebs-csi-controller --timeout=180s
            aws_kube --namespace kube-system rollout status daemonset/eks-pod-identity-agent --timeout=180s ;;
        *) aws_fail 'Stage must be bootstrap, cluster or platform.' ;;
    esac
    echo "Identity and $aws_stage prerequisites checked. No Terraform operation performed; review the separate plan and obtain approval."
    exit
fi
if [[ "$aws_mode" == connect ]]; then
    aws_backend
    aws_cluster
    [[ ! -e "$aws_kubeconfig" ]] || aws_fail 'Refusing to overwrite an existing dedicated kubeconfig.'
    mkdir -p -- "$aws_private_dir"
    (
        set -o noclobber
        jq --arg name "$cluster_name" --arg profile "$aws_profile" --arg region "$aws_region" '
          {apiVersion:"v1",kind:"Config","current-context":$name,
           clusters:[{name:$name,cluster:{server:.cluster.endpoint,"certificate-authority-data":.cluster.certificateAuthority.data}}],
           contexts:[{name:$name,context:{cluster:$name,user:$name}}],
           users:[{name:$name,user:{exec:{apiVersion:"client.authentication.k8s.io/v1beta1",command:"aws",interactiveMode:"Never",
             args:["eks","get-token","--cluster-name",$name,"--profile",$profile,"--region",$region]}}}]}
        ' <<<"$aws_cluster_json" >"$aws_kubeconfig"
    )
    aws_check_kubeconfig
    echo "Created dedicated kubeconfig: $aws_kubeconfig"
    exit
fi
for file in bootstrap.tfvars.json cluster.tfvars.json platform.tfvars.json backend.hcl; do
    [[ ! -e "$aws_private_dir/$file" ]] || aws_fail 'Preparation files exist; review/archive manually. Nothing was overwritten.'
done
mkdir -p -- "$aws_private_dir"
(
    set -o noclobber
    jq '{aws_profile,aws_region,expected_account_id,cluster_name,state_bucket,deployment_principal_arn:.operator_role_arn}' "$aws_config_file" >"$aws_private_dir/bootstrap.tfvars.json"
    jq '{aws_profile,aws_region,expected_account_id,cluster_name,operator_role_arn,api_access_cidrs}' "$aws_config_file" >"$aws_private_dir/cluster.tfvars.json"
    jq '{aws_profile,aws_region,expected_account_id,cluster_name,state_bucket,image_repository,image_tag,client_access_cidrs,enable_public_ingress,allow_unrestricted_api:(.allow_unrestricted_api // false),certificate_arn}' "$aws_config_file" >"$aws_private_dir/platform.tfvars.json"
    jq -r '
      "bucket = " + (.state_bucket | tojson),
      "region = " + (.aws_region | tojson),
      "profile = " + (.aws_profile | tojson),
      "allowed_account_ids = [" + (.expected_account_id | tojson) + "]",
      "workspace_key_prefix = \"disabled-workspaces\""
    ' "$aws_config_file" >"$aws_private_dir/backend.hcl"
)
echo 'Private inputs prepared. No backend initialized; no plan/apply run.'
echo 'Review docs/aws-deployment.md and obtain separate Phase C approval.'
