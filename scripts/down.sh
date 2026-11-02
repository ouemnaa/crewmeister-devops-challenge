#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ ! -d .local/bin ]] || export PATH="$repo_root/.local/bin:$PATH"
export KUBECONFIG="$repo_root/.local/crewmeister.kubeconfig"
export KIND_EXPERIMENTAL_PROVIDER=docker
fail() { echo "$*" >&2; exit 1; }
for tool in docker terraform kind kubectl; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool is missing: $tool."
done

run_id="$$-$RANDOM"
platform_plan="../../.local/down-$run_id-platform.tfplan"
cluster_plan="../../.local/down-$run_id-cluster.tfplan"
cleanup() {
    result=$?
    trap - EXIT
    rm -f -- ".local/down-$run_id-platform.tfplan" ".local/down-$run_id-cluster.tfplan"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

assert_state() {
    [[ "$(printf '%s\n' "$2" | terraform -chdir="terraform/$1" console)" == true ]] || fail "Refusing teardown: $1 state does not match the project identity."
}

cluster_resources=''
platform_resources=''
for stage in cluster platform; do
    if [[ -f "terraform/$stage/terraform.tfstate" ]]; then
        terraform -chdir="terraform/$stage" init -input=false -lockfile=readonly >/dev/null
        resources="$(terraform -chdir="terraform/$stage" state list)"
        if [[ "$stage" == cluster ]]; then cluster_resources="$resources"; else platform_resources="$resources"; fi
    fi
done
clusters="$(kind get clusters)"
project_nodes="$(docker ps -a --filter label=io.x-k8s.kind.cluster=crewmeister --format '{{.Names}}')"
if [[ -z "$cluster_resources" ]]; then
    [[ -z "$platform_resources" && -z "$project_nodes" && $'\n'"$clusters"$'\n' != *$'\ncrewmeister\n'* ]] || fail 'Refusing teardown: project infrastructure exists without matching cluster state. Preserve state and resolve ownership first.'
    echo 'Project infrastructure is already absent.'
    exit 0
fi
[[ "$cluster_resources" == kind_cluster.crewmeister ]] || fail 'Refusing teardown: unexpected cluster resources.'
[[ $'\n'"$clusters"$'\n' == *$'\ncrewmeister\n'* ]] || fail 'Project cluster is missing but state remains. Restore or recover it before teardown.'
assert_state cluster 'kind_cluster.crewmeister.name == "crewmeister" && kind_cluster.crewmeister.context_name == "kind-crewmeister" && kind_cluster.crewmeister.kubeconfig_path == abspath("${path.module}/../../.local/crewmeister.kubeconfig")'
kubeconfig="$(terraform -chdir=terraform/cluster output -raw kubeconfig_path)"

checks=true
while IFS= read -r resource; do
    [[ -n "$resource" ]] || continue
    case "$resource" in
        helm_release.application) check='helm_release.application.name == "crewmeister-app" && helm_release.application.namespace == "crewmeister"' ;;
        helm_release.mysql) check='helm_release.mysql.name == "crewmeister-mysql" && helm_release.mysql.namespace == "crewmeister"' ;;
        kubernetes_namespace_v1.crewmeister) check='kubernetes_namespace_v1.crewmeister.metadata[0].name == "crewmeister"' ;;
        kubernetes_secret_v1.database) check='kubernetes_secret_v1.database.metadata[0].name == "crewmeister-database" && kubernetes_secret_v1.database.metadata[0].namespace == "crewmeister"' ;;
        kubernetes_secret_v1.mysql_root) check='kubernetes_secret_v1.mysql_root.metadata[0].name == "crewmeister-mysql-root" && kubernetes_secret_v1.mysql_root.metadata[0].namespace == "crewmeister"' ;;
        random_password.database|random_password.mysql_root) check=true ;;
        *) fail "Refusing teardown: unexpected platform resource $resource." ;;
    esac
    checks="$checks && ($check)"
done <<< "$platform_resources"
[[ -z "$platform_resources" ]] || assert_state platform "$checks"

# Match the live API to both Docker's project node and Terraform's recorded CA.
[[ "$(docker ps -a --filter label=io.x-k8s.kind.cluster=crewmeister --format '{{.Names}}')" == crewmeister-control-plane ]] || fail 'Refusing teardown: unexpected project node containers.'
kube=(kubectl --kubeconfig "$kubeconfig" --context kind-crewmeister)
server="$("${kube[@]}" config view --minify --output='jsonpath={.clusters[0].cluster.server}')"
binding="$(docker port crewmeister-control-plane 6443/tcp)"
[[ "$binding" =~ ^127\.0\.0\.1:[0-9]+$ && "$server" == "https://$binding" ]] || fail 'Refusing teardown: kubeconfig does not point to the project Docker API port.'
ca="$("${kube[@]}" config view --minify --raw --output='jsonpath={.clusters[0].cluster.certificate-authority-data}')"
[[ "$ca" =~ ^[A-Za-z0-9+/=]+$ ]] || fail 'Refusing teardown: invalid project CA data.'
assert_state cluster "kind_cluster.crewmeister.endpoint == \"$server\" && base64encode(kind_cluster.crewmeister.cluster_ca_certificate) == \"$ca\""
"${kube[@]}" get node crewmeister-control-plane --request-timeout=10s --output=name >/dev/null

echo 'Removing the verified Crewmeister platform and cluster. Database data will be deleted.'
if [[ -n "$platform_resources" ]]; then
    terraform -chdir=terraform/platform plan -destroy -input=false "-out=$platform_plan" "-var=kubeconfig_path=$kubeconfig" -var=kube_context=kind-crewmeister >/dev/null
fi
terraform -chdir=terraform/cluster plan -destroy -input=false "-out=$cluster_plan" >/dev/null
if [[ -n "$platform_resources" ]]; then
    terraform -chdir=terraform/platform apply -input=false -auto-approve "$platform_plan"
fi
terraform -chdir=terraform/cluster apply -input=false -auto-approve "$cluster_plan"
[[ -z "$(docker ps -a --filter label=io.x-k8s.kind.cluster=crewmeister --format '{{.Names}}')" ]] || fail 'Project node containers remain.'
clusters="$(kind get clusters)"
[[ $'\n'"$clusters"$'\n' != *$'\ncrewmeister\n'* ]] || fail 'Project cluster removal could not be confirmed.'
echo 'Teardown complete. Project infrastructure removed; cached images and local Terraform files retained.'
