#!/usr/bin/env bash
# Offline regression checks: no real cloud commands are possible.
set -euo pipefail
umask 077
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo"
name="crewmeister-aws-tests-bash-$$"
relative=".local/aws/$name-input.json"
fixture="$repo/$relative"
private_dir="$repo/.local/aws/$name"
[[ ! -e "$fixture" && ! -e "$private_dir" ]] || { echo 'Refusing existing test fixtures.' >&2; exit 1; }
mkdir -p .local/aws
export AWS_GUARD_ACCOUNT=111122223333
aws() {
    if [[ "${1:-}" == --version ]]; then echo 'aws-cli/2.38.4 test-only'; return; fi
    while [[ "${1:-}" == --profile || "${1:-}" == --region || "${1:-}" == --output || "${1:-}" == --no-cli-pager ]]; do
        if [[ "$1" == --no-cli-pager ]]; then shift; else shift 2; fi
    done
    case "$1 $2" in
        'sts get-caller-identity') printf '{"Account":"%s","Arn":"arn:aws:sts::111122223333:assumed-role/Testing/session"}\n' "$AWS_GUARD_ACCOUNT" ;;
        'iam get-role') echo '{"Role":{"Arn":"arn:aws:iam::111122223333:role/Testing"}}' ;;
        *) echo 'Unexpected AWS operation in offline test.' >&2; return 90 ;;
    esac
}
terraform() { [[ "${1:-}" == version ]] || return 90; echo '{"terraform_version":"1.15.8"}'; }
helm() { [[ "${1:-}" == version ]] || return 90; echo 'v4.3.1+test'; }
kubectl() { [[ "${1:-}" == version ]] || return 90; echo '{"clientVersion":{"gitVersion":"v1.36.4"}}'; }
export -f aws terraform helm kubectl
config="$(jq -n --arg name "$name" '{
  aws_profile:"testing",aws_region:"eu-north-1",expected_account_id:"111122223333",
  cluster_name:$name,state_bucket:"crewmeister-offline-test",operator_role_arn:"arn:aws:iam::111122223333:role/Testing",
  api_access_cidrs:["8.8.8.8/32"],client_access_cidrs:["8.8.8.8/32"],
  image_repository:"ghcr.io/example/assessment",image_tag:"1111111111111111111111111111111111111111",
  enable_public_ingress:false,certificate_arn:null
}')"
reject() {
    local pattern="$1" output
    if output="$(bash scripts/aws-setup.sh --mode prepare --config "$relative" 2>&1)"; then
        echo "Expected rejection: $pattern" >&2; exit 1
    fi
    [[ "$output" == *"$pattern"* ]] || { echo "Unexpected failure: $output" >&2; exit 1; }
}
jq '.aws_profile="default"' <<<"$config" >"$fixture"
reject 'Invalid private AWS configuration'
jq '.api_access_cidrs=["0.0.0.0/0"]' <<<"$config" >"$fixture"
reject 'IPv4 /24'
printf '%s\n' "$config" >"$fixture"
export AWS_GUARD_ACCOUNT=999999999999
reject 'account mismatch'
[[ ! -e "$private_dir" ]] || { echo 'Wrong-account preparation wrote files.' >&2; exit 1; }
export AWS_GUARD_ACCOUNT=111122223333
bash scripts/aws-setup.sh --mode prepare --config "$relative"
before="$(cat "$private_dir/cluster.tfvars.json")"
reject 'Preparation files exist'
[[ "$before" == "$(cat "$private_dir/cluster.tfvars.json")" ]] || { echo 'Inputs overwritten.' >&2; exit 1; }
[[ "$(cat "$private_dir/backend.hcl")" == *allowed_account_ids* ]]
echo 'PASS: default profile, world-open CIDR, wrong account, private preparation and overwrite protection (offline stubs).'
