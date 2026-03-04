terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

# Primary region (us-east-1)
provider "aws" {
  region = var.primary_region
  alias  = "primary"

  default_tags {
    tags = {
      Project     = "Multi-Region-DR"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Secondary region (us-west-2) for backups
provider "aws" {
  region = var.secondary_region
  alias  = "secondary"

  default_tags {
    tags = {
      Project     = "Multi-Region-DR"
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
