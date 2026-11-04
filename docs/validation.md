# Validation Summary

The project was validated through automated CI checks and end-to-end deployment testing.

| Area | Validation |
|---|---|
| Application | Six Java/MySQL integration tests passed |
| Local deployment | Fresh Windows setup, verification and teardown passed |
| Linux compatibility | Complete lifecycle previously validated on WSL2 Ubuntu |
| Infrastructure | Terraform validation and Helm lint/render checks passed |
| API | GET/POST operations and database persistence verified |
| Monitoring | Prometheus targets UP and Grafana dashboard operational |
| Persistence | MySQL data survived pod recreation |
| CI/CD | GitHub Actions checks passed; container image published to GHCR |
| AWS | EKS deployment, application, storage and monitoring verified |

### Known limitations

- Native Linux, macOS and ARM64 deployments have not been validated.
- The published container image supports `linux/amd64`.
- Trivy reports two unresolved critical-severity dependency findings; details are disclosed in the README.
- The AWS environment is a temporary, single-node demonstration.

For supporting evidence, see the [GitHub Actions workflow](../.github/workflows/ci.yml), screenshots in the README, and the AWS deployment video.
