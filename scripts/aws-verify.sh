#!/usr/bin/env bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/aws-common.sh"
aws_arguments check "$@"
[[ "$aws_mode" == check ]] || aws_fail 'Only read-only check mode is supported.'
aws_tools
aws_config "$aws_config_path"
aws_identity
aws_backend
aws_cluster
aws_check_kubeconfig
aws_kube wait --for=condition=Ready nodes --all --timeout=180s
for daemon in aws-node ebs-csi-node eks-pod-identity-agent; do
    aws_kube --namespace kube-system rollout status "daemonset/$daemon" --timeout=180s
done
for workload in statefulset/crewmeister-mysql deployment/crewmeister-app statefulset/prometheus-crewmeister-monitoring-prometheus deployment/crewmeister-grafana deployment/crewmeister-mysql-exporter; do
    aws_kube rollout status "$workload" --timeout=300s
done
aws_kube --namespace kube-system rollout status deployment/aws-load-balancer-controller --timeout=300s
aws_kube get pvc db-volume-crewmeister-mysql-0 --output=json | jq -e '.status.phase == "Bound" and .spec.storageClassName == "crewmeister-gp3"' >/dev/null || aws_fail 'MySQL PVC is not Bound to crewmeister-gp3.'
aws_kube get service crewmeister-app crewmeister-mysql crewmeister-grafana crewmeister-monitoring-prometheus --output=json | jq -e 'all(.items[]; .spec.type == "ClusterIP")' >/dev/null || aws_fail 'Application/database/monitoring services must be ClusterIP.'
expected_image="$(jq -r '.image_repository + ":" + .image_tag' "$aws_config_file")"
aws_kube get deployment crewmeister-app --output=json | jq -e --arg image "$expected_image" '[.spec.template.spec.containers[] | select(.name == "application")] | length == 1 and .[0].image == $image' >/dev/null || aws_fail 'Deployed image does not match the configured GHCR SHA.'
aws_kube get storageclass crewmeister-gp3 --output=json | jq -e '.provisioner == "ebs.csi.aws.com" and .reclaimPolicy == "Delete" and .parameters.encrypted == "true"' >/dev/null || aws_fail 'EBS storage configuration mismatch.'
aws_kube get nodes -o wide
aws_kube get pods,pvc,ingress
echo 'Read-only infrastructure checks passed. API writes, persistence recreation and HTTP/monitoring checks remain explicit acceptance checks in docs/aws-deployment.md.'
