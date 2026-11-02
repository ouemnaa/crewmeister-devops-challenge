#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
[[ ! -d .local/bin ]] || export PATH="$repo_root/.local/bin:$PATH"
export KIND_EXPERIMENTAL_PROVIDER=docker

fail() { echo "$*" >&2; exit 1; }
for tool in docker kind kubectl curl; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required tool is missing: $tool."
done
kube=(kubectl --kubeconfig "$repo_root/.local/crewmeister.kubeconfig" --context kind-crewmeister --namespace crewmeister)
name="verify-$(date +%s)-$$-$RANDOM"
log_prefix="$repo_root/.local/$name"
forward_pid=''
monitor_pids=()
post_attempted=false

query_mysql() {
    printf '%s\n' "$1" | "${kube[@]}" exec -i crewmeister-mysql-0 --container=mysql -- bash -ec \
        'MYSQL_PWD=$MYSQL_PASSWORD mysql --protocol=TCP --host=127.0.0.1 --user=$MYSQL_USER --database=$MYSQL_DATABASE --batch --skip-column-names'
}

cleanup() {
    result=$?
    trap - EXIT
    if [[ "$post_attempted" == true ]]; then
        if ! query_mysql "DELETE FROM user WHERE name = '$name';" >/dev/null; then
            echo 'Verification user cleanup failed.' >&2
            result=1
        fi
    fi
    if [[ -n "$forward_pid" ]]; then
        kill "$forward_pid" 2>/dev/null || true
        wait "$forward_pid" 2>/dev/null || true
    fi
    for pid in "${monitor_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    done
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

clusters="$(kind get clusters)"
[[ $'\n'"$clusters"$'\n' == *$'\ncrewmeister\n'* ]] || fail 'Project cluster is absent. Run setup first.'
"${kube[@]}" get node crewmeister-control-plane --output=name
"${kube[@]}" wait --for=condition=Ready nodes --all --timeout=180s
"${kube[@]}" rollout status statefulset/crewmeister-mysql --timeout=300s
"${kube[@]}" rollout status deployment/crewmeister-app --timeout=300s
"${kube[@]}" wait --for=create statefulset/prometheus-crewmeister-monitoring-prometheus --timeout=180s
for workload in statefulset/prometheus-crewmeister-monitoring-prometheus deployment/crewmeister-grafana deployment/crewmeister-mysql-exporter; do
    "${kube[@]}" rollout status "$workload" --timeout=300s
done
[[ "$("${kube[@]}" get pvc db-volume-crewmeister-mysql-0 --output='jsonpath={.status.phase}')" == Bound ]] || fail 'MySQL PVC is not Bound.'
[[ "$("${kube[@]}" get service crewmeister-app crewmeister-mysql --output='jsonpath={.items[*].spec.type}')" == 'ClusterIP ClusterIP' ]] || fail 'Project services must be internal ClusterIP services.'
[[ "$(query_mysql 'SELECT 1;')" == 1 ]] || fail 'MySQL is not responding.'

"${kube[@]}" port-forward --address 127.0.0.1 service/crewmeister-app :8080 >"$log_prefix.log" 2>"$log_prefix.err" &
forward_pid=$!
port=''
for attempt in {1..30}; do
    kill -0 "$forward_pid" 2>/dev/null || fail "Port forwarding failed. See $log_prefix.err."
    port="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "$log_prefix.log")"
    [[ -z "$port" ]] || break
    sleep 1
done
[[ -n "$port" ]] || fail 'Port forwarding did not become ready.'
base_url="http://127.0.0.1:$port"
http=(curl --fail --silent --show-error --connect-timeout 5 --max-time 10)
[[ "$("${http[@]}" "$base_url/user?id=1")" == 'Greetings from Crewmeister, Alice!' ]] || fail 'Seeded GET /user failed.'
post_attempted=true
created="$("${http[@]}" -H 'Content-Type: application/json' --data "{\"name\":\"$name\"}" "$base_url/user")"
[[ "$created" == "Greetings from Crewmeister, $name!" ]] || fail 'POST /user failed.'
id="$(query_mysql "SELECT id FROM user WHERE name = '$name';")"
[[ "$id" =~ ^[0-9]+$ ]] || fail 'POST /user did not persist a record.'
[[ "$("${http[@]}" "$base_url/user?id=$id")" == "$created" ]] || fail 'Created user could not be retrieved.'
for path in /actuator/health /actuator/health/readiness /actuator/health/liveness; do
    health="$("${http[@]}" "$base_url$path")"
    [[ "$health" =~ \"status\"[[:space:]]*:[[:space:]]*\"UP\" ]] || fail "Health check failed: $path."
done
metrics="$("${http[@]}" "$base_url/actuator/prometheus")"
[[ "$metrics" == *jvm_memory_used_bytes* && "$metrics" == *http_server_requests_seconds_count* ]] || fail 'Expected JVM and HTTP metrics are missing.'
for service in crewmeister-monitoring-prometheus:9090 crewmeister-grafana:80; do
    prefix="$log_prefix-${service%:*}"
    "${kube[@]}" port-forward --address 127.0.0.1 "service/${service%:*}" ":${service##*:}" >"$prefix.log" 2>"$prefix.err" &
    monitor_pids+=("$!")
    port=''
    for attempt in {1..30}; do
        kill -0 "${monitor_pids[${#monitor_pids[@]}-1]}" 2>/dev/null || fail "Monitoring port forwarding failed. See $prefix.err."
        port="$(sed -n 's/^Forwarding from 127\.0\.0\.1:\([0-9][0-9]*\).*/\1/p' "$prefix.log")"
        [[ -z "$port" ]] || break
        sleep 1
    done
    [[ -n "$port" ]] || fail 'Monitoring port forwarding did not become ready.'
    url="http://127.0.0.1:$port"
    if [[ "$service" == crewmeister-monitoring-prometheus:* ]]; then
        up=false
        for attempt in {1..100}; do
            result="$("${http[@]}" --get --data-urlencode 'query=up{namespace="crewmeister",service="crewmeister-app"}' "$url/api/v1/query")"
            if [[ "$result" =~ \"value\":\[[^]]*,\"1\"\] ]]; then up=true; break; fi
            sleep 3
        done
        [[ "$up" == true ]] || fail 'Prometheus application target is not UP.'
    else
        health="$("${http[@]}" "$url/api/health")"
        [[ "$health" =~ \"database\"[[:space:]]*:[[:space:]]*\"ok\" ]] || fail 'Grafana is unhealthy.'
        password="$("${kube[@]}" get secret crewmeister-grafana-admin --output=go-template --template='{{index .data "admin-password" | base64decode}}')"
        dashboard="$("${http[@]}" --user "admin:$password" "$url/api/dashboards/uid/crewmeister")"
        [[ "$dashboard" == *'"provisioned":true'* && "$dashboard" == *'"uid":"crewmeister"'* ]] || fail 'Grafana dashboard is not provisioned.'
        unset password dashboard
    fi
done

echo 'Verification passed: cluster, workloads, storage, GET/POST persistence, health, Prometheus target, and Grafana dashboard.'
