output "alb_dns_name" {
  value = aws_lb.pact_broker_lb.dns_name
}

output "rds_endpoint" {
  value = module.rds.db_instance_address
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.pactbroker_app_cluster.name
}
