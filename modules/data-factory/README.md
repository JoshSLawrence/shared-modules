<!-- BEGIN_TF_DOCS -->
# Data Factory

Azure Data Factory with a managed virtual network, public network access disabled by default, managed private endpoints, and optional private endpoints.

## Usage

Reference this module from a root (or child) module, pinned to a released, module-scoped tag:

```hcl
module "data-factory" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/data-factory?ref=data-factory/vX.Y.Z"

  # module inputs...
}
```

Or over SSH:

```hcl
module "data-factory" {
  source = "git::ssh://git@github.com/JoshSLawrence/shared-modules.git//modules/data-factory?ref=data-factory/vX.Y.Z"

  # module inputs...
}
```

Always pin `ref` to a released tag — see [Versioning and Releases](../../CONTRIBUTING.md#versioning-and-releases) — rather than a branch. Released versions of this module are listed on the repo's [Releases](https://github.com/JoshSLawrence/shared-modules/releases) page as `data-factory/vX.Y.Z`.

See [CHANGELOG.md](./CHANGELOG.md) for version history and upgrade notes.

## Defaults

The factory is private unless you opt out:

- **No public endpoint** (`public_network_access_enabled = false`); reach
  ADF Studio and the factory API through `private_endpoints` (`portal`,
  `dataFactory`).
- **Managed virtual network always on**. Pipelines reach private data stores
  through `managed_private_endpoints` when they run on an integration
  runtime in that network: create one with `managed_integration_runtime`,
  or publish one from Git.
- Optional `github_configuration`, `role_assignments`,
  `diagnostic_settings` (all log and metric categories unless you list
  specific ones) and `lock` (an Azure management lock against
  deletion).

Grant the factory access to data with role assignments on the target, e.g.
the storage-account module's `role_assignments` with
`principal_id = module.data_factory.identity_principal_id`.

Managed private endpoints are created (through Azure Resource Manager)
pending approval; approve them on the target resource's private endpoint
connections.

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

## Managed private endpoints and Git

Managed private endpoints point at a specific environment's resources (dev's
storage account isn't prod's), so let this module own them in every
environment, as the synapse-workspace module does. Unlike Synapse, Data
Factory's ARM export (`ARMTemplateForFactory.json`) includes the managed
private endpoints that exist in the factory, and deploying one whose
properties differ from an existing endpoint of the same name fails. Remove
them from the template before deploying it to each environment, e.g.:

```bash
jq '.resources |= map(select(.type != "Microsoft.DataFactory/factories/managedVirtualNetworks/managedPrivateEndpoints"))' \
  ARMTemplateForFactory.json > ARMTemplateForFactory.deploy.json
```

Linked services stay in Git; they name their targets (e.g. a `dfs` URL), and
run through the matching approved managed private endpoint when they use an
integration runtime in the managed virtual network.

## Example

```hcl
module "data_factory" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/data-factory?ref=data-factory/vX.Y.Z"

  name                = "adf-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus"

  managed_integration_runtime = {}

  managed_private_endpoints = {
    data-lake-dfs = {
      target_resource_id = module.data_lake.id
      subresource_name   = "dfs"
    }
  }

  private_endpoints = {
    dataFactory = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.datafactory.id]
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
| [azurerm_data_factory.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory) | resource |
| [azurerm_data_factory_integration_runtime_azure.managed](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_integration_runtime_azure) | resource |
| [azurerm_data_factory_managed_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/data_factory_managed_private_endpoint) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | Send the factory's logs (pipeline, activity and trigger runs, and more)<br/>and metrics to a Log Analytics workspace. `null` (the default) disables<br/>diagnostics.<br/><br/>- `log_categories`: log categories to enable. `null` (the default)<br/>  enables the `allLogs` category group; `[]` enables no logs.<br/>- `metric_categories`: metric categories to enable. `null` (the default)<br/>  enables `AllMetrics`; `[]` enables no metrics.<br/><br/>At least one log or metric category must end up enabled. | <pre>object({<br/>    log_analytics_workspace_id = string<br/>    name                       = optional(string, "diag-log-analytics")<br/>    log_categories             = optional(list(string))<br/>    metric_categories          = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_github_configuration"></a> [github\_configuration](#input\_github\_configuration) | Connect ADF Studio to a GitHub repository for source control.<br/>`branch_name` is the collaboration branch and `root_folder` the folder<br/>holding factory artifacts (e.g. `/datafactory`). `git_url` is only<br/>needed for GitHub Enterprise Server. A repository admin still has to<br/>approve the Data Factory app's access. `null` (the default) leaves Git<br/>integration off. | <pre>object({<br/>    account_name       = string<br/>    repository_name    = string<br/>    branch_name        = string<br/>    root_folder        = optional(string, "/")<br/>    git_url            = optional(string)<br/>    publishing_enabled = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_identity_ids"></a> [identity\_ids](#input\_identity\_ids) | User-assigned managed identities to attach in addition to the always-on system-assigned identity. | `list(string)` | `[]` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region to create the Data Factory in (e.g. `eastus`). | `string` | n/a | yes |
| <a name="input_lock"></a> [lock](#input\_lock) | Management lock on the factory, protecting it from accidental deletion<br/>(`CanNotDelete`) or any change (`ReadOnly`). `name` defaults to<br/>`lock-<factory name>`. `null` (the default) creates no lock.<br/><br/>A `ReadOnly` lock also blocks publishing pipelines and other factory<br/>changes.<br/><br/>A `CanNotDelete` lock also blocks deleting role assignments and diagnostic<br/>settings under its scope, so revoking a grant or removing a diagnostic<br/>setting needs the lock lifted first. | <pre>object({<br/>    kind  = string<br/>    name  = optional(string)<br/>    notes = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_managed_integration_runtime"></a> [managed\_integration\_runtime](#input\_managed\_integration\_runtime) | Create an Azure integration runtime inside the managed virtual network.<br/>Activities only use managed private endpoints when they run on such a<br/>runtime; the built-in AutoResolveIntegrationRuntime runs outside it.<br/>`location` is a region or `AutoResolve`; `compute_type` is `General` or<br/>`MemoryOptimized` (data flows); `core_count` is the data flow cluster<br/>size; `time_to_live_min` keeps a data flow cluster warm between runs.<br/>`null` (the default) creates none, e.g. when integration runtimes are<br/>published from Git instead. | <pre>object({<br/>    name             = optional(string, "ir-managed-vnet")<br/>    location         = optional(string, "AutoResolve")<br/>    compute_type     = optional(string, "General")<br/>    core_count       = optional(number, 8)<br/>    time_to_live_min = optional(number, 0)<br/>    cleanup_enabled  = optional(bool, true)<br/>    description      = optional(string, "Azure integration runtime in the managed virtual network.")<br/>  })</pre> | `null` | no |
| <a name="input_managed_private_endpoints"></a> [managed\_private\_endpoints](#input\_managed\_private\_endpoints) | Managed private endpoints from the factory's managed virtual network,<br/>keyed by an arbitrary static name (the default endpoint name), e.g.:<pre>hcl<br/>managed_private_endpoints = {<br/>  data-lake-dfs = {<br/>    target_resource_id = module.storage_account.id<br/>    subresource_name   = "dfs"<br/>  }<br/>}</pre>Each endpoint is created pending approval: approve it on the target<br/>resource's private endpoint connections before it carries traffic. | <pre>map(object({<br/>    target_resource_id = string<br/>    subresource_name   = optional(string)<br/>    fqdns              = optional(list(string))<br/>    name               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Data Factory (e.g. `adf-myapp-prod`). Must be globally unique. | `string` | n/a | yes |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints to create, keyed by target sub-resource:<br/><br/>- `dataFactory` - the factory's APIs, used by self-hosted integration<br/>  runtimes and tooling (`privatelink.datafactory.azure.net`).<br/>- `portal` - ADF Studio (`privatelink.adf.azure.com`).<br/><br/>Per endpoint:<br/><br/>- `subnet_id` - subnet to place the endpoint's network interface in.<br/>- `private_dns_zone_ids` - private DNS zones to register the<br/>  endpoint in. Leave empty when DNS is managed elsewhere: set<br/>  `private_endpoints_manage_dns_zone_group = false` if an Azure<br/>  Policy registers the endpoints.<br/>- `private_ip_address` - static IP from the subnet. `null` lets Azure<br/>  assign one.<br/>- `name` / `network_interface_name` - default to<br/>  `pep-<factory name>-<sub-resource>` and `nic-pep-<factory name>-<sub-resource>`<br/>  (sub-resource lowercased).<br/>- `resource_group_name` / `location` - default to the factory's. | <pre>map(object({<br/>    subnet_id              = string<br/>    private_dns_zone_ids   = optional(list(string), [])<br/>    private_ip_address     = optional(string)<br/>    name                   = optional(string)<br/>    network_interface_name = optional(string)<br/>    resource_group_name    = optional(string)<br/>    location               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Who registers `private_endpoints` in private DNS:<br/><br/>- `true` (the default) - this module: each endpoint gets a private DNS<br/>  zone group for its `private_dns_zone_ids`, and Azure writes the A<br/>  records.<br/>- `false` - something else, typically an Azure Policy that attaches a<br/>  zone group pointing at centrally managed zones after the endpoint is<br/>  created (as in Azure landing zones). The module leaves zone groups<br/>  alone so applies don't remove them, and `private_dns_zone_ids` must be<br/>  empty.<br/><br/>Changing this recreates the endpoints. | `bool` | `true` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Enable the factory's public endpoint. When `false` (the default) ADF<br/>Studio and the factory's APIs are reachable only through private<br/>endpoints, and self-hosted integration runtimes must connect privately. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to create the Data Factory (and its private endpoints, unless overridden) in. | `string` | n/a | yes |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | Azure RBAC role assignments scoped to the factory, keyed by an arbitrary<br/>static name (e.g. `Data Factory Contributor` for developers).<br/>`role_definition_id_or_name` takes a built-in role name or a full role<br/>definition resource ID (starting with `/`). | <pre>map(object({<br/>    role_definition_id_or_name       = string<br/>    principal_id                     = string<br/>    principal_type                   = optional(string)<br/>    description                      = optional(string)<br/>    condition                        = optional(string)<br/>    condition_version                = optional(string)<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every resource this module creates. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the Data Factory. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Object ID of the factory's system-assigned managed identity, e.g. to grant it access to storage or Key Vault. |
| <a name="output_managed_integration_runtime_name"></a> [managed\_integration\_runtime\_name](#output\_managed\_integration\_runtime\_name) | Name of the integration runtime in the managed virtual network. `null` unless `managed_integration_runtime` is set. |
| <a name="output_managed_private_endpoint_ids"></a> [managed\_private\_endpoint\_ids](#output\_managed\_private\_endpoint\_ids) | IDs of the managed private endpoints created, keyed like `var.managed_private_endpoints`. |
| <a name="output_name"></a> [name](#output\_name) | Name of the Data Factory. |
| <a name="output_private_dns_records"></a> [private\_dns\_records](#output\_private\_dns\_records) | DNS records Azure registered for this module's private endpoints (one<br/>per record), e.g. to check name resolution or document the network:<br/><br/>- `resource` / `subresource` - the resource and sub-resource (the<br/>  `private_endpoints` key) the record points at.<br/>- `zone_name` - private DNS zone holding the record (e.g.<br/>  `privatelink.blob.core.windows.net`).<br/>- `name` / `fqdn` - host name within the zone and its fully qualified<br/>  name.<br/>- `type` - record type (`A`).<br/>- `ip_addresses` - the endpoint's private IP address(es).<br/>- `ttl` - time to live, in seconds.<br/><br/>Includes records registered by an Azure Policy when<br/>`private_endpoints_manage_dns_zone_group` is `false`, once the policy<br/>has run and state is refreshed. Known after apply. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | Private endpoints created, keyed by sub-resource, with their `id` and `private_ip_address`. |
<!-- END_TF_DOCS -->