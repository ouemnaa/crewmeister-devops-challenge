# Validation evidence

Validation performed on 2026-11-02. Local tools: Docker Engine 28.0.4 with Linux containers, Terraform 1.15.8, Kind 0.33.0, Kubernetes/kubectl 1.36.4 and Helm 4.3.1. The host uses cgroup v1; the documented compatibility setting was exercised.

| Check | Result |
| --- | --- |
| Java 17 / MySQL integration tests after dependency updates | Six tests passed, none skipped |
| Multi-stage Docker build | Passed; application runs as user 10001 |
| Terraform formatting and validation | Both stages passed; provider locks retained |
| Application Helm chart | Strict lint and rendering passed with monitoring enabled and disabled |
| GitHub Actions syntax | actionlint passed |
| PowerShell setup and verification | Passed with the updated application and monitoring |
| Git Bash verification | Passed, including authenticated provisioned Grafana dashboard access |
| Prometheus | Application target UP and MySQL exporter reports database UP |
| Provisioned Grafana dashboard | All eight panel queries returned data after live API traffic |
| Native Linux verification | Passed on Ubuntu 22.04 under WSL using Linux binaries |
| Gitleaks history scan | No secrets detected; synthetic token fixture correctly rejected |
| CycloneDX SBOM | Generated successfully; 210 components in the local image scan |
| Trivy OS and Java scan | 2 CRITICAL, 0 HIGH, 28 MEDIUM, 4 LOW; report-only policy documented in README |

Earlier lifecycle checks covered PowerShell and Git Bash setup, verification and guarded teardown, including repeated teardown, absent-cluster failure and refusal of missing-state or mismatched-API targets. An unrelated sentinel container and volume survived teardown. API data survived application and MySQL pod replacement. Native Linux containers also ran the application tests and infrastructure checks independently of Windows binaries.

A fresh clone was deployed using native Linux Terraform, Kind, kubectl and Helm under WSL. The complete cluster and four releases were created without carrying over Terraform state or credentials. Monitoring configuration updates were then applied through Terraform and verified in both native Linux Bash and Windows PowerShell. These checks exposed and resolved a background port-forward log creation race and insufficient monitoring startup grace. Grafana's unused plugin downloads are disabled; replacement Grafana and kube-state-metrics pods became healthy with no restarts during validation. Registry DNS briefly failed during the cold run and Kubernetes retried the pull successfully.

Native Linux teardown then destroyed all 11 platform resources and the Kind cluster successfully. No project node containers remained. The test environment was left removed after validation; run setup to create it again.

The [hosted CI run for d078fce](https://github.com/ouemnaa/crewmeister-devops-challenge/actions/runs/41517004402) passed tests, infrastructure validation, image scanning, GHCR publishing and anonymous package access. Later local commits require a push to receive hosted validation. No claim is made that the newer workflow has already run on GitHub.

SonarCloud is conditional on repository configuration and credentials; no live SonarCloud analysis was performed. macOS instructions are supplied, but a native macOS machine was not available for execution. A production rollout, cloud infrastructure and production security certification are outside this local assessment.
