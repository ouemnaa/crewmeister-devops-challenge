# Crewmeister Challenge

## Background

At Crewmeister, our development team is continuously growing. We aim to hire the best educated, motivated, and enthusiastic people in the field who have fun building up Crewmeister in our vision to empower small businesses to thrive in a digital world. For this quest, we are continuously getting new applicants from all over the world. To filter which candidates could be a good fit, we provide our candidates with a coding challenge that we manually review and evaluate.

---

## DevOps Engineer Task

As a DevOps Engineer at Crewmeister, you will be in charge of several challenging tasks in your daily work. One of your core responsibilities will be to ensure that the system is always running smoothly and that the application is deployed successfully to our customers.

In this challenge, you should use DevOps best practices to architect and implement the complete cycle of building, packaging, and deploying a Java application (specified later in this document). 

The following are core technologies/tools that should be present in the solution:

- Dockerfile
- Helm Chart
- Terraform to interact with the Kubernetes cluster

You have the flexibility to utilize any cloud provider of your choice to deploy and run the application effectively. Additionally, it should be designed to operate seamlessly on local machines, allowing for a versatile setup that caters to various operational preferences and environments.

## Plus:

- Create a CI Pipeline in Github to automate the application lifecycle

- Add monitoring tools to check the health of the application

## Important Points:

- At Crewmeister, we value creativity and pushing for better. You are encouraged to expand the solution as you find fit. To do so, you must ensure high-quality documentation and that the base solution is correctly executed.
- All the tools used must be publicly accessible or explicitly documented on how to authenticate.
- All the tools must be free to use.

 ## Submission:
- Provide the link to your GitHub repository in the Greenhouse submission form.
- Submit your completed project via the Greenhouse link in the email received from the Recruitment Manager.

## Challenge Application

A Spring Boot application that provides a simple user management REST API.

### Technologies Used

- Java 17
- Spring Boot 3.3.5
- MySQL Database
- Flyway Migration
- Maven
- Spring Data JPA
- Spring Actuator

### Pre-requisites

- JDK 17
- MySQL
- Maven

### API Endpoints

#### GET /user

Retrieves a user by ID

#### POST /user

Creates a new user

### Running integration tests

Use Java 17 and a running MySQL database named `challenge`. The database account
must be able to create tables and read and write data. Use a disposable database:
Flyway applies the schema and inserts the initial user, Alice, with ID 1.
The database username and password must be supplied through the environment;
the application has no default database credentials.

Set both database URLs. The application uses `SPRING_DATASOURCE_URL`, while
Flyway uses `SPRING_DATASOURCE_WRITER_URL`.

PowerShell:

```powershell
$env:SPRING_DATASOURCE_URL = 'jdbc:mysql://127.0.0.1:3306/challenge'
$env:SPRING_DATASOURCE_WRITER_URL = $env:SPRING_DATASOURCE_URL
$env:SPRING_DATASOURCE_USERNAME = 'crewmeister'
$env:SPRING_DATASOURCE_PASSWORD = '<local-database-password>'
.\mvnw.cmd clean verify
```

Linux / macOS / WSL:

```bash
export SPRING_DATASOURCE_URL='jdbc:mysql://127.0.0.1:3306/challenge'
export SPRING_DATASOURCE_WRITER_URL="$SPRING_DATASOURCE_URL"
export SPRING_DATASOURCE_USERNAME='crewmeister'
export SPRING_DATASOURCE_PASSWORD='<local-database-password>'
bash ./mvnw clean verify
```

Replace the password and connection settings with those of your test database.
The tests start the application on a random HTTP port, check the migrated user,
create and retrieve a user through the API, and check application health.
Test-created users have unique names and are removed after the POST test.

### Health and metrics

The application exposes the following Actuator endpoints on its HTTP port:

| Endpoint | Purpose |
| --- | --- |
| `/actuator/health` | Overall application health, including MySQL connectivity |
| `/actuator/health/liveness` | Application liveness, independent of database availability |
| `/actuator/health/readiness` | Readiness to receive traffic, including MySQL connectivity |
| `/actuator/prometheus` | Prometheus metrics, including JVM memory and HTTP request counts and timings |

Probe endpoints are enabled in local environments as well as Kubernetes.
The integration tests check both probes and confirm JVM and HTTP metrics are exposed.

### Building and running the Docker image

Use Docker with Linux containers. The multi-stage build uses the Maven wrapper
and Java 17, so a host JDK or Maven installation is not required to build the image.
Both Eclipse Temurin base images are pinned by digest. The runtime contains the
application JAR and a JRE and runs as user `10001:10001`.

```text
docker build --tag crewmeister-app:local .
```

Integration tests require MySQL and run separately with `mvnw clean verify`;
the image build packages the application with tests skipped.

For a disposable container check, create a `.local` directory and two local files.
These files are ignored by Git and excluded from the Docker build context.
Replace the password placeholders with generated values, using the same application
password in both files.

`.local/mysql.env`:

```dotenv
MYSQL_ROOT_PASSWORD=<generated-root-password>
MYSQL_DATABASE=challenge
MYSQL_USER=crewmeister
MYSQL_PASSWORD=<generated-application-password>
```

`.local/app.env`:

```dotenv
SPRING_DATASOURCE_URL=jdbc:mysql://crewmeister-db:3306/challenge
SPRING_DATASOURCE_WRITER_URL=jdbc:mysql://crewmeister-db:3306/challenge
SPRING_DATASOURCE_USERNAME=crewmeister
SPRING_DATASOURCE_PASSWORD=<generated-application-password>
```

The following single-line Docker commands work in PowerShell and Bash:

```text
docker network create crewmeister-container
docker run --detach --name crewmeister-db --network crewmeister-container --env-file .local/mysql.env mysql:8.4@sha256:a0225d1ea6631c8bc2385dc4c2faba17bbf1834ecf369e1659a9a382bd8d5dd7
docker logs crewmeister-db
```

Wait for MySQL's final `ready for connections` message on port 3306, then start
the application. MySQL's hostname inside the network is `crewmeister-db`;
`localhost` inside the application container refers to the application itself.

```text
docker run --detach --name crewmeister-app --network crewmeister-container --env-file .local/app.env --publish 127.0.0.1::8080 crewmeister-app:local
docker logs crewmeister-app
docker port crewmeister-app 8080/tcp
```

Docker assigns an available localhost port. Use the reported port to access
`http://127.0.0.1:<port>/user?id=1` and the Actuator endpoints.
POST `/user` with content type `application/json` and body `{"name":"Reviewer"}`
to create a user. Both API endpoints return greeting strings; POST does not
return the generated user ID.

Check the runtime identity with `docker exec crewmeister-app id`.
Database credentials are supplied at runtime and are not built into the image.
Environment files and container environment variables contain credentials and
should be treated as local secrets.

Remove the disposable resources when finished:

```text
docker rm --force crewmeister-app
docker rm --force --volumes crewmeister-db
docker network rm crewmeister-container
```

Removing the database container with `--volumes` deletes its anonymous data volume.
Delete the two local environment files after use. The Kubernetes setup below
uses Terraform and Helm and generates its own database credentials.

### Local Kubernetes cluster

`terraform/cluster` creates a single-node Kind cluster named `crewmeister`.
The API server binds to `127.0.0.1` on an available port. No application ports
are reserved on the host. The dedicated kubeconfig is written to
`.local/crewmeister.kubeconfig`; project commands always specify its context,
`kind-crewmeister`.

The setup scripts create the cluster, prepare the application image, and install
MySQL and the application through `terraform/platform`. Separating the two
Terraform stages gives the Helm provider a working Kubernetes connection before
it initializes. Monitoring will be added in a later stage.

Install the following tools and make them available on `PATH`:

| Tool | Selected version | Notes |
| --- | --- | --- |
| Docker Engine / Docker Desktop | Tested with Engine 28.0.4 | Must be running with Linux containers |
| Terraform | 1.15.8 | Required by the configuration |
| Kind CLI | 0.33.0 | Matches the Kind library in provider 0.13.0 |
| kubectl | 1.36.4 | The scripts accept 1.35.x through 1.37.x |
| Helm | 4.3.1 | Used for application chart validation |
| Git | 2.x | Required for checkout and image versioning |

Tools can also be installed locally under the ignored `.local/bin` directory.
Both scripts prefer that directory when it exists, so a project-specific
kubectl can be used without replacing Docker Desktop's bundled client.

The Kind provider is pinned to `0.13.0`, and Kubernetes is pinned to the
`kindest/node:v1.36.4` image digest from the
[Kind 0.33.0 release](https://github.com/kubernetes-sigs/kind/releases/tag/v0.33.0).
The committed Terraform lockfile includes provider checksums for Windows amd64,
Linux amd64/arm64, and macOS amd64/arm64. kubectl must follow the
[Kubernetes version compatibility policy](https://kubernetes.io/releases/version-skew-policy/#kubectl).

Prefer Docker hosts using cgroup v2. On older Docker/WSL installations using
cgroup v1, setup detects that mode and sets `cgroup_v1_compatibility=true`,
which adds the documented `failCgroupV1: false` kubelet setting. It does not
change Docker or host settings. This is a temporary local compatibility path;
see [Kubernetes cgroup migration guidance](https://kubernetes.io/blog/2026/10/06/kubernetes-cgroups-v2-shift/).
When running Terraform apply or plan directly on such a host, pass
`-var=cgroup_v1_compatibility=true` to match the setup script.

Installation instructions:
[Terraform](https://developer.hashicorp.com/terraform/install),
[Kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation),
[kubectl on Windows](https://kubernetes.io/docs/tasks/tools/install-kubectl-windows/),
[kubectl on Linux](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/),
[kubectl on macOS](https://kubernetes.io/docs/tasks/tools/install-kubectl-macos/),
and [Helm](https://helm.sh/docs/intro/install/).

From a checkout, run the script for your shell:

```powershell
.\scripts\setup.ps1
```

```bash
bash scripts/setup.sh
```

Both scripts resolve paths from their own location, check prerequisites,
initialize and validate Terraform, apply the cluster configuration, and wait
for the node to become Ready. They then prepare the image, validate the chart,
and apply the platform stage. The scripts use `-auto-approve` for unattended
local provisioning of both stages. They refuse to reuse a same-named cluster absent from this
checkout's Terraform state. PowerShell checks external command exit codes and
restores the caller's environment and working directory on completion or failure.

On Windows, if a downloaded script is blocked, inspect it and run
`Unblock-File .\scripts\setup.ps1`. If your execution policy also blocks scripts,
use `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` for the
current PowerShell session, subject to your organization's policy.

Inspect the cluster explicitly:

```text
kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister get nodes
```

Destroy the platform before removing the cluster, using the ordered teardown
below. Removing Kind also removes its Kubernetes data. Keep Terraform state, plan output, and
kubeconfigs private: the provider stores cluster credentials in state. State,
provider downloads, and the project kubeconfig are excluded from Git; the
provider lockfile is committed.

### Helm deployments on Kubernetes

`terraform/platform` installs the `crewmeister-mysql` Helm release in the
`crewmeister` namespace. It uses the public
[groundhog2k MySQL chart](https://github.com/groundhog2k/helm-charts/tree/master/charts/mysql),
pinned to chart version `3.1.5`, with the same digest-pinned official MySQL 8.4
image used for the container check. No chart repository login is required.

Terraform generates separate root and application passwords and creates two
Kubernetes Secrets. Helm receives only Secret names and key mappings. The
application account is restricted to the `challenge` database; its Secret does
not contain the root password. Passwords are not Terraform outputs.

MySQL uses a StatefulSet, an internal ClusterIP service, resource limits, and a
2 GiB PVC backed by Kind's `standard` storage class. Startup and readiness checks
authenticate over TCP against the application database. The PVC survives pod
replacement; it is not intended to survive deletion of the Kind cluster.

The platform also deploys the application chart described below. After creating
the cluster with the setup script, build and load its local image before applying
the platform:

```text
docker build --tag crewmeister-app:local .
kind load docker-image crewmeister-app:local --name crewmeister
terraform -chdir=terraform/platform init
terraform -chdir=terraform/platform apply
kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister --namespace crewmeister get pods,pvc,service
```

The platform providers explicitly use the project kubeconfig and context.
The provider versions and checksums are committed in the platform lockfile.
Generated passwords and Secret data remain in local Terraform state, so keep
state files and plan logs private and preserve state while the database is in use.

The manual commands above use the static `crewmeister-app:local` Terraform defaults.
The setup scripts instead write their selected image settings to the ignored
`.local/image.auto.tfvars.json` file. After scripted setup, use
`-var-file=../../.local/image.auto.tfvars.json` for subsequent platform plan/apply
commands to preserve that image selection.

Use the teardown script for your shell to destroy the platform **before** the cluster:

```powershell
.\scripts\down.ps1
```

```bash
bash scripts/down.sh
```

Platform destruction deletes the project namespace and its database PVC. This
removes stored data. A new deployment after full teardown generates new passwords.

### Application Helm chart

`helm/crewmeister-app` defines the application Deployment, internal Service, and
ConfigMap. Terraform installs it as a separate `crewmeister-app` release after
MySQL is Ready. The chart references the existing application Secret and never
receives the database root password.

The ConfigMap sets both application and Flyway JDBC URLs and bounded Flyway
connection retries. The container runs as UID `10001`, with a read-only root
filesystem, a writable `/tmp`, dropped capabilities, no privilege escalation,
and no mounted service-account token. CPU and memory requests and limits are
defined in chart values.

The startup probe allows time for Spring Boot and Flyway to initialize. Readiness
checks MySQL connectivity; liveness checks the application independently so a
temporary database outage does not cause unnecessary application restarts.
ConfigMap changes and chart changes trigger a deployment rollout.

The Terraform defaults use `crewmeister-app:local` with pull policy `Never`.
For a published image, supply `image_repository`, `image_tag`, and
`image_pull_policy=IfNotPresent` as Terraform inputs. Use a commit SHA tag rather
than a moving `latest` tag. `values-local.yaml` supports images loaded into Kind;
the same chart can render registry image settings without changing templates.

Validate the chart:

```text
helm lint helm/crewmeister-app --strict
helm lint helm/crewmeister-app --values helm/crewmeister-app/values-local.yaml --strict
helm template crewmeister-app helm/crewmeister-app --namespace crewmeister --values helm/crewmeister-app/values-local.yaml
```

Access the API with a localhost port forward:

```text
kubectl --kubeconfig .local/crewmeister.kubeconfig --context kind-crewmeister --namespace crewmeister port-forward --address 127.0.0.1 service/crewmeister-app :8080
```

Use the assigned port printed by kubectl for `/user?id=1`, POST `/user`, and the
Actuator endpoints. Both application and MySQL data remain available after pod
replacement. Database storage persists across pod replacements, not full teardown.

### Image selection during setup

By default, setup tries the public GHCR image tagged with the checkout's full
commit SHA. If it cannot pull that image, it builds the checkout locally and
loads it into Kind. Uncommitted application build inputs also select the local
build path in automatic mode. Local tags are derived from the build input
contents, so repeated setup uses the same tag when those inputs are unchanged.

Both registry and local images are loaded into the project Kind cluster.
Registry images use `IfNotPresent`; local images use `Never` to avoid a registry
pull for an image that exists only on the development machine. The image helpers
are `scripts/load-image.ps1` and `scripts/load-image.sh`.

Optional environment variables are shared by both script families:

| Variable | Default | Purpose |
| --- | --- | --- |
| `CREWMEISTER_IMAGE_MODE` | `auto` | `auto` tries the registry then builds locally; `local` always builds; `registry` requires a successful pull |
| `CREWMEISTER_IMAGE_REPOSITORY` | `ghcr.io/ouemnaa/crewmeister-devops-challenge` | Repository to pull from in automatic or registry mode |
| `CREWMEISTER_IMAGE_TAG` | Current Git commit SHA | Registry tag to pull; local fallback always tags the current build inputs |

Force local mode in PowerShell:

```powershell
$env:CREWMEISTER_IMAGE_MODE = 'local'
.\scripts\setup.ps1
Remove-Item Env:CREWMEISTER_IMAGE_MODE
```

Or in Bash:

```bash
CREWMEISTER_IMAGE_MODE=local bash scripts/setup.sh
```

Registry mode stops if the selected image is unavailable. Automatic mode logs
pull failures under `.local/image-pull.*` and continues with a local build.
Publishing the GHCR image will be added with the CI pipeline; until then,
automatic mode supports a fresh checkout through its local fallback.

### Verifying a deployment

After setup, run one command for your shell:

```powershell
.\scripts\verify.ps1
```

```bash
bash scripts/verify.sh
```

Verification checks the project Kind cluster, Ready nodes, healthy MySQL and
application workloads, a Bound PVC, internal services, and an authenticated
database query. It then uses a temporary localhost port forward to test the
seeded user, POST a uniquely named user, confirm that record in MySQL, and
retrieve it by its actual database ID. Health probes and JVM/HTTP metrics are
also checked.

The scripts delete their test user and stop the port forward on completion or
failure. They use the dedicated project kubeconfig and context and work from
any current directory. Bash verification also requires `curl`. A failed check
returns a nonzero exit code; logs for port forwarding stay under ignored `.local/`.

### Teardown behavior

Teardown is unattended: it applies saved Terraform destroy plans without an
interactive confirmation. Run it only when you intend to delete the project's
database and infrastructure.

Before planning deletion, the scripts check the expected Terraform resource
addresses and names, dedicated kubeconfig path, Kind node container, live API
port, and Terraform's recorded certificate authority. They refuse a mismatched
target, unexpected resources, or infrastructure with missing ownership state.
They use the explicit project context throughout.

Both stages are planned before deletion begins. The platform is destroyed first;
if that fails, the cluster remains available for troubleshooting. After successful
cluster destruction, the scripts confirm that the project Kind node containers
are gone. A repeated teardown succeeds without action when both stages and the
cluster are already absent.

The scripts leave cached images, the shared Kind Docker network, and unrelated
containers, volumes, and Kubernetes contexts alone. Provider caches and local
Terraform files are retained for the next setup. State backups may still contain
old credentials and remain private. Temporary destroy-plan files are removed on
exit; they are also covered by the repository's ignore rules.

All lifecycle scripts work from any current directory. PowerShell restores the
caller's path, kubeconfig environment variable, and Kind provider selection even
when a check fails. Bash scripts run in their own shell process.
