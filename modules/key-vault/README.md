<!-- BEGIN_TF_DOCS -->
# Key Vault

Azure Key Vault with RBAC authorization, purge protection, a deny-by-default firewall, and optional private endpoints.

## Usage

Reference this module from a root (or child) module, pinned to a released, module-scoped tag:

```hcl
module "key-vault" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/key-vault?ref=key-vault/vX.Y.Z"

  # module inputs...
}
```

Or over SSH:

```hcl
module "key-vault" {
  source = "git::ssh://git@github.com/JoshSLawrence/shared-modules.git//modules/key-vault?ref=key-vault/vX.Y.Z"

  # module inputs...
}
```

Always pin `ref` to a released tag — see [Versioning and Releases](../../CONTRIBUTING.md#versioning-and-releases) — rather than a branch. Released versions of this module are listed on the repo's [Releases](https://github.com/JoshSLawrence/shared-modules/releases) page as `key-vault/vX.Y.Z`.

See [CHANGELOG.md](./CHANGELOG.md) for version history and upgrade notes.

## Defaults

The vault is private and locked down unless you opt out:

- **Private** (`public_network_access_enabled = false`): no public
  endpoint; reach the vault through `private_endpoints` (sub-resource
  `vault`). Set `public_network_access_enabled = true` to open it to every
  network instead (still behind Entra ID). There's no IP-restricted middle
  state.
- **RBAC authorization only**; grant data access with `role_assignments`
  (e.g. `Key Vault Secrets User`). Access policies aren't supported.
- **Purge protection on**, with 90 days of soft delete retention.
- Optional `diagnostic_settings` (logs and metrics to Log Analytics, all
  categories unless you list specific ones) and
  `lock` (an Azure management lock against deletion).

Creating secrets, keys or certificates uses the vault's data plane: the
identity running OpenTofu needs a data role on the vault and network access
to it (e.g. through its private endpoint).

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
module "key_vault" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/key-vault?ref=key-vault/vX.Y.Z"

  name                = "kv-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus"

  private_endpoints = {
    vault = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.vault.id]
    }
  }

  lock = {
    kind = "CanNotDelete"
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
| [azurerm_key_vault.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | Send the vault's logs (including audit events) and metrics to a Log Analytics workspace. `null` (the default) disables diagnostics.<br/><br/>- `log_categories`: log categories to enable. `null` (the default)<br/>  enables the `allLogs` category group; `[]` enables no logs.<br/>- `metric_categories`: metric categories to enable. `null` (the default)<br/>  enables `AllMetrics`; `[]` enables no metrics.<br/><br/>At least one log or metric category must end up enabled. | <pre>object({<br/>    log_analytics_workspace_id = string<br/>    name                       = optional(string, "diag-log-analytics")<br/>    log_categories             = optional(list(string))<br/>    metric_categories          = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region to create the Key Vault in (e.g. `eastus`). | `string` | n/a | yes |
| <a name="input_lock"></a> [lock](#input\_lock) | Management lock on the vault, protecting it from accidental deletion<br/>(`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to<br/>`lock-<vault name>`. `null` (the default) creates no lock. | <pre>object({<br/>    kind  = string<br/>    name  = optional(string)<br/>    notes = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Key Vault (e.g. `kv-myapp-prod`). Must be globally unique. | `string` | n/a | yes |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints to create, keyed by target sub-resource. Key Vault has a<br/>single sub-resource, `vault`.<br/><br/>- `subnet_id` - subnet to place the endpoint's network interface in.<br/>- `private_dns_zone_ids` - private DNS zones to register the<br/>  endpoint in (normally the `privatelink.vaultcore.azure.net` zone).<br/>  Leave empty when DNS is managed elsewhere: set<br/>  `private_endpoints_manage_dns_zone_group = false` if an Azure<br/>  Policy registers the endpoints.<br/>- `private_ip_address` - static IP from the subnet (e.g.<br/>  `cidrhost(<subnet prefix>, 5)`). `null` lets Azure assign one.<br/>- `name` / `network_interface_name` - default to `pep-<vault name>` and<br/>  `nic-pep-<vault name>`.<br/>- `resource_group_name` / `location` - default to the vault's. | <pre>map(object({<br/>    subnet_id              = string<br/>    private_dns_zone_ids   = optional(list(string), [])<br/>    private_ip_address     = optional(string)<br/>    name                   = optional(string)<br/>    network_interface_name = optional(string)<br/>    resource_group_name    = optional(string)<br/>    location               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Who registers `private_endpoints` in private DNS:<br/><br/>- `true` (the default) - this module: each endpoint gets a private DNS<br/>  zone group for its `private_dns_zone_ids`, and Azure writes the A<br/>  records.<br/>- `false` - something else, typically an Azure Policy that attaches a<br/>  zone group pointing at centrally managed zones after the endpoint is<br/>  created (as in Azure landing zones). The module leaves zone groups<br/>  alone so applies don't remove them, and `private_dns_zone_ids` must be<br/>  empty.<br/><br/>Changing this recreates the endpoints. | `bool` | `true` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Network access to the vault:<br/><br/>- `false` (the default) - private: the public endpoint is disabled and<br/>  the vault is reachable only through `private_endpoints`.<br/>- `true` - public: the endpoint accepts traffic from every network<br/>  (still subject to Entra ID authorization). | `bool` | `false` | no |
| <a name="input_purge_protection_enabled"></a> [purge\_protection\_enabled](#input\_purge\_protection\_enabled) | Prevent deleted vaults and objects from being purged until the retention<br/>period ends. Required for customer-managed keys (e.g. Synapse or Storage<br/>encryption). Once enabled it can't be disabled. | `bool` | `true` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to create the Key Vault (and its private endpoints, unless overridden) in. | `string` | n/a | yes |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | Azure RBAC role assignments scoped to the vault, keyed by an arbitrary<br/>static name. The vault uses RBAC authorization (not access policies), so<br/>this is how identities get data access, e.g.:<pre>hcl<br/>role_assignments = {<br/>  deployer_secrets_officer = {<br/>    role_definition_id_or_name = "Key Vault Secrets Officer"<br/>    principal_id               = data.azurerm_client_config.current.object_id<br/>  }<br/>}</pre>`role_definition_id_or_name` takes a built-in role name or a full role<br/>definition resource ID (starting with `/`). | <pre>map(object({<br/>    role_definition_id_or_name       = string<br/>    principal_id                     = string<br/>    principal_type                   = optional(string)<br/>    description                      = optional(string)<br/>    condition                        = optional(string)<br/>    condition_version                = optional(string)<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | Key Vault SKU: `standard` or `premium` (HSM-backed keys). | `string` | `"standard"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | Days (7-90) that deleted vaults and objects are retained before they can be purged. Can't be changed after creation. | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every resource this module creates. | `map(string)` | `{}` | no |
| <a name="input_tenant_id"></a> [tenant\_id](#input\_tenant\_id) | Entra ID tenant used to authenticate requests to the vault. `null` uses the tenant of the identity running OpenTofu. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the Key Vault. |
| <a name="output_name"></a> [name](#output\_name) | Name of the Key Vault. |
| <a name="output_private_dns_records"></a> [private\_dns\_records](#output\_private\_dns\_records) | DNS records Azure registered for this module's private endpoints (one<br/>per record), e.g. to check name resolution or document the network:<br/><br/>- `resource` / `subresource` - the resource and sub-resource (the<br/>  `private_endpoints` key) the record points at.<br/>- `zone_name` - private DNS zone holding the record (e.g.<br/>  `privatelink.blob.core.windows.net`).<br/>- `name` / `fqdn` - host name within the zone and its fully qualified<br/>  name.<br/>- `type` - record type (`A`).<br/>- `ip_addresses` - the endpoint's private IP address(es).<br/>- `ttl` - time to live, in seconds.<br/><br/>Includes records registered by an Azure Policy when<br/>`private_endpoints_manage_dns_zone_group` is `false`, once the policy<br/>has run and state is refreshed. Known after apply. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | Private endpoints created, keyed by sub-resource, with their `id` and `private_ip_address`. |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Entra ID tenant the Key Vault authenticates requests against. |
| <a name="output_vault_uri"></a> [vault\_uri](#output\_vault\_uri) | Data plane URI of the Key Vault (e.g. `https://kv-myapp-prod.vault.azure.net/`). |
<!-- END_TF_DOCS -->