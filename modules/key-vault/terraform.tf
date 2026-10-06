terraform {
  required_version = ">= 1.9.0"

  # A shared module only declares its providers and their minimum versions
  # here — never a `provider "x" {}` block; configuring providers is the
  # caller's job (see examples/). `>=` constraints let callers pick newer
  # releases without waiting on a module release.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.7.0"
    }
  }
}
