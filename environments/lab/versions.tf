terraform {
  required_version = ">= 1.12.2, < 2.0.0"
  backend "local" {
    path          = "/var/lib/jenkins/terraform-state/kt-lab/infrastructure.tfstate"
    workspace_dir = "/var/lib/jenkins/terraform-state/kt-lab/workspaces"
  }
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.62.0"
    }
  }
}
