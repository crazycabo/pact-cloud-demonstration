provider "aws" {
  region = "${var.region}"
}

terraform {
  backend "s3" {
    bucket         = "terraform-state-pactdemo-purdueglobal"
    key            = "terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks-pactdemo-purdueglobal"
  }
}


# ----------
# VPC
# ----------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0"

  name = "pact-broker-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
}

# ----------
# ALB
# ----------
resource "aws_security_group" "pact_broker_alb_sg" {
  name        = "pact-broker-alb-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "pact_broker_lb" {
  name               = "pact-broker-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.pact_broker_alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_listener" "pact_broker_lb_http_listener" {
  load_balancer_arn = aws_lb.pact_broker_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.pact_broker_lb_target_group.arn
  }
}

resource "aws_lb_target_group" "pact_broker_lb_target_group" {
  name        = "pact-broker-lb-target-group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id

  health_check {
    matcher   = "200,301,302"
    path      = "/diagnostic/status/heartbeat"
  }
}

# ----------
# ECS
# ----------
resource "aws_ecs_cluster" "pactbroker_app_cluster" {
  name = "pactbroker-app-cluster"
}

resource "aws_ecs_task_definition" "pactbroker_app_task" {
  family                   = "pactbroker_app_task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "pactbroker"
      image     = "pactfoundation/pact-broker:2.124.0-pactbroker2.112.0"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
          protocol      = "tcp"
        }
      ]
    }
  ])
}

resource "aws_ecs_service" "pactbroker_app_service" {
  name            = "pactbroker-app-service"
  cluster         = aws_ecs_cluster.pactbroker_app_cluster.id
  task_definition = aws_ecs_task_definition.pactbroker_app_task.arn
  desired_count   = 2

  launch_type = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.pact_broker_alb_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.pact_broker_lb_target_group.arn
    container_name   = "pactbroker"
    container_port   = 80
  }
}

# ----------
# RDS
# ----------
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "6.10.0"

  identifier           = "packbroker-db"
  engine               = "postgres"
  engine_version       = "16.6"
  major_engine_version = "16"
  family               = "postgres16"
  instance_class       = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true

  db_name                = "packbrokerdb"
  username               = "pactbrokeradmin"
  password               = "Kate0522"
  vpc_security_group_ids = [aws_security_group.pact_broker_alb_sg.id]
  subnet_ids             = module.vpc.private_subnets

  publicly_accessible = false
}

# ----------
# DNS
# ----------
resource "aws_route53_zone" "ingendev_app_zone" {
  name = "ingendevelopment.com"
}

resource "aws_route53_record" "packbroker_app_record" {
  zone_id = aws_route53_zone.ingendev_app_zone.zone_id
  name    = "pactbroker.ingendevelopment.com"
  type    = "A"

  alias {
    name                   = aws_lb.pact_broker_lb.dns_name
    zone_id                = aws_lb.pact_broker_lb.zone_id
    evaluate_target_health = true
  }
}
