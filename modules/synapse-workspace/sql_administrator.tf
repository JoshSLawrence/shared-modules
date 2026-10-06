# Synapse requires a SQL administrator login and password at creation, even
# when only Entra ID authentication is allowed, so one is generated unless the
# caller supplies it.
resource "random_password" "sql_administrator" {
  count = var.sql_administrator_password == null ? 1 : 0

  length      = 32
  special     = true
  min_lower   = 1
  min_upper   = 1
  min_numeric = 1
  min_special = 1
  # Characters that don't need escaping in connection strings or shells
  override_special = "!#%*()-_=+[]{}:?"
}

locals {
  sql_administrator_password = var.sql_administrator_password == null ? random_password.sql_administrator[0].result : var.sql_administrator_password
}

# Approved exception: AZU-0017 wants every secret to expire. This password
# doesn't rotate, so a forced expiry could cut off whatever reads the secret
# (e.g. linked services); callers opt in with
# sql_administrator_password_secret.expiration_date instead.
#trivy:ignore:AZU-0017
resource "azurerm_key_vault_secret" "sql_administrator_password" {
  count = var.sql_administrator_password_secret == null ? 0 : 1

  name            = coalesce(var.sql_administrator_password_secret.name, "${var.name}-sql-admin-password")
  key_vault_id    = var.sql_administrator_password_secret.key_vault_id
  value           = local.sql_administrator_password
  content_type    = "password"
  expiration_date = var.sql_administrator_password_secret.expiration_date
  tags            = var.tags
}

resource "azurerm_synapse_workspace_aad_admin" "this" {
  count = var.entra_admin == null ? 0 : 1

  synapse_workspace_id = azurerm_synapse_workspace.this.id
  login                = var.entra_admin.login
  object_id            = var.entra_admin.object_id
  tenant_id            = coalesce(var.entra_admin.tenant_id, data.azurerm_client_config.current.tenant_id)
}
