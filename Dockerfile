FROM eclipse-temurin:24-jdk-noble@sha256:dacac8e9a0df0d2bd24e702b4431132875c249930b70555ebd7ca285b5bee684 AS build

WORKDIR /workspace
COPY pom.xml mvnw ./
COPY .mvn/ .mvn/
COPY src/ src/

# Integration tests require MySQL and run separately with `mvnw clean verify`.
RUN --mount=type=cache,target=/root/.m2 sh ./mvnw --batch-mode -DskipTests package

FROM eclipse-temurin:24-jre-noble@sha256:b416d02335e702b0403ff280de9475a3348e29382285969c9d4e17862ce632e7 AS runtime

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=build /workspace/target/crewmeisterchallenge-*.jar /app/app.jar

USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
