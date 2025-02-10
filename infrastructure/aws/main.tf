provider "aws" {
  region = var.region
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

data "aws_ssm_parameter" "rds_username" {
  name = "/pact/pactBrokerRDSUsername"
}

data "aws_ssm_parameter" "rds_password" {
  name = "/pact/pactBrokerRDSPassword"
}

data "aws_ssm_parameter" "pact_username" {
  name = "/pact/pactBrokerUsername"
}

data "aws_ssm_parameter" "pact_password" {
  name = "/pact/pactBrokerPassword"
}

data "aws_ssm_parameter" "pact_readonly_username" {
  name = "/pact/pactBrokerReadOnlyUsername"
}

data "aws_ssm_parameter" "pact_readonly_password" {
  name = "/pact/pactBrokerReadOnlyPassword"
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
resource "aws_cloudwatch_log_group" "pactbroker" {
  name              = "/ecs/pactbroker"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "pactbroker_app_cluster" {
  name = "pactbroker-app-cluster"
}

resource "aws_ecs_task_definition" "pactbroker_app_task" {
  family                   = "pactbroker_app_task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.packbroker_ecs_task_execution_role.arn

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
      logConfiguration = {
        logDriver = "awslogs"
        options   = {
          awslogs-group         = "/ecs/pactbroker"
          awslogs-region        = "us-east-1"
          awslogs-stream-prefix = "ecs"
        }
      }
      environment = [
        {
          name = "PACT_BROKER_DATABASE_USERNAME",
          value = data.aws_ssm_parameter.rds_username.value
        },
        {
          name = "PACT_BROKER_DATABASE_PASSWORD",
          value = data.aws_ssm_parameter.rds_password.value
        },
        {
          "name": "PACT_BROKER_DATABASE_HOST",
          "value": module.rds.db_instance_address
        },
        {
          "name": "PACT_BROKER_DATABASE_NAME",
          "value": module.rds.db_instance_name
        },
        {
          "name": "PACT_BROKER_PUMA_PERSISTENT_TIMEOUT",
          "value": "120"
        },
        {
          "name": "PACT_BROKER_BASIC_AUTH_USERNAME",
          "value": data.aws_ssm_parameter.pact_username.value
        },
        {
          "name": "PACT_BROKER_BASIC_AUTH_PASSWORD",
          "value": data.aws_ssm_parameter.pact_password.value
        },
        {
          "name": "PACT_BROKER_BASIC_AUTH_READ_ONLY_USERNAME",
          "value": data.aws_ssm_parameter.pact_readonly_username.value
        },
        {
          "name": "PACT_BROKER_BASIC_AUTH_READ_ONLY_PASSWORD",
          "value": data.aws_ssm_parameter.pact_readonly_password.value
        },
        {
          "name": "PACT_BROKER_ALLOW_PUBLIC_READ",
          "value": "true"
        },
        {
          "name": "PACT_BROKER_LOG_LEVEL",
          "value": "INFO"
        },
        {
          "name": "PACT_BROKER_PUBLIC_HEARTBEAT",
          "value": "true"
        },
        {
          "name": "PACT_BROKER_WEBHOOK_HOST_WHITELIST",
          "value": ""
        }
      ]
    }
  ])
}

resource "aws_iam_role" "packbroker_ecs_task_execution_role" {
  name = "packbroker_ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_logs" {
  role       = aws_iam_role.packbroker_ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
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
resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  description = "Security group for RDS"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    security_groups = [aws_security_group.pact_broker_alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

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
  username               = data.aws_ssm_parameter.rds_username.value
  password               = data.aws_ssm_parameter.rds_password.value
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  create_db_subnet_group = true
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
