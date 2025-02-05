package com.ingendevelopment;

import jakarta.inject.Singleton;
import java.util.Optional;

@Singleton
public class EmployeeAccessService {

    private final EmployeeDirectoryClient employeeDirectoryClient;

    public EmployeeAccessService(EmployeeDirectoryClient employeeDirectoryClient) {
        this.employeeDirectoryClient = employeeDirectoryClient;
    }

    public Optional<EmployeeInfo> getEmployeeInfo(String employeeId) {
        return employeeDirectoryClient.getEmployee(employeeId);
    }
}
