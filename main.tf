provider "aws" {
  region = "ap-south-1"
}

##############################
# ECR Repository
##############################
resource "aws_ecr_repository" "final_test_repo" {
  name = "final-test-repo"
}

##############################
# ECS Cluster
##############################
resource "aws_ecs_cluster" "final_test_cluster" {
  name = "final-test-cluster"
}

##############################
# Get Default VPC and Subnets
##############################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

##############################
# Get Default Security Group
##############################
data "aws_security_group" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "group-name"
    values = ["default"]
  }
}

##############################
# Cloud Map Namespace (Optional)
##############################
resource "aws_service_discovery_private_dns_namespace" "final_test_namespace" {
  name        = "final-test-namespace"
  description = "Service discovery namespace for final test"
  vpc         = data.aws_vpc.default.id
}

##############################
# ECS Task Definition
##############################
resource "aws_ecs_task_definition" "final_test_task" {
  family                   = "final-test-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  container_definitions = jsonencode([
    {
      name      = "my-final-test-container"
      image     = "${aws_ecr_repository.final_test_repo.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}

##############################
# ECS Service
##############################
resource "aws_ecs_service" "final_test_service" {
  name            = "final-test-service"
  cluster         = aws_ecs_cluster.final_test_cluster.id
  task_definition = aws_ecs_task_definition.final_test_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = slice(data.aws_subnets.default.ids, 0, 2)
    security_groups = [data.aws_security_group.default.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = aws_service_discovery_private_dns_namespace.final_test_namespace.arn
  }

  depends_on = [aws_ecs_cluster.final_test_cluster]
}