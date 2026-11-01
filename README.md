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
