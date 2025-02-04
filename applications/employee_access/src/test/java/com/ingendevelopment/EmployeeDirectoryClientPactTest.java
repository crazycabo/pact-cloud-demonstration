package com.ingendevelopment;

import au.com.dius.pact.consumer.MockServer;
import au.com.dius.pact.consumer.dsl.PactDslWithProvider;
import au.com.dius.pact.consumer.junit5.PactConsumerTestExt;
import au.com.dius.pact.consumer.junit5.PactTestFor;
import au.com.dius.pact.core.model.RequestResponsePact;
import au.com.dius.pact.core.model.annotations.Pact;
import com.google.gson.Gson;
import io.micronaut.test.extensions.junit5.annotation.MicronautTest;
import kong.unirest.core.HttpResponse;
import kong.unirest.core.Unirest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;

import static org.hamcrest.MatcherAssert.assertThat;
import static org.hamcrest.Matchers.instanceOf;
import static org.junit.jupiter.api.Assertions.*;

@MicronautTest
@ExtendWith(PactConsumerTestExt.class)
public class EmployeeDirectoryClientPactTest {

    Gson gson = new Gson();

    @Pact(provider = "EmployeeDirectory", consumer = "EmployeeAccess")
    public RequestResponsePact employeePact(PactDslWithProvider builder) {
        return builder
                .given("Employee exists with ID 12345")
                .uponReceiving("A request for an employee's details")
                .path("/")
                .method("GET")
                .query("employeeId=12345")
                .willRespondWith()
                .status(200)
                .body("""
                    {
                        "fullName": "John Doe",
                        "department": "Engineering",
                        "phoneNumber": "555-1234"
                    }
                """)
                .toPact();
    }

    @Test
    @PactTestFor(pactMethod = "employeePact")
    void testGetEmployeeInfo(MockServer mockServer) {

        HttpResponse<String> response = Unirest.get(mockServer.getUrl() + "/employee-directory/12345")
                .asString();

        String responseBody = response.getBody();

        assertAll(
                () -> assertEquals(200, response.getStatus()),
                () -> assertThat(gson.fromJson(responseBody, EmployeeInfo.class), instanceOf(EmployeeInfo.class))
        );
    }
}
