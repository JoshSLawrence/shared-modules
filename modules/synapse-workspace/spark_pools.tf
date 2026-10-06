resource "azurerm_synapse_spark_pool" "this" {
  for_each = var.spark_pools

  name                                = coalesce(each.value.name, each.key)
  synapse_workspace_id                = azurerm_synapse_workspace.this.id
  spark_version                       = each.value.spark_version
  node_size_family                    = each.value.node_size_family
  node_size                           = each.value.node_size
  node_count                          = each.value.node_count
  cache_size                          = each.value.cache_size
  dynamic_executor_allocation_enabled = each.value.dynamic_executor_allocation_enabled
  session_level_packages_enabled      = each.value.session_level_packages_enabled
  spark_events_folder                 = each.value.spark_events_folder
  spark_log_folder                    = each.value.spark_log_folder
  tags                                = var.tags

  dynamic "auto_scale" {
    for_each = each.value.node_count == null ? [1] : []

    content {
      min_node_count = each.value.auto_scale_min_node_count
      max_node_count = each.value.auto_scale_max_node_count
    }
  }

  dynamic "auto_pause" {
    for_each = each.value.auto_pause_delay_in_minutes > 0 ? [1] : []

    content {
      delay_in_minutes = each.value.auto_pause_delay_in_minutes
    }
  }
}
