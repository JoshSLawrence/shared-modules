tflint {
  required_version = ">= 0.64.0"
}

config {
  # stdout format
  format = "default"

  # where plugins are installed
  plugin_dir = "~/.tflint.d/plugins"

  # lint the root module, no remote module sources
  call_module_type = "local"

  # change exit code on lint failure
  force = false

  # are plugin default enabled rules, enabled
  disabled_by_default = false
}

plugin "azurerm" {
  enabled = true
  version = "0.32.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

# Approved exception: prevent_destroy can't reference a variable on this
# module's OpenTofu floor (1.9.0; variables are only allowed from 1.12), and
# hardcoding it would make the module impossible to destroy, including in
# integration tests. Callers protect data-bearing resources with the
# module's `lock` input (an Azure management lock) instead, which also
# guards against deletion from the portal or CLI.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}
