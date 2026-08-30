terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  # Placeholder values on purpose - S3 backend config does not accept
  # variables. Either edit these to match your bootstrap output, or
  # (recommended, so nothing backend-specific is hardcoded in git)
  # pass them at init time instead:
  #
  #   terraform init \
  #     -backend-config="bucket=<state_bucket_name>" \
  #     -backend-config="dynamodb_table=<lock_table_name>" \
  #     -backend-config="region=<aws_region>"
  backend "s3" {
    bucket         = "capstone-phoenix-tfstate-CHANGEME"
    key            = "capstone-phoenix/infra-terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "capstone-phoenix-tf-lock"
    encrypt        = true
  }
}
