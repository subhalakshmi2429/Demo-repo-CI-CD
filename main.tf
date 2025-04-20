provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Lookup default VPC
data "aws_vpc" "default" {
  default = true
}

# Get default subnet(s)
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Get default security group
data "aws_security_group" "default" {
  name   = "default"
  vpc_id = data.aws_vpc.default.id
}

# Use existing IAM role if it exists, otherwise create one
data "aws_iam_role" "existing_ecs_task_execution" {
  name = "ecsTaskExecutionRole"
  depends_on = []
}

resource "aws_iam_role" "ecs_task_execution_role" {
  count = length(try(data.aws_iam_role.existing_ecs_task_execution.name, "")) > 0 ? 0 : 1
  name  = "ecsTaskExecutionRole"

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

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  count      = length(try(data.aws_iam_role.existing_ecs_task_execution.name, "")) > 0 ? 0 : 1
  role       = aws_iam_role.ecs_task_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Get ECR repo or create it
resource "aws_ecr_repository" "final_test_repo" {
  name = "final-test-repo"
}

# Docker login
resource "null_resource" "ecr_login" {
  provisioner "local-exec" {
    command = <<EOT
      aws ecr get-login-password --region ${data.aws_region.current.name} \
      | docker login --username AWS --password-stdin \
      ${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com
    EOT
  }
}

# Build and push Docker image
resource "null_resource" "build_and_push_image" {
  depends_on = [null_resource.ecr_login]

  provisioner "local-exec" {
    command = <<EOT
      docker build -t final-test-repo ./app
      docker tag final-test-repo:latest ${aws_ecr_repository.final_test_repo.repository_url}:latest
      docker push ${aws_ecr_repository.final_test_repo.repository_url}:latest
    EOT
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "final_test_cluster" {
  name = "final-test-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "final_test_task" {
  family                   = "final-test-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = coalesce(
    try(data.aws_iam_role.existing_ecs_task_execution.arn, ""),
    aws_iam_role.ecs_task_execution_role[0].arn
  )

  container_definitions = jsonencode([{
    name      = "my-final-test-container"
    image     = "${aws_ecr_repository.final_test_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

# ECS Service
resource "aws_ecs_service" "final_test_service" {
  name            = "final-test-service"
  cluster         = aws_ecs_cluster.final_test_cluster.id
  task_definition = aws_ecs_task_definition.final_test_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [data.aws_security_group.default.id]
    assign_public_ip = true
  }

  depends_on = [aws_ecs_task_definition.final_test_task]
}
