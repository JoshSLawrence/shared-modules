tflint {
  required_version = ">= 0.64.0"
}

config {
  # stdout format
  format = "default"

  # where plugins are installed
  plugin_dir = "~/.tflint.d/plugins"

  # lint this root module; it calls no modules
  call_module_type = "local"

  # change exit code on lint failure
  force = false

  # are plugin default enabled rules, enabled
  disabled_by_default = false
}

