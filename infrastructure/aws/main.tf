provider "aws" {
  region = "us-east-1"
}

# ----------
# VPC
# ----------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.19.0"

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
  name        = "pact_broker_alb_sg"
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
  name               = "pact_broker_lb"
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
  name     = "pact_broker_lb_target_group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# ----------
# ECS
# ----------
resource "aws_ecs_cluster" "app_cluster" {
  name = "app-cluster"
}

resource "aws_ecs_task_definition" "app_task" {
  family                   = "app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "app-container"
      image     = "your-docker-image:latest"
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

resource "aws_ecs_service" "app_service" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.app_cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 2

  launch_type = "FARGATE"

  network_configuration {
    subnets         = module.vpc.private_subnets
    security_groups = [aws_security_group.alb_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "app-container"
    container_port   = 80
  }
}

# ----------
# RDS
# ----------
module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "5.0.2"

  identifier = "app-db"
  engine     = "postgres"
  engine_version = "15.2"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_encrypted = true

  name     = "appdb"
  username = "admin"
  password = "password"
  vpc_security_group_ids = [aws_security_group.alb_sg.id]
  subnet_ids = module.vpc.private_subnets

  publicly_accessible = false
}

# ----------
# DNS
# ----------
resource "aws_route53_zone" "app_zone" {
  name = "ingendevelopment.com"
}

resource "aws_route53_record" "app_record" {
  zone_id = aws_route53_zone.app_zone.zone_id
  name    = "pactbroker.ingendevelopment.com"
  type    = "A"

  alias {
    name                   = aws_lb.app_lb.dns_name
    zone_id                = aws_lb.app_lb.zone_id
    evaluate_target_health = true
  }
}
