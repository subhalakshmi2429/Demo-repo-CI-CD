provider "aws" {
  region = "ap-south-1"
}

##############################
# Use Existing or Create ECR Repository
##############################
data "aws_ecr_repository" "existing" {
  name = "final-test-repo"
}

resource "aws_ecr_repository" "final_test_repo" {
  name     = "final-test-repo"
  count    = length(data.aws_ecr_repository.existing.id) > 0 ? 0 : 1
  lifecycle {
    create_before_destroy = true
  }
}

##############################
# Use Existing ECS Cluster or Create
##############################
data "aws_ecs_cluster" "existing" {
  cluster_name = "final-test-cluster"
}

resource "aws_ecs_cluster" "final_test_cluster" {
  name  = "final-test-cluster"
  count = length(data.aws_ecs_cluster.existing.id) > 0 ? 0 : 1
}

##############################
# Default VPC, Subnets, and SG
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
# IAM Role for ECS Execution
##############################
data "aws_iam_role" "existing_ecs_exec_role" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
  count = length(data.aws_iam_role.existing_ecs_exec_role.arn) > 0 ? 0 : 1

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  count      = length(data.aws_iam_role.existing_ecs_exec_role.arn) > 0 ? 0 : 1
  role       = aws_iam_role.ecs_task_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

##############################
# Cloud Map Namespace (Optional)
##############################
resource "aws_service_discovery_private_dns_namespace" "final_test_namespace" {
  name        = "final-test-namespace-${random_string.suffix.result}"
  description = "Service discovery namespace for final test"
  vpc         = data.aws_vpc.default.id
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

##############################
# ECS Task Definition
##############################
resource "aws_ecs_task_definition" "final_test_task" {
  family                   = "final-test-task-${random_string.suffix.result}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = coalesce(
    try(data.aws_iam_role.existing_ecs_exec_role.arn, null),
    try(aws_iam_role.ecs_task_execution_role[0].arn, null)
  )

  container_definitions = jsonencode([
    {
      name      = "my-final-test-container"
      image     = "574720314262.dkr.ecr.ap-south-1.amazonaws.com/final-test-repo:latest"
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
  name            = "final-test-service-${random_string.suffix.result}"
  cluster         = coalesce(
    try(data.aws_ecs_cluster.existing.id, null),
    try(aws_ecs_cluster.final_test_cluster[0].id, null)
  )
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

  depends_on = [
    aws_ecs_task_definition.final_test_task
  ]
}
