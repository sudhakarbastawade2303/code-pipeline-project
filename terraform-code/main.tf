# Root main.tf for full EKS + VPC + CodePipeline Infrastructure

provider "aws" {
  region = var.aws_region
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.0"

  name = "eks-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.27"

  subnet_ids         = module.vpc.private_subnets
  vpc_id             = module.vpc.vpc_id
  enable_irsa        = true
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      desired_size = 2
      max_size     = 3
      min_size     = 1

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "eks-sockshop-artifacts-${random_string.suffix.result}"
  force_destroy = true
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# IAM Roles & Policies for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_codebuild_project" "deploy" {
  name          = "sockshop-deploy"
  service_role  = aws_iam_role.codebuild_role.arn

    source {
    type            = "CODEPIPELINE"
    buildspec       = "pipeline/buildspec-deploy.yml"
    }


  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    privileged_mode             = true
    environment_variables = [
      {
        name  = "AWS_REGION"
        value = var.aws_region
      },
      {
        name  = "EKS_CLUSTER_NAME"
        value = var.cluster_name
      }
    ]
  }
}

resource "aws_iam_role" "pipeline_role" {
  name = "codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "pipeline_policy" {
  role       = aws_iam_role.pipeline_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_codepipeline" "pipeline" {
  name     = "sockshop-pipeline"
  role_arn = aws_iam_role.pipeline_role.arn

  artifact_store {
    location = aws_s3_bucket.artifacts.bucket
    type     = "S3"
  }

  stage {
  name = "Source"

  action {
    name             = "Source"
    category         = "Source"
    owner            = "ThirdParty"
    provider         = "GitHub"
    version          = "1"
    output_artifacts = ["source_output"]

    configuration = {
      Owner      = "your-github-username"
      Repo       = "your-infra-repo-name"
      Branch     = "main"
      OAuthToken = "" # leave empty if public, or pass dummy var
    }
  }
}


  stage {
    name = "Deploy"
    action {
      name             = "DeployAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      project_name     = aws_codebuild_project.deploy.name
      version          = "1"
    }
  }
}
