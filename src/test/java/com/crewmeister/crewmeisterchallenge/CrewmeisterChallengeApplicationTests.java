package com.crewmeister.crewmeisterchallenge;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.actuate.observability.AutoConfigureObservability;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@AutoConfigureObservability
@Timeout(30)
class CrewmeisterChallengeApplicationTests {

  @Autowired
  private TestRestTemplate rest;

  @Autowired
  private JdbcTemplate jdbc;

  @Test
  void retrievesUserSeededByFlyway() {
    ResponseEntity<String> response = rest.getForEntity("/user?id=1", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isEqualTo("Greetings from Crewmeister, Alice!");
  }

  @Test
  void createsUserAndRetrievesPersistedRecord() {
    String name = "integration-" + UUID.randomUUID();
    HttpHeaders headers = new HttpHeaders();
    headers.setContentType(MediaType.APPLICATION_JSON);
    HttpEntity<String> request = new HttpEntity<>("{\"name\":\"" + name + "\"}", headers);

    try {
      ResponseEntity<String> created = rest.postForEntity("/user", request, String.class);

      assertThat(created.getStatusCode()).isEqualTo(HttpStatus.OK);
      assertThat(created.getBody()).isEqualTo("Greetings from Crewmeister, " + name + "!");

      Long id = jdbc.queryForObject("SELECT id FROM user WHERE name = ?", Long.class, name);
      assertThat(id).isNotNull();

      ResponseEntity<String> retrieved = rest.getForEntity("/user?id=" + id, String.class);
      assertThat(retrieved.getStatusCode()).isEqualTo(HttpStatus.OK);
      assertThat(retrieved.getBody()).isEqualTo(created.getBody());
    } finally {
      jdbc.update("DELETE FROM user WHERE name = ?", name);
    }
  }

  @Test
  void reportsHealthyApplicationAndDatabase() {
    assertHealthUp("/actuator/health");
  }

  @Test
  void exposesLivenessProbe() {
    assertHealthUp("/actuator/health/liveness");
  }

  @Test
  void exposesReadinessProbe() {
    assertHealthUp("/actuator/health/readiness");
  }

  @Test
  void exposesJvmAndHttpMetricsForPrometheus() {
    rest.getForEntity("/user?id=1", String.class);

    ResponseEntity<String> response = rest.getForEntity("/actuator/prometheus", String.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody())
        .contains("jvm_memory_used_bytes")
        .contains("http_server_requests_seconds_count");
  }

  private void assertHealthUp(String path) {
    ResponseEntity<JsonNode> response = rest.getForEntity(path, JsonNode.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().path("status").asText()).isEqualTo("UP");
  }

}
