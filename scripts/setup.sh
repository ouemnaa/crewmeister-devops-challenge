#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
if [[ -d .local/bin ]]; then
    export PATH="$repo_root/.local/bin:$PATH"
fi

fail() {
    echo "$*" >&2
    exit 1
}

for tool in docker terraform kind kubectl; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool is missing: $tool. See the README prerequisites."
done

terraform_version="$(terraform version)"
[[ "${terraform_version%%$'\n'*}" == 'Terraform v1.15.8' ]] || fail 'Terraform 1.15.8 is required.'
kind_version="$(kind version)"
[[ "$kind_version" == 'kind v0.33.0 '* ]] || fail "Kind 0.33.0 is required; found $kind_version."
kubectl_version="$(kubectl version --client)"
[[ "$kubectl_version" =~ Client\ Version:\ v1\.(35|36|37)\. ]] || fail 'kubectl must be within one minor of Kubernetes 1.36. Use 1.36.4.'
[[ "$(docker info --format '{{.OSType}}')" == linux ]] || fail 'Docker must be running with Linux containers.'
case "$(docker info --format '{{.CgroupVersion}}')" in
    1)
        cgroup_compatibility=true
        echo 'Docker uses cgroup v1. Enabling the documented local compatibility setting; cgroup v2 is preferred.'
        ;;
    2) cgroup_compatibility=false ;;
    *) fail 'Unsupported Docker cgroup version.' ;;
esac

mkdir -p .local
export KUBECONFIG="$repo_root/.local/crewmeister.kubeconfig"
export KIND_EXPERIMENTAL_PROVIDER=docker

terraform -chdir=terraform/cluster init -input=false
terraform -chdir=terraform/cluster validate

clusters="$(kind get clusters)"
managed_resources=''
if [[ -f terraform/cluster/terraform.tfstate ]]; then
    managed_resources="$(terraform -chdir=terraform/cluster state list)"
fi
if [[ $'\n'"$clusters"$'\n' == *$'\ncrewmeister\n'* && $'\n'"$managed_resources"$'\n' != *$'\nkind_cluster.crewmeister\n'* ]]; then
    fail 'A crewmeister cluster already exists outside this Terraform state. Resolve that name conflict first.'
fi

terraform -chdir=terraform/cluster apply -input=false -auto-approve "-var=cgroup_v1_compatibility=$cgroup_compatibility"
kubeconfig="$(terraform -chdir=terraform/cluster output -raw kubeconfig_path)"
context="$(terraform -chdir=terraform/cluster output -raw context)"
kubectl --kubeconfig "$kubeconfig" --context "$context" wait --for=condition=Ready nodes --all --timeout=180s
kubectl --kubeconfig "$kubeconfig" --context "$context" get nodes

echo "Cluster ready. Project kubeconfig: $kubeconfig"
echo 'The current setup provisions the cluster only; application deployment follows in the platform stage.'
