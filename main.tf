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
      version          = "1"  # Ensure the correct lowercase 'version'
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
      version          = "1"  # Ensure the correct lowercase 'version'

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
      version          = "1"  # Ensure the correct lowercase 'version'
      input_artifacts  = ["build_output"]
      output_artifacts = []

      configuration = {
        ClusterName   = "your-cluster-name"
        ServiceName   = "your-service-name"
        FileName      = "imagedefinitions.json"
        ContainerName = "your-container-name"  # Ensure this is set dynamically if needed
      }
    }
  }
}
