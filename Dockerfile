# syntax=docker/dockerfile:1

# Etapa 1: compilar con Maven (las pruebas ya corren en el pipeline de CI con mvn verify)
FROM maven:3.9.16-eclipse-temurin-21-noble AS build
WORKDIR /src
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -ntp -q dependency:go-offline
COPY src ./src
# CampusFix no es Spring Boot: el .jar no trae sus dependencias, así que se copian aparte a lib/
RUN --mount=type=cache,target=/root/.m2 mvn -B -ntp -q package -DskipTests \
 && mvn -B -ntp -q dependency:copy-dependencies -DincludeScope=runtime -DoutputDirectory=/out/lib \
 && cp target/campusfix-*.jar /out/app.jar

# Etapa 2: imagen final solo con el JRE, el .jar y sus librerías
FROM eclipse-temurin:21.0.12.1_1-jre-noble
RUN groupadd --system app && useradd --system --gid app --no-create-home app
WORKDIR /app
COPY --from=build --chown=app:app /out/lib ./lib
COPY --from=build --chown=app:app /out/app.jar app.jar
USER app
ENV PORT=8080
EXPOSE 8080

# CampusFix expone GET /salud; no depende de servicios externos
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=5 \
  CMD curl -fsS http://localhost:8080/salud || exit 1

# La JVM usa como máximo el 75 % de la memoria del contenedor; headless porque ZXing usa java.awt
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-Djava.awt.headless=true", \
            "-cp", "/app/app.jar:/app/lib/*", "com.campusfix.bootstrap.CampusFixApp"]
