provider "aws" {
  region = "ap-south-1"
}

# Use default VPC, Subnets, and Security Groups
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

# Check if IAM role exists, if not create it
data "aws_iam_role" "ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role" "ecs_task_execution" {
  count = length(data.aws_iam_role.ecs_task_execution.id) == 0 ? 1 : 0

  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  count       = length(data.aws_iam_role.ecs_task_execution.id) == 0 ? 1 : 0
  role        = aws_iam_role.ecs_task_execution[0].name
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  depends_on  = [aws_iam_role.ecs_task_execution]
}

# ECR Repository (Create if it doesn't exist, or use existing)
resource "aws_ecr_repository" "final_repo" {
  name = "final-test-repo"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [name]
  }
}

# S3 Bucket (Will create a new one if it doesn't exist)
resource "aws_s3_bucket" "pipeline_bucket" {
  bucket = "final-test-pipeline-bucket"

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [bucket]
  }
}

# ECS Cluster (Create if it doesn't exist, or use existing)
resource "aws_ecs_cluster" "final_cluster" {
  name = "final-test-cluster"
}

# ECS Task Definition (Create if it doesn't exist, or use existing)
resource "aws_ecs_task_definition" "final_task" {
  family                   = "final-test-task"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn

  container_definitions = jsonencode([
    {
      name      = "my-final-test-container",
      image     = "dummy", # Placeholder, CodePipeline will override this
      essential = true,
      portMappings = [
        {
          containerPort = 80,
          hostPort      = 80
        }
      ]
    }
  ])
}

# ECS Service (Create if it doesn't exist, or use existing)
resource "aws_ecs_service" "final_service" {
  name            = "final-test-service"
  cluster         = aws_ecs_cluster.final_cluster.id
  task_definition = aws_ecs_task_definition.final_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets         = data.aws_subnets.default.ids
    security_groups = [data.aws_security_group.default.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_task_definition.final_task]
}
