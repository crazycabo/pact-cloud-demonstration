package com.ingendevelopment;

import io.micronaut.http.annotation.Get;
import io.micronaut.http.client.annotation.Client;

import java.util.Optional;

@Client("/employee-directory")
public interface EmployeeDirectoryClient {

    @Get("/{?employeeId}")
    Optional<EmployeeInfo> getEmployee(String employeeId);
}
