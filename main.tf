# Use existing IAM role if it exists, otherwise create one
data "aws_iam_role" "existing_ecs_task_execution" {
  name = "ecsTaskExecutionRole"
}

resource "aws_iam_role" "ecs_task_execution_role" {
  count = can(data.aws_iam_role.existing_ecs_task_execution.arn) ? 0 : 1
  name  = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  count      = length(aws_iam_role.ecs_task_execution_role) > 0 ? 1 : 0
  role       = aws_iam_role.ecs_task_execution_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Local value to use correct IAM role ARN
locals {
  ecs_task_execution_role_arn = (
    can(data.aws_iam_role.existing_ecs_task_execution.arn)
    ? data.aws_iam_role.existing_ecs_task_execution.arn
    : aws_iam_role.ecs_task_execution_role[0].arn
  )
}

# ECS Task Definition
resource "aws_ecs_task_definition" "final_test_task" {
  family                   = "final-test-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = local.ecs_task_execution_role_arn

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
