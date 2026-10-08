locals {
  private_endpoints_with_dns_zone_group    = var.private_endpoints_manage_dns_zone_group ? var.private_endpoints : {}
  private_endpoints_without_dns_zone_group = var.private_endpoints_manage_dns_zone_group ? {} : var.private_endpoints

  private_endpoints_created = merge(
    azurerm_private_endpoint.this,
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
    private_connection_resource_id = azurerm_mssql_server.this.id
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
    private_connection_resource_id = azurerm_mssql_server.this.id
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
