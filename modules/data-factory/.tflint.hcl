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
