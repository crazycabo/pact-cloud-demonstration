# Pact Cloud Demonstration
Demonstrate verifying contracts between service APIs using serverless cloud infrastructure via automated tooling.

## Project Purpose
The Pact framework uses tests between consumer and provider services to verify consumer expectations. The process requires executing downloaded Pact test files created by consumers to verify responses meet those expectations. This project attempts to guide users intending to implement Pact testing through multiple example service projects.

Communication through a centralized Pact broker instance decouples consumer and provider test execution and offers on-demand scaling across multiple projects. Terraform infrastructure-as-code configurations guide users through deploying necessary cloud infrastructure for the broker using serverless components. In addition, GitHub workflows demonstrate automated tooling for performing infrastructure updates, building service projects, verifying Pacts, and determining if service deployment is safe based on Pact results.
