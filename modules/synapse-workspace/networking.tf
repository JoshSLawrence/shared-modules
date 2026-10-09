# With public access enabled, Synapse's firewall still blocks every network
# until a rule admits it. Public means public to all here, so one rule spans
# the whole IPv4 range.
resource "azurerm_synapse_firewall_rule" "allow_all" {
  count = var.public_network_access_enabled ? 1 : 0

  name                 = "AllowAll"
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "255.255.255.255"
}

# Lets Azure services (and resources in any Azure subscription) reach the
# public endpoints; the special 0.0.0.0-0.0.0.0 range is Azure's marker for it.
resource "azurerm_synapse_firewall_rule" "azure_services" {
  count = var.azure_services_access_enabled ? 1 : 0

  name                 = "AllowAllWindowsAzureIps"
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  start_ip_address     = "0.0.0.0"
  end_ip_address       = "0.0.0.0"
}

locals {
  private_endpoints_with_dns_zone_group    = var.private_endpoints_manage_dns_zone_group ? var.private_endpoints : {}
  private_endpoints_without_dns_zone_group = var.private_endpoints_manage_dns_zone_group ? {} : var.private_endpoints

  private_endpoints_created = merge(
    azurerm_private_endpoint.this,
    azurerm_private_endpoint.this_unmanaged_dns_zone_group,
    azurerm_private_endpoint.this_unmanaged_dns_zone_group,
  )
}

# Endpoints come from one of two resources, depending on who manages their
# private DNS zone group. When this module does, the zone group is part of
# the configuration. When something else does (typically an Azure Policy that
# attaches it after creation), the zone group must be ignored, or every apply
# would remove it. A lifecycle block can't be conditional, hence two resources.
resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints_with_dns_zone_group

  name                          = coalesce(each.value.name, "pep-${var.name}-${lower(each.key)}")
  custom_network_interface_name = coalesce(each.value.network_interface_name, "nic-pep-${var.name}-${lower(each.key)}")
  resource_group_name           = coalesce(each.value.resource_group_name, var.resource_group_name)
  location                      = coalesce(each.value.location, var.location)
  subnet_id                     = each.value.subnet_id
  tags                          = var.tags

  private_service_connection {
    name                           = "privatelink"
    private_connection_resource_id = azurerm_synapse_workspace.this.id
    is_manual_connection           = false
    subresource_names              = [each.key]
  }

  dynamic "private_dns_zone_group" {
    for_each = length(each.value.private_dns_zone_ids) > 0 ? [1] : []

    content {
      name                 = "privatedns"
      private_dns_zone_ids = each.value.private_dns_zone_ids
    }
  }

  dynamic "ip_configuration" {
    for_each = each.value.private_ip_address == null ? [] : [1]

    content {
      name               = "ipconfig"
      private_ip_address = each.value.private_ip_address
      subresource_name   = each.key
      member_name        = each.key
    }
  }
}

resource "azurerm_private_endpoint" "this_unmanaged_dns_zone_group" {
  for_each = local.private_endpoints_without_dns_zone_group

  name                          = coalesce(each.value.name, "pep-${var.name}-${lower(each.key)}")
  custom_network_interface_name = coalesce(each.value.network_interface_name, "nic-pep-${var.name}-${lower(each.key)}")
  resource_group_name           = coalesce(each.value.resource_group_name, var.resource_group_name)
  location                      = coalesce(each.value.location, var.location)
  subnet_id                     = each.value.subnet_id
  tags                          = var.tags

  private_service_connection {
    name                           = "privatelink"
    private_connection_resource_id = azurerm_synapse_workspace.this.id
    is_manual_connection           = false
    subresource_names              = [each.key]
  }

  dynamic "ip_configuration" {
    for_each = each.value.private_ip_address == null ? [] : [1]

    content {
      name               = "ipconfig"
      private_ip_address = each.value.private_ip_address
      subresource_name   = each.key
      member_name        = each.key
    }
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_synapse_managed_private_endpoint" "this" {
  for_each = var.managed_private_endpoints

  name                 = coalesce(each.value.name, each.key)
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  target_resource_id   = each.value.target_resource_id
  subresource_name     = each.value.subresource_name

  # Created through the workspace's dev endpoint, which is only reachable
  # once a firewall rule or private endpoints exist
  depends_on = [
    azurerm_synapse_firewall_rule.allow_all,
    azurerm_synapse_firewall_rule.azure_services,
    azurerm_private_endpoint.this,
    azurerm_private_endpoint.this_unmanaged_dns_zone_group,
  ]

  # Azure fills in the FQDNs itself for some targets (e.g. Key Vault's
  # vault), and azurerm declares the attribute Optional + ForceNew but not
  # Computed (checked at v5.8.0), so leaving it unset would plan a
  # replacement on every run. This module never sets it. Remove the ignore
  # if an input for it is ever added (e.g. for Private Link Service
  # targets).
  lifecycle {
    ignore_changes = [fully_qualified_domain_names]
  }
}

resource "azurerm_synapse_managed_private_endpoint" "storage" {
  for_each = toset(var.storage_managed_private_endpoints)

  name                 = "${basename(local.storage_account_id)}-${each.key}"
  synapse_workspace_id = azurerm_synapse_workspace.this.id
  target_resource_id   = local.storage_account_id
  subresource_name     = each.key

  depends_on = [
    azurerm_synapse_firewall_rule.allow_all,
    azurerm_synapse_firewall_rule.azure_services,
    azurerm_private_endpoint.this,
    azurerm_private_endpoint.this_unmanaged_dns_zone_group,
  ]

  # Azure fills in the FQDNs itself for some targets (e.g. Key Vault's
  # vault), and azurerm declares the attribute Optional + ForceNew but not
  # Computed (checked at v5.8.0), so leaving it unset would plan a
  # replacement on every run. This module never sets it. Remove the ignore
  # if an input for it is ever added (e.g. for Private Link Service
  # targets).
  lifecycle {
    ignore_changes = [fully_qualified_domain_names]
  }
}
