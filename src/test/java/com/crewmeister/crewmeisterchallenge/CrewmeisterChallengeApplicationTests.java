package com.crewmeister.crewmeisterchallenge;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.JsonNode;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
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

  private void assertHealthUp(String path) {
    ResponseEntity<JsonNode> response = rest.getForEntity(path, JsonNode.class);

    assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
    assertThat(response.getBody()).isNotNull();
    assertThat(response.getBody().path("status").asText()).isEqualTo("UP");
  }

}
