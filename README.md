# Pact Cloud Demonstration
Demonstrate verifying contracts between service APIs using serverless cloud infrastructure via automated tooling.

## Project Purpose
The Pact framework uses tests between consumer and provider services to verify consumer expectations. The process requires executing downloaded Pact test files created by consumers to verify responses meet those expectations. This project attempts to guide users intending to implement Pact testing through multiple example service projects.

Communication through a centralized Pact broker instance decouples consumer and provider test execution and offers on-demand scaling across multiple projects. Terraform infrastructure-as-code configurations guide users through deploying necessary cloud infrastructure for the broker using serverless components. In addition, GitHub workflows demonstrate automated tooling for performing infrastructure updates, building service projects, verifying Pacts, and determining if service deployment is safe based on Pact results.

## AWS Account Setup
Some cloud configuration steps are required to be performed manually outside of Terraform execution.

1. Create an S3 bucket using the AWS CLI:
   ```
   aws s3api create-bucket --bucket terraform-state-pactdemo-purdueglobal --region us-east-1
   aws s3api put-bucket-versioning --bucket terraform-state-pactdemo-purdueglobal --versioning-configuration Status=Enabled
   ```
3. Create a DynamoDB table to store state-locking information:
   ```
   aws dynamodb create-table --table-name terraform-locks-pactdemo-purdueglobal \                                               ✔  07:20:27 PM  
   --attribute-definitions AttributeName=LockID,AttributeType=S \
   --key-schema AttributeName=LockID,KeyType=HASH \
   --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1
   ```
3. Create the following list of SSM Systems Manager secrets and input appropriate values:
   ```
   /pact/pactBrokerRDSUsername (String)
   /pact/pactBrokerRDSPassword (Secure String)
   /pact/pactBrokerUsername (String)
   /pact/pactBrokerPassword (Secure String)
   /pact/pactBrokerReadOnlyUsername (String)
   /pact/pactBrokerReadOnlyPassword (Secure String)
   ```

## Build / Terraform Workflows
This project consists of two Micronaut web applications, employee-status and employee-directory. The employee status application is a consumer of the employee directory and contains a Pact test the provider must execute to validate the contract between the two.

All AWS cloud infrastructure is deployable through Terraform consisting of:
- VPC with public and private subnets and flow logs enabled
- ALB accepting TLS connections forwarding requests to port 9292
- ECS cluster with Pact broker task definition using Fargate
- RDS PostgreSQL v16 database only available through private subnets
- DNS entries for the load balancer and database

A single Micronaut GitHub workflow builds each web application using conditionals. Two Terraform workflows deploy everything and destroy on-demand. The deployment workflow always runs in pull requests up to the plan action. Applying changes requires manual dispatch and confirmation. The destruction workflow must be performed via dispatch and requires entering the 'confirm' keyword to execute.
