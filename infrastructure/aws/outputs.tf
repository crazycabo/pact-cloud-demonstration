output "alb_dns_name" {
  value = aws_lb.pactbroker_app_lb.dns_name
}

output "rds_endpoint" {
  value = module.rds.this_rds_instance_address
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.pactbroker_app_cluster.name
}