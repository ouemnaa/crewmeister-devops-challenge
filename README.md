# Crewmeister DevOps challenge

A Java 17 / Spring Boot 3.5.16 user API, deployed on Kubernetes with Terraform and Helm, built and scanned by GitHub Actions, and monitored with Prometheus and Grafana. The same application chart runs on a **local Kind cluster** (free, the main path) and on **AWS EKS** (optional, shown in a video).

[![CI](https://github.com/ouemnaa/crewmeister-devops-challenge/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/ouemnaa/crewmeister-devops-challenge/actions/workflows/ci.yml)

[Quick start](#quick-start-local) · [How it works](#how-it-works) · [CI pipeline](#ci-pipeline) · [AWS EKS](#aws-eks-optional) · [Limitations](#known-limitations)

## Overview

| | Local: Kind (main path) | Cloud: AWS EKS (optional) |
| --- | --- | --- |
| Who runs it | You, with one script | The author, shown in the video below |
| Cost | Free, no cloud account | About $6 per day while running |
| Status | Tested on Windows 11 and WSL2 Ubuntu | Verified on 3 November 2026 from Windows; temporary |
| Start here | [Quick start](#quick-start-local) | [AWS EKS](#aws-eks-optional) |

```mermaid
flowchart LR
    push([git push]) --> ci["GitHub Actions: test, scan, build"]
    ci -->|"only on main, after all checks pass"| ghcr[("GHCR image tagged with commit SHA")]

    subgraph local ["Local path - Kind, primary"]
        setup["Setup script"] --> tf1["Terraform: cluster, then platform"]
        tf1 --> kind["Kind cluster"]
        kind --> app1["Helm releases: app, MySQL, monitoring"]
    end

    subgraph aws ["AWS path - EKS, optional"]
        tf2["Terraform: bootstrap, cluster, platform"] --> eks["EKS cluster"]
        eks --> app2["Same Helm chart and monitoring"]
    end

    ghcr --> app1
    ghcr --> app2
```


### 🎬 AWS EKS Deployment Demo

Watch the application running on Amazon EKS, including Kubernetes workloads,
persistent MySQL storage, Prometheus, Grafana, and API verification.

<p align="center">
  <a href="https://youtu.be/O4EGeSubWZ8">
    <img
      src="https://img.youtube.com/vi/O4EGeSubWZ8/hqdefault.jpg"
      alt="Watch the Crewmeister AWS EKS deployment demo"
      width="560"
    />
  </a>
</p>

<p align="center">
  <strong>
    <a href="https://youtu.be/O4EGeSubWZ8">
      ▶ Watch the AWS EKS Deployment Walkthrough
    </a>
  </strong>
</p>


## Requirements and where they are

| Assessment requirement | Implementation | Read next |
| --- | --- | --- |
| Dockerfile | [Dockerfile](Dockerfile): multi-stage build, pinned base images, non-root runtime | [Image delivery](#image-delivery) |
| Helm chart | [helm/crewmeister-app](helm/crewmeister-app): Deployment, Service, configuration, probes, ServiceMonitor | [Helm](#helm) |
| Terraform interacting with Kubernetes | [terraform/cluster](terraform/cluster) and [terraform/platform](terraform/platform): Kind, namespace, Secrets and Helm releases | [Terraform ownership](#terraform-ownership) |
| Any cloud provider | [terraform/aws](terraform/aws): AWS EKS extension with separate state | [AWS EKS (optional)](#aws-eks-optional) |
| Runs locally | [scripts](scripts): PowerShell and Bash setup, verification and teardown | [Quick start](#quick-start-local) |
| GitHub CI | [.github/workflows/ci.yml](.github/workflows/ci.yml): tests, validation, scans, gated image publishing | [CI pipeline](#ci-pipeline) |
| Monitoring | [monitoring](monitoring): Prometheus, MySQL exporter and provisioned Grafana dashboard | [Open monitoring](#3-open-monitoring) |

## Quick start (local)

Deploy the complete stack on a local Kind cluster with Terraform and Helm. **No AWS account or host Java installation is required.**

**You need:** Docker Desktop or Docker Engine running Linux containers (at least 4 CPUs and 6 GiB RAM), Terraform **1.15.8**, Kind **0.33.0**, kubectl **1.35–1.37**, Helm **4.3.1**, and Git. Setup enforces the Terraform and Kind versions. The first Windows deployment took approximately **11 minutes**.

### 1. Deploy and verify

Choose the commands for your environment. **Setup, verification, and teardown must all run from the same environment and checkout.**

#### Windows — PowerShell

```powershell
git clone https://github.com/ouemnaa/crewmeister-devops-challenge.git
cd crewmeister-devops-challenge
.\scripts\setup.ps1
.\scripts\verify.ps1
```

Docker Desktop must be running in **Linux containers** mode. If PowerShell blocks a script, run it in a separate process with `powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1` (and similarly for `verify.ps1`). This does not change the machine-wide execution policy.

#### WSL2 / Linux / macOS — Bash

```bash
git clone https://github.com/ouemnaa/crewmeister-devops-challenge.git
cd crewmeister-devops-challenge
bash scripts/setup.sh
bash scripts/verify.sh
```

The Bash deployment was tested on **WSL2 Ubuntu**. Native Linux and macOS are **not yet tested**, and the published image is `linux/amd64` only; Apple Silicon compatibility is not established. In WSL2, use Linux CLI binaries and enable Docker Desktop integration for your distribution.

<details>
<summary>Tool versions, environment checks, and additional requirements</summary>

| Tool | Required / tested version |
| --- | --- |
| Docker Engine | 28.0.4 tested; Linux containers |
| Terraform | 1.15.8 (enforced) |
| Kind | 0.33.0 (enforced) |
| kubectl | 1.35–1.37 (1.36.4 tested) |
| Helm | 4.3.1 tested |
| PowerShell | 5.1+ |
| Bash | 5.1+, with curl 7.81+ |
| Git | 2.x |

Check your tools before starting if needed:

```text
terraform version
kind version
kubectl version --client
helm version --short
docker info --format '{{.OSType}}'
```

Docker must report `linux`. Allocate **8 GiB RAM** for extra build headroom when possible. Docker needs internet access to GitHub, Maven Central, Helm chart repositories and container registries. The Dockerfile builds with Java 17, so no host JDK is necessary.

Kind prefers cgroup v2; the setup can enable Kubernetes cgroup-v1 compatibility without modifying the host. WSL2 requires Docker Desktop integration. Use binaries built for your OS and CPU architecture. Do not mix Windows and WSL lifecycle commands in one checkout.

</details>

Setup provisions one Kind node and **four Helm releases**: MySQL, Spring Boot application, monitoring, and MySQL Exporter. The scripts use `.local/crewmeister.kubeconfig` and the `kind-crewmeister` context instead of your default kubeconfig. Verification checks deployment readiness, GET/POST API behavior, persistent data, health and metrics endpoints, Prometheus targets, and Grafana.

<p align="center">
  <a href="docs/screenshots/local-setup-progress.png"><img src="docs/screenshots/local-setup-progress.png" width="560" alt="Local Terraform apply showing application workloads and a bound MySQL PVC"></a>
  <br>
  <sub>Setup in progress: the MySQL volume is bound while Prometheus is still starting. Click to enlarge.</sub>
</p>

Verification checks nodes, workloads, storage, seeded GET, POST and persisted readback, health, metrics, Prometheus targets and the authenticated Grafana dashboard. It removes its test row and temporary port-forwards. It does not replace the separately recorded MySQL pod-recreation persistence test in [validation evidence](docs/validation.md).

### 2. Test the API

Keep this port-forward running in one terminal, from the repository root:

```bash
kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister -n crewmeister port-forward --address localhost service/crewmeister-app 18080:8080
```

Then make requests from a **second terminal**.

**PowerShell:**

```powershell
Invoke-RestMethod 'http://localhost:18080/user?id=1'
Invoke-RestMethod 'http://localhost:18080/user' -Method Post -ContentType 'application/json' -Body '{"name":"Reviewer"}'
```

**Bash:**

```bash
curl --fail 'http://localhost:18080/user?id=1'
curl --fail -H 'Content-Type: application/json' --data '{"name":"Reviewer"}' 'http://localhost:18080/user'
```

The GET request returns the **Alice** greeting seeded by Flyway. POST stores a new user in MySQL and returns a greeting (not the generated user ID). Use only dummy data.

### 3. Open monitoring

Run each port-forward in a **separate terminal** from the repository root:

```bash
# Grafana
kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister -n crewmeister port-forward --address localhost service/crewmeister-grafana 13000:80
```

```bash
# Prometheus
kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister -n crewmeister port-forward --address localhost service/crewmeister-monitoring-prometheus 19090:9090
```

| Service | Local URL |
| --- | --- |
| Spring Boot API | http://localhost:18080 |
| Grafana | http://localhost:13000 |
| Prometheus | http://localhost:19090 |

If a local port is already in use, change the number **before the colon** in the corresponding port-forward and use the matching URL. MySQL (3306) and MySQL Exporter (9104) remain internal; the Kind Kubernetes API uses a random localhost port.

<details>
<summary>Log in to Grafana using the generated administrator password</summary>

The Grafana username is `admin`; there is no `admin/admin` default. In PowerShell, copy the password to the clipboard without printing it:

```powershell
$secret = kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister -n crewmeister get secret crewmeister-grafana-admin -o json | ConvertFrom-Json
$grafanaPassword = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($secret.data.'admin-password'))
Set-Clipboard -Value $grafanaPassword
Remove-Variable secret, grafanaPassword
```

Replace clipboard contents with non-sensitive text after logging in. Do not record the Secret or clipboard.

Bash can capture the password without printing it:

```bash
grafana_password="$(kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister -n crewmeister get secret crewmeister-grafana-admin -o go-template --template='{{index .data "admin-password" | base64decode}}')"
```

Transfer the password with your local clipboard utility, then `unset grafana_password`. Bash clipboard integration varies by OS and has not been validated; WSL2 users can use the Windows PowerShell clipboard method against the same checkout.

</details>

In Grafana, open **Dashboards → Crewmeister → Crewmeister application**. The provisioned panels show availability, request rate, latency, HTTP errors, JVM memory, restarts, MySQL health, and connections. Generate API traffic if the graphs are initially empty.

In Prometheus, query `up{namespace="crewmeister",service="crewmeister-app"}` and `mysql_up{namespace="crewmeister",service="crewmeister-mysql-exporter"}`; each should return `1` when healthy.

<table>
  <tr>
    <td align="center" valign="top"><a href="docs/screenshots/grafana-dashboard.png"><img src="docs/screenshots/grafana-dashboard.png" width="260" alt="Provisioned Grafana dashboard with live application and JVM data"></a><br><sub>Grafana dashboard with live data</sub></td>
    <td align="center" valign="top"><a href="docs/screenshots/prometheus-application-up.png"><img src="docs/screenshots/prometheus-application-up.png" width="260" alt="Prometheus query showing the application target up"></a><br><sub>Prometheus: application UP</sub></td>
    <td align="center" valign="top"><a href="docs/screenshots/prometheus-mysql-up.png"><img src="docs/screenshots/prometheus-mysql-up.png" width="260" alt="Prometheus query showing MySQL up"></a><br><sub>Prometheus: MySQL UP</sub></td>
  </tr>
</table>

<sub>Click an image to enlarge.</sub>

### 4. Tear down the local environment

Stop any manual port-forwards with **Ctrl+C**. Then use the same environment you used for setup.

**PowerShell:**

```powershell
.\scripts\down.ps1
```

**Bash:**

```bash
bash scripts/down.sh
```

The script destroys the **platform first, then the Kind cluster**, with resource identity checks. **This deletes the demonstration database.** Do not discard local state or the dedicated kubeconfig before teardown completes.

## How it works

The local environment is provisioned in two stages: Terraform first creates Kind, then uses the dedicated kubeconfig to install the application and supporting services through Helm. The AWS environment uses separate Terraform configurations and state.

### Terraform ownership

- `terraform/cluster/` manages the local Kind cluster.
- `terraform/platform/` manages the local namespace, generated Secrets, and Helm releases.
- Each root keeps an **independent local Terraform state**. AWS does not reuse either state.

Terraform state can contain generated database and Grafana passwords **in plaintext**, even when Terraform marks values sensitive. State, saved plans, private inputs and kubeconfigs are excluded from Git; provider lock files are committed.

### Helm

Terraform manages four Helm releases: **MySQL, application, kube-prometheus-stack, and MySQL Exporter**. The application chart lives in [`helm/crewmeister-app/`](helm/crewmeister-app); upstream chart versions are pinned to MySQL `3.1.5`, kube-prometheus-stack `92.17.0` and prometheus-mysql-exporter `2.16.0`. The MySQL 8.4 image is pinned by digest.

### Kubernetes runtime

The Spring Boot app communicates with MySQL over its internal service. Prometheus scrapes application and MySQL exporter metrics, and Grafana visualizes them. The local deployment exposes **no public Kubernetes Services**: access is through `kubectl port-forward`. The MySQL PVC survives pod replacement; teardown deletes the demonstration data. Prometheus uses ephemeral local storage with a six-hour retention period.

The application runs as non-root UID `10001`, drops capabilities, uses a read-only root filesystem, disables service-account-token mounting, and has startup, liveness, and database-aware readiness probes.

### Image delivery

The default image is `ghcr.io/ouemnaa/crewmeister-devops-challenge:<full-commit-SHA>`. Local setup selects an existing public image when the checkout is eligible; otherwise, `auto` mode builds and imports an image into Kind. Registry images use `IfNotPresent`; local images use pull policy `Never`. No path uses `latest`.

Set `CREWMEISTER_IMAGE_MODE=local` to force a build or `registry` to require an already published image. `CREWMEISTER_IMAGE_TAG` and `CREWMEISTER_IMAGE_REPOSITORY` allow overrides.

**Want the detailed diagrams?** See [Technical architecture](docs/architecture.md) for the local Terraform sequence, Helm resource mapping, Kubernetes runtime, image selection, and AWS state flow.

## CI pipeline

[The GitHub Actions workflow](.github/workflows/ci.yml) runs for pull requests to `main`, pushes to `main`, and manual dispatch. The test, infrastructure, and secret-scanning jobs run in parallel; image building waits for all three.

```mermaid
flowchart LR
    t([PR, push to main, or manual run]) --> test["test: build and 6 integration tests"]
    t --> infra["infrastructure: Helm, Terraform, script checks"]
    t --> secrets["secrets: Gitleaks over full history"]
    test --> image["image: build, Trivy scan, SBOM"]
    infra --> image
    secrets --> image
    image --> gate{"Push to main?"}
    gate -->|"yes"| publish["publish: push to GHCR with SHA tag"]
    gate -->|"no"| skip(["No publishing on PRs or manual runs"])
```

| Job | What it checks or produces | When it runs |
| --- | --- | --- |
| `test` (Build and test) | Java 17 build, six integration tests against disposable MySQL, test reports; optional SonarCloud step | Every trigger |
| `infrastructure` (Validate infrastructure) | Helm lint and render for local and AWS values, monitoring and dashboard checks, all five Terraform roots, PowerShell parsing and offline AWS guard tests, Bash syntax | Every trigger |
| `secrets` (Scan Git history for secrets) | Full-history Gitleaks scan; detected secrets fail the job, output is redacted | Every trigger |
| `image` (Build and scan image) | One Docker build, Trivy OS and Java reports, CycloneDX SBOM; scanner errors fail the job | After the first three jobs pass |
| `publish` (Publish image) | Publishes the already scanned image with the full commit SHA and checks anonymous GHCR access | Push to `main` only, after all earlier jobs pass |

Pull requests and manual runs cannot publish. Only `publish` has package-write permission. CI publishes a container image; it does not commit code or deploy Kubernetes or AWS. Actions and scanners are pinned to immutable revisions; Dependabot checks Actions, Docker and Maven weekly.

SonarCloud analyses the repository through its own GitHub integration, which needs no token and is separate from the workflow. The workflow also has an optional Sonar step inside `test`; it runs only on pushes to `main` when the required repository variables and token exist. The recorded pre-submission run skipped that step.

<p align="center">
  <a href="docs/screenshots/sonarcloud-analysis.png"><img src="docs/screenshots/sonarcloud-analysis.png" width="480" alt="SonarCloud overview with a passed quality gate and one low-severity security issue"></a>
  <br>
  <sub>SonarCloud: quality gate passed, one low-severity finding left open. Click to enlarge.</sub>
</p>

## AWS EKS (optional)

**Reviewers are not expected to deploy AWS.** The Kind quick start reproduces the complete assessment without cloud charges. AWS is an optional, temporary demonstration of the same application, published image and Helm chart on a managed Kubernetes cluster.

<p align="center">
  <a href="https://youtu.be/O4EGeSubWZ8"><img src="https://img.youtube.com/vi/O4EGeSubWZ8/hqdefault.jpg" width="320" alt="AWS EKS deployment demo on YouTube"></a>
  <br>
  <sub>▶ <a href="https://youtu.be/O4EGeSubWZ8">Watch the AWS EKS deployment</a></sub>
</p>

The AWS Terraform roots create a protected S3 state bucket, a dedicated VPC with two public subnets, EKS, one On-Demand `m7i-flex.large` worker, Pod Identity associations, encrypted gp3 MySQL storage, and the Helm workloads. Public API ingress uses an ALB; there is no NAT gateway. This single-node setup is a demonstration, **not a high-availability production deployment**.

```mermaid
flowchart LR
    client(["API client"]) --> alb["ALB, only the /user path"]

    subgraph vpc ["Dedicated VPC, two public subnets"]
        alb --> app["Application pod"]
        app --> mysql["MySQL pod"]
        mysql --> ebs[("Encrypted EBS volume")]
        node["One EKS worker node"]
    end

    eks["EKS control plane, managed by AWS"] --> node
    tf["Terraform: bootstrap, cluster, platform"] --> eks
    tf --> s3[("S3 state bucket")]
    ghcr[("GHCR image")] --> app
```

The bootstrap state stays local under `.local/aws/`; cluster and platform state live in **separate S3 objects with native locking**. State is isolated from Kind. See [Technical architecture](docs/architecture.md#aws-state-and-dependency-flow) and the [AWS deployment guide](docs/aws-deployment.md) for the full workflow.

**Cost:** about **$0.25 per hour, or $6 per day**, with ingress, before credits, taxes, transfer and extra storage. This is a historical estimate, not a spending cap. Idle pods do not stop infrastructure charges.

**Status:** deployed and verified on **3 November 2026** from Windows PowerShell. The cluster is temporary because of its cost and will be destroyed after the review period; this video and the screenshots stay as evidence. The ordered teardown steps are in the AWS guide. A completed teardown and leftover audit are not yet recorded.

<table>
  <tr>
    <td align="center" valign="top"><a href="docs/screenshots/aws/aws-workload-status.png"><img src="docs/screenshots/aws/aws-workload-status.png" width="260" alt="EKS workload summary with running resources"></a><br><sub>EKS workloads running</sub></td>
    <td align="center" valign="top"><a href="docs/screenshots/aws/aws-running-pods.png"><img src="docs/screenshots/aws/aws-running-pods.png" width="260" alt="EKS pod list with the application and monitoring pods running"></a><br><sub>Application and monitoring pods</sub></td>
    <td align="center" valign="top"><a href="docs/screenshots/aws/aws-load-balancer.png"><img src="docs/screenshots/aws/aws-load-balancer.png" width="260" alt="ALB listener with a default 404 response"></a><br><sub>ALB: default 404, only /user routed</sub></td>
  </tr>
</table>

<sub>Click an image to enlarge.</sub>

**Public access during the demo:** The EKS management endpoint is restricted to the administrator's approved IP. The ALB accepts IPv4 traffic from **any source IP** while the demo is live, but routes only the exact `/user` path (including query strings); other paths, including public Actuator and Grafana endpoints, receive 404. Grafana and Prometheus themselves remain private and are accessed by localhost port-forwarding. **The public API uses unauthenticated HTTP; use dummy data only and limit the exposure window.**

The environment is provisioned through temporary AWS credentials, private account-specific configuration and a separately owned S3 backend. For replication, reviewers must use **their own account, credentials, backend bucket and approved Terraform plans**. The [AWS deployment guide](docs/aws-deployment.md) explains setup, verification and the ordered teardown. A full deployment in a second AWS account has not been validated.

## Design decisions

- **Two local Terraform stages:** the cluster exists before the Helm providers connect to it.
- **Full commit-SHA image tags:** each image maps to a source revision, and a local-build fallback keeps unpublished checkouts runnable.
- **CI publishes but does not deploy:** repository activity never triggers cloud changes or costs.
- **Kind for the local path:** reviewers can run Kubernetes without a cloud account.
- **Pod Identity on AWS:** the tested account blocked creation of an IAM OIDC provider, and Pod Identity gives each workload its own role without one.
- **Separate, protected S3 state on AWS:** cloud resources never share state with the local Kind setup.
- **Trivy is report-only:** inherited application vulnerabilities stay visible instead of being hidden, and scanner errors still fail CI.
- **SonarCloud through its GitHub integration:** analysis needs no token, so local reviewers need no extra setup.

## Known limitations

- **Security scan:** the image scan on 3 November 2026 reported 2 critical findings in `spring-webmvc` 6.2.19 (CVE-2026-47884, CVE-2026-47890), fixed only in Spring Framework 7. They are open; fixing them needs a major Spring Boot upgrade. Details are in [validation evidence](docs/validation.md#critical-findings-unchanged).
- **Platforms:** tested on Windows 11 with Docker Desktop and on WSL2 Ubuntu. Native Linux, macOS and Apple Silicon are untested, and the published image is `linux/amd64` only.
- **Scope and public exposure:** one node, no high availability or backups. The temporary AWS ALB permits unauthenticated HTTP traffic to `/user` from any IPv4 address while live; dummy data only, with prompt teardown recommended. Teardown deletes the MySQL data.
  
## Repository layout

```text
Dockerfile                    Application container build
helm/crewmeister-app/         Application chart and local/AWS values
terraform/cluster/            Local Kind cluster stage
terraform/platform/           Local namespace, Secrets and releases
terraform/aws/                Separate bootstrap, cluster and platform roots
monitoring/                   Shared values, exporter and Grafana dashboard
scripts/                      PowerShell/Bash lifecycle and verification
.github/workflows/ci.yml      CI checks and gated GHCR publishing
src/                          Application, migrations and integration tests
docs/                         Assessment, architecture, validation, AWS guide and screenshots
```

More detail: the [original assessment](docs/assessment.md), [technical architecture](docs/architecture.md), [validation evidence](docs/validation.md), and [AWS deployment guide](docs/aws-deployment.md).
