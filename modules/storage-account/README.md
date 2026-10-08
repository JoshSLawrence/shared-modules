<!-- BEGIN_TF_DOCS -->
# Storage Account

Azure Storage Account (optionally ADLS Gen2) with a deny-by-default firewall, Entra ID-only auth by default, containers created via the control plane, and optional private endpoints.

## Usage

Reference this module from a root (or child) module, pinned to a released, module-scoped tag:

```hcl
module "storage-account" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/vX.Y.Z"

  # module inputs...
}
```

Or over SSH:

```hcl
module "storage-account" {
  source = "git::ssh://git@github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/vX.Y.Z"

  # module inputs...
}
```

Always pin `ref` to a released tag — see [Versioning and Releases](../../CONTRIBUTING.md#versioning-and-releases) — rather than a branch. Released versions of this module are listed on the repo's [Releases](https://github.com/JoshSLawrence/shared-modules/releases) page as `storage-account/vX.Y.Z`.

See [CHANGELOG.md](./CHANGELOG.md) for version history and upgrade notes.

## Defaults

The account is private and locked down unless you opt out:

- **Private** (`public_network_access_enabled = false`): no public
  endpoints; reach the account through `private_endpoints` (`blob`, `dfs`,
  `file`, `queue`, `table`, `web`). Set `public_network_access_enabled = true`
  to open it to every network instead (still behind Entra ID). There's no
  IP-restricted middle state.
- **Entra ID only**: Shared Key (account key and SAS) auth is disabled.
- TLS 1.2, HTTPS only, no anonymous blob access, infrastructure
  encryption, and no cross-tenant replication.
- Blob and container soft delete for 7 days.
- Optional `diagnostic_settings` (blob read/write/delete logs and
  transaction metrics to Log Analytics, with configurable categories),
  `lock` (an Azure management lock against deletion), and
  `role_assignments` (account-scoped) and `containers[*].role_assignments`
  (container-scoped).

Set `is_hns_enabled = true` for an ADLS Gen2 (Data Lake) account. Its
`containers` are file systems, and the `containers` output gives each one's
`data_lake_filesystem_id`, e.g. for the synapse-workspace module's
`existing_storage`.

Containers are created through Azure Resource Manager rather than the
storage data plane, so OpenTofu needs neither network access to a private
account nor Shared Key auth to manage them.

## Private DNS

Clients resolve a private endpoint through an A record in the service's
`privatelink.*` private DNS zone. Either this module registers it, or
something else does:

- **Module-managed** (default): pass each endpoint's `private_dns_zone_ids`.
  The module adds a DNS zone group, and Azure writes, updates and deletes
  the A record with the endpoint.
- **Policy-managed**: set `private_endpoints_manage_dns_zone_group = false`
  and leave `private_dns_zone_ids` out. An Azure Policy (e.g. the built-in
  "Configure ... private endpoints to use private DNS zones" policies used by
  Azure landing zones) attaches the zone group after the endpoint is
  created, and the module leaves it alone on later applies.

Either way, the `private_dns_records` output lists the registered records
(zone, host name, type and IP).

## Example

```hcl
module "data_lake" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account?ref=storage-account/vX.Y.Z"

  name                = "stmyappprod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus"
  is_hns_enabled      = true

  containers = {
    bronze = {}
    silver = {}
    gold   = {}
  }

  private_endpoints = {
    dfs = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.dfs.id]
    }
  }
}
```

See [examples/](./examples) for complete root modules.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 5.7.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.7.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.account](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_monitor_diagnostic_setting.blob](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.containers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access_tier"></a> [access\_tier](#input\_access\_tier) | Default access tier for blob data: `Hot`, `Cool` or `Cold`. Ignored for Premium accounts. | `string` | `"Hot"` | no |
| <a name="input_account_kind"></a> [account\_kind](#input\_account\_kind) | Storage account kind: `StorageV2` (general purpose v2), `BlockBlobStorage` or `FileStorage` (both Premium only). | `string` | `"StorageV2"` | no |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | Replication: `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS` or `RAGZRS`. | `string` | `"RAGRS"` | no |
| <a name="input_account_tier"></a> [account\_tier](#input\_account\_tier) | Performance tier: `Standard` or `Premium`. | `string` | `"Standard"` | no |
| <a name="input_blob_properties"></a> [blob\_properties](#input\_blob\_properties) | Blob service data protection:<br/><br/>- `versioning_enabled` - keep previous versions of overwritten blobs.<br/>- `change_feed_enabled` - log blob changes to the change feed.<br/>- `delete_retention_days` / `container_delete_retention_days` - soft<br/>  delete retention (1-365 days) for blobs and containers; `0` disables<br/>  it.<br/><br/>Synapse's default storage doesn't support versioning or soft delete; the<br/>synapse-workspace module turns them off for the account it creates. | <pre>object({<br/>    versioning_enabled              = optional(bool, false)<br/>    change_feed_enabled             = optional(bool, false)<br/>    delete_retention_days           = optional(number, 7)<br/>    container_delete_retention_days = optional(number, 7)<br/>  })</pre> | `{}` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | Private blob containers (Data Lake file systems when `is_hns_enabled` is<br/>`true`) to create, keyed by an arbitrary static name. `name` defaults to<br/>the key.<br/><br/>`role_assignments` grants Azure RBAC roles scoped to the container alone<br/>(same shape as the account-level `role_assignments`), e.g. Storage Blob<br/>Data Reader on one container, so a principal sees that container's data<br/>and no other's.<br/><br/>Containers are created through Azure Resource Manager, not the storage<br/>data plane, so OpenTofu doesn't need network access to a private account<br/>or Shared Key auth to manage them. | <pre>map(object({<br/>    name     = optional(string)<br/>    metadata = optional(map(string), {})<br/>    role_assignments = optional(map(object({<br/>      role_definition_id_or_name       = string<br/>      principal_id                     = string<br/>      principal_type                   = optional(string)<br/>      description                      = optional(string)<br/>      condition                        = optional(string)<br/>      condition_version                = optional(string)<br/>      skip_service_principal_aad_check = optional(bool, false)<br/>    })), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | Send the account's metrics, and the blob service's logs and metrics, to a<br/>Log Analytics workspace. `null` (the default) disables diagnostics.<br/><br/>- `log_categories`: blob service log categories to enable. `null`<br/>  (the default) enables `StorageRead`, `StorageWrite` and `StorageDelete`;<br/>  `[]` enables none.<br/>- `metric_categories`: metric categories to enable on both the account<br/>  and the blob service. `null` (the default) enables `Transaction`; `[]`<br/>  enables none. The account-level setting is only created when at least<br/>  one metric category is enabled.<br/><br/>At least one log or metric category must end up enabled. | <pre>object({<br/>    log_analytics_workspace_id = string<br/>    name                       = optional(string, "diag-log-analytics")<br/>    log_categories             = optional(list(string))<br/>    metric_categories          = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_infrastructure_encryption_enabled"></a> [infrastructure\_encryption\_enabled](#input\_infrastructure\_encryption\_enabled) | Encrypt data a second time at the infrastructure level, with a different algorithm and key. Can't be changed after creation. | `bool` | `true` | no |
| <a name="input_is_hns_enabled"></a> [is\_hns\_enabled](#input\_is\_hns\_enabled) | Enable the hierarchical namespace, making this an Azure Data Lake Storage Gen2 account (required for Synapse). Can't be changed after creation. | `bool` | `false` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region to create the storage account in (e.g. `eastus`). | `string` | n/a | yes |
| <a name="input_lock"></a> [lock](#input\_lock) | Management lock on the storage account, protecting it from accidental<br/>deletion (`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to<br/>`lock-<account name>`. `null` (the default) creates no lock.<br/><br/>A `ReadOnly` lock also blocks listing account keys and creating<br/>containers through Azure Resource Manager.<br/><br/>Azure refuses to delete role assignments and diagnostic settings under a<br/>scope with a `CanNotDelete` lock, so revoking a grant or changing<br/>diagnostics needs the lock lifted first. | <pre>object({<br/>    kind  = string<br/>    name  = optional(string)<br/>    notes = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the storage account (e.g. `stmyappprod`). Must be globally unique. | `string` | n/a | yes |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints to create, keyed by target sub-resource: `blob`, `dfs`,<br/>`file`, `queue`, `table` or `web` (or their `_secondary` variants for<br/>RA-GRS/RA-GZRS accounts). Data Lake clients need both `blob` and `dfs`.<br/><br/>- `subnet_id` - subnet to place the endpoint's network interface in.<br/>- `private_dns_zone_ids` - private DNS zones to register the<br/>  endpoint in (e.g. `privatelink.blob.core.windows.net` for `blob`,<br/>  `privatelink.dfs.core.windows.net` for `dfs`). Leave empty when<br/>  DNS is managed elsewhere: set<br/>  `private_endpoints_manage_dns_zone_group = false` if an Azure<br/>  Policy registers the endpoints.<br/>- `private_ip_address` - static IP from the subnet (e.g.<br/>  `cidrhost(<subnet prefix>, 4)`). `null` lets Azure assign one.<br/>- `name` / `network_interface_name` - default to<br/>  `pep-<account name>-<sub-resource>` and `nic-pep-<account name>-<sub-resource>`.<br/>- `resource_group_name` / `location` - default to the account's. | <pre>map(object({<br/>    subnet_id              = string<br/>    private_dns_zone_ids   = optional(list(string), [])<br/>    private_ip_address     = optional(string)<br/>    name                   = optional(string)<br/>    network_interface_name = optional(string)<br/>    resource_group_name    = optional(string)<br/>    location               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Who registers `private_endpoints` in private DNS:<br/><br/>- `true` (the default) - this module: each endpoint gets a private DNS<br/>  zone group for its `private_dns_zone_ids`, and Azure writes the A<br/>  records.<br/>- `false` - something else, typically an Azure Policy that attaches a<br/>  zone group pointing at centrally managed zones after the endpoint is<br/>  created (as in Azure landing zones). The module leaves zone groups<br/>  alone so applies don't remove them, and `private_dns_zone_ids` must be<br/>  empty.<br/><br/>Changing this recreates the endpoints. | `bool` | `true` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Network access to the account:<br/><br/>- `false` (the default) - private: the public endpoints are disabled and<br/>  the account is reachable only through `private_endpoints`.<br/>- `true` - public: the endpoints accept traffic from every network<br/>  (still subject to Entra ID authorization). | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to create the storage account (and its private endpoints, unless overridden) in. | `string` | n/a | yes |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | Azure RBAC role assignments scoped to the storage account, keyed by an<br/>arbitrary static name, e.g. to give a Data Factory access to blob data:<pre>hcl<br/>role_assignments = {<br/>  adf_blob_contributor = {<br/>    role_definition_id_or_name = "Storage Blob Data Contributor"<br/>    principal_id               = module.data_factory.identity_principal_id<br/>  }<br/>}</pre>`role_definition_id_or_name` takes a built-in role name or a full role<br/>definition resource ID (starting with `/`). | <pre>map(object({<br/>    role_definition_id_or_name       = string<br/>    principal_id                     = string<br/>    principal_type                   = optional(string)<br/>    description                      = optional(string)<br/>    condition                        = optional(string)<br/>    condition_version                = optional(string)<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_shared_access_key_enabled"></a> [shared\_access\_key\_enabled](#input\_shared\_access\_key\_enabled) | Allow Shared Key (account key and SAS) authorization. `false` (the<br/>default) requires Entra ID for every request. Callers that manage data<br/>plane objects with OpenTofu then need `storage_use_azuread = true` in<br/>their azurerm provider block. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every resource this module creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_containers"></a> [containers](#output\_containers) | Containers created, keyed like `var.containers`, with:<br/><br/>- `id` - Azure Resource Manager ID of the container.<br/>- `name` - container name.<br/>- `data_lake_filesystem_id` - the container's Data Lake file system ID<br/>  (`https://<account>.dfs.core.windows.net/<name>`), as expected by e.g.<br/>  `azurerm_synapse_workspace.storage_data_lake_gen2_filesystem_id`.<br/>  `null` unless `is_hns_enabled` is `true`. |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the storage account. |
| <a name="output_name"></a> [name](#output\_name) | Name of the storage account. |
| <a name="output_primary_blob_endpoint"></a> [primary\_blob\_endpoint](#output\_primary\_blob\_endpoint) | Primary blob service endpoint (e.g. `https://stmyappprod.blob.core.windows.net/`). |
| <a name="output_primary_dfs_endpoint"></a> [primary\_dfs\_endpoint](#output\_primary\_dfs\_endpoint) | Primary Data Lake (DFS) endpoint (e.g. `https://stmyappprod.dfs.core.windows.net/`). |
| <a name="output_private_dns_records"></a> [private\_dns\_records](#output\_private\_dns\_records) | DNS records Azure registered for this module's private endpoints (one<br/>per record), e.g. to check name resolution or document the network:<br/><br/>- `resource` / `subresource` - the resource and sub-resource (the<br/>  `private_endpoints` key) the record points at.<br/>- `zone_name` - private DNS zone holding the record (e.g.<br/>  `privatelink.blob.core.windows.net`).<br/>- `name` / `fqdn` - host name within the zone and its fully qualified<br/>  name.<br/>- `type` - record type (`A`).<br/>- `ip_addresses` - the endpoint's private IP address(es).<br/>- `ttl` - time to live, in seconds.<br/><br/>Includes records registered by an Azure Policy when<br/>`private_endpoints_manage_dns_zone_group` is `false`, once the policy<br/>has run and state is refreshed. Known after apply. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | Private endpoints created, keyed by sub-resource, with their `id` and `private_ip_address`. |
<!-- END_TF_DOCS -->