FROM eclipse-temurin:17-jdk-noble@sha256:53686f59c44e08ac3310d39ef9c3e3d3bb03370366d9c45802229c86fa2d8369 AS build

WORKDIR /workspace
COPY pom.xml mvnw ./
COPY .mvn/ .mvn/
COPY src/ src/

# Integration tests require MySQL and run separately with `mvnw clean verify`.
RUN --mount=type=cache,target=/root/.m2 sh ./mvnw --batch-mode -DskipTests package

FROM eclipse-temurin:17-jre-noble@sha256:e13d2fc95a199cda333a2d8ce67a48727029dda50782bb8ecaced710932ac920 AS runtime

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=build /workspace/target/crewmeisterchallenge-*.jar /app/app.jar

USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
