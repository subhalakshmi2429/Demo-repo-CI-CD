# Lookup your default VPC, subnets & SG
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
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "my-final-test-container"
    image     = ""  # overridden by imagedefinitions.json
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
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = slice(data.aws_subnets.default.ids, 0, 2)
    security_groups  = [data.aws_security_group.default.id]
    assign_public_ip = true
  }

  depends_on = [ aws_ecs_task_definition.final_test_task ]
}

# CodePipeline Deploy stage (excerpt)
resource "aws_codepipeline" "example" {
  # … other stages …

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      input_artifacts = ["build_output"]
      version         = "1"

      configuration = {
        ClusterName = aws_ecs_cluster.final_test_cluster.name
        ServiceName = aws_ecs_service.final_test_service.name
        FileName    = "imagedefinitions.json"
      }
    }
  }
}
