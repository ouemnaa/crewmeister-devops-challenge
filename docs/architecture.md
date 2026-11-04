# Technical architecture diagrams

These additional diagrams expand on the [Crewmeister DevOps challenge README](../README.md). The README keeps only the project overview, CI pipeline, and optional AWS EKS architecture diagrams to stay easy to scan.

## Local Terraform setup sequence

The PowerShell and Bash setup scripts manage the lifecycle of two separate local Terraform roots. The platform stage runs only after Kind is ready.

```mermaid
sequenceDiagram
    participant S as Setup script
    participant C as terraform/cluster
    participant K as Kind cluster
    participant P as terraform/platform
    participant H as Helm releases
    S->>C: init and apply
    C->>K: create node and API
    C-->>S: write .local/crewmeister.kubeconfig
    Note over S: choose image, GHCR pull or local build
    S->>P: init and apply with kubeconfig and image tag
    P->>H: namespace, Secrets, then four Helm releases
    H->>K: pods start and become ready
```



State is isolated: `terraform/cluster/terraform.tfstate` and `terraform/platform/terraform.tfstate`. Never point the Kind platform root or its state at AWS.

## Helm releases and resources

The Terraform platform root installs four releases with dependency-aware ordering. The custom application chart remains shared by Kind and AWS.

```mermaid
flowchart LR
    tf["Terraform helm_release"] --> r1["mysql release"]
    tf --> r2["application release"]
    tf --> r3["monitoring release"]
    tf --> r4["mysql exporter release"]
    r1 --> o1["StatefulSet, Service, PVC"]
    r2 --> o2["Deployment, Service, probes, ServiceMonitor"]
    r3 --> o3["Prometheus, Grafana, operator"]
    r4 --> o4["Exporter Deployment, ServiceMonitor"]
```



Pinned upstream charts: MySQL `3.1.5`, kube-prometheus-stack `92.17.0`, and prometheus-mysql-exporter `2.16.0`.

## Local Kubernetes runtime

Application traffic, database storage, monitoring scrapes, and localhost access are isolated within the `crewmeister` namespace.

```mermaid
flowchart LR
    subgraph ns ["namespace crewmeister"]
        app["Spring Boot app"] -->|"JDBC 3306"| mysql[("MySQL with 2 GiB PVC")]
        exporter["MySQL exporter"] --> mysql
        prom["Prometheus"] -->|"scrapes metrics"| app
        prom -->|"scrapes metrics"| exporter
        grafana["Grafana dashboard"] -->|"queries"| prom
    end

    you(["Reviewer on localhost"]) -. "port-forward" .-> app
    you -. "port-forward" .-> grafana
    you -. "port-forward" .-> prom
```



In the local Kind environment, all Kubernetes Services are ClusterIP. Application, Grafana and Prometheus access uses localhost port-forwarding. MySQL storage is persistent across pod replacement, but teardown removes the demo data.

## Local image selection and delivery

For a clean checkout matching a published image, Kind can pull the public GHCR image tagged with the exact commit SHA. Otherwise, the local setup can build and import a new image.

```mermaid
flowchart LR
    setup["Setup script"] --> check{"Image for this commit in GHCR, and no local changes?"}
    check -->|"yes"| ghcr["Public GHCR image"]
    ghcr --> pull["Kubernetes pulls it, IfNotPresent"]
    check -->|"no"| build["Local Docker build"]
    build --> load["kind load, pull policy Never"]
    pull --> deploy["Application Deployment"]
    load --> deploy
```



`CREWMEISTER_IMAGE_MODE=local` forces local build and load; `registry` requires the published image; `auto` selects between them. Local images use pull policy `Never`, whereas published images use `IfNotPresent`.

## AWS state and dependency flow

The AWS extension uses three Terraform roots, entirely separate from Kind. The bootstrap backend is protected locally, while the cluster and platform use separate locked S3 state keys.

```mermaid
flowchart LR
    boot["terraform/aws/bootstrap"] -->|"creates"| bucket[("Protected S3 bucket")]
    bucket --> cstate["cluster state"]
    bucket --> pstate["platform state"]
    cluster["terraform/aws/cluster"] --> infra["VPC, EKS, node, identity"]
    cluster --> cstate
    platform["terraform/aws/platform"] --> work["Storage, ALB controller, workloads"]
    platform --> pstate
    cstate -->|"read by"| platform
```



- Bootstrap: protected local state under `.local/aws/`, backed up separately.
- Cluster: `crewmeister/aws/cluster.tfstate` in the private S3 backend.
- Platform: `crewmeister/aws/platform.tfstate` in that backend, with a different key.

The platform reads the AWS cluster state to connect Helm/Kubernetes providers to the correct EKS cluster. Apply bootstrap → cluster → platform; remove public ingress and platform resources before destroying the cluster. Keep S3 state until cleanup has been verified. Refer to [the AWS deployment guide](aws-deployment.md) for safeguards and controlled teardown procedures.
