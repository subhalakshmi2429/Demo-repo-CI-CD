provider "aws" {
  region = "ap-south-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  suffix = random_id.suffix.hex
  container_name = "my-container-${local.suffix}"
}

resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket        = "demo-pipeline-bucket-${local.suffix}"
  force_destroy = true
}

resource "aws_iam_role" "codebuild_role" {
  name = "demo-codebuild-role-${local.suffix}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
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
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "codepipeline.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
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
      output_artifacts = []

      configuration = {
        ClusterName          = "your-cluster-name"
        ServiceName          = "your-service-name"
        FileName             = "imagedefinitions.json"
        ContainerName        = local.container_name
      }
    }
  }
}

resource "aws_ecs_task_definition" "example" {
  family                   = "demo-task-family-${local.suffix}"
  requires_compatibilities = ["FARGATE"]
  network_mode            = "awsvpc"
  cpu                     = "256"
  memory                  = "512"

  container_definitions = jsonencode([
    {
      name      = local.container_name  # Using dynamic container name here
      image     = "574720314262.dkr.ecr.ap-south-1.amazonaws.com/final-test-repo:${local.container_name}"
      essential = true
      cpu       = 256
      memory    = 512
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
