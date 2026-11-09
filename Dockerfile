FROM eclipse-temurin:17-jdk-noble@sha256:ec2c8050c856a00986776ddd94d4facc9e872430c27799108ca318a26f9f1887 AS build

WORKDIR /workspace
COPY pom.xml mvnw ./
COPY .mvn/ .mvn/
COPY src/ src/

# Integration tests require MySQL and run separately with `mvnw clean verify`.
RUN --mount=type=cache,target=/root/.m2 sh ./mvnw --batch-mode -DskipTests package

FROM eclipse-temurin:17-jre-noble@sha256:8ee89ca3f9eb6a931a2b2e8b2901a4af3554383f8077558e3631d49bb58cff1d AS runtime

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=build /workspace/target/crewmeisterchallenge-*.jar /app/app.jar

USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
