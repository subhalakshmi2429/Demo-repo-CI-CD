provider "aws" {
  region = "ap-south-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  suffix = random_id.suffix.hex
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "demo-pipeline-bucket-${local.suffix}"
  force_destroy = true
}

resource "aws_iam_role" "codebuild_role" {
  name = "demo-codebuild-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    } ]
  })
}

resource "aws_codebuild_project" "example" {
  name          = "demo-codebuild-${local.suffix}"
  description   = "Demo build project"
  build_timeout = 5

  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "demo-codepipeline-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Effect    = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action    = "sts:AssumeRole"
    } ]
  })
}

# Static ECS Cluster with the name "final-test-cluster"
resource "aws_ecs_cluster" "final_test_cluster" {
  name = "final-test-cluster"
}

# IAM role for ECS Task Execution
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [ {
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    } ]
  })
}

# Attach the necessary policy to the execution role
resource "aws_iam_role_policy_attachment" "ecs_execution_policy_attachment" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Static ECS Task Definition with the name "final-test-task"
resource "aws_ecs_task_definition" "final_test_task" {
  family                   = "final-test-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "my-final-test-container"  # This must match the container name in imagedefinitions.json
    image     = "",                        # This will be updated dynamically during deployment
    essential = true,
    portMappings = [ {
      containerPort = 80,
      hostPort      = 80
    } ]
  }])
}

# Static ECS Service with the name "final-test-service"
resource "aws_ecs_service" "final_test_service" {
  name            = "final-test-service"
  cluster         = aws_ecs_cluster.final_test_cluster.id
  task_definition = aws_ecs_task_definition.final_test_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [data.aws_vpc.default.id]  # Use default VPC
    assign_public_ip = true
    security_groups  = [data.aws_security_group.default.id]  # Use default security group
  }
}

# Data source for default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source for default security group
data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
}

resource "aws_codepipeline" "example" {
  name     = "demo-pipeline-${local.suffix}"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["source_output"]

      configuration = {
        RepositoryName = "demo-repo"
        BranchName     = "main"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"

      configuration = {
        ProjectName = aws_codebuild_project.example.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "ECS"
      input_artifacts  = ["build_output"]
      version          = "1"

      configuration = {
        ClusterName   = aws_ecs_cluster.final_test_cluster.name
        ServiceName   = aws_ecs_service.final_test_service.name
        FileName      = "imagedefinitions.json"  # This tells ECS to pick the image from the artifact
      }
    }
  }
}
