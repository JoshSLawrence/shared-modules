<!-- BEGIN_TF_DOCS -->
# Synapse Workspace

Azure Synapse Analytics workspace that creates its default ADLS Gen2 storage (via the storage-account module) or uses an existing filesystem, with private endpoints, firewall rules, and a managed virtual network.

## Usage

Reference this module from a root (or child) module, pinned to a released, module-scoped tag:

```hcl
module "synapse-workspace" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/synapse-workspace?ref=synapse-workspace/vX.Y.Z"

  # module inputs...
}
```

Or over SSH:

```hcl
module "synapse-workspace" {
  source = "git::ssh://git@github.com/JoshSLawrence/shared-modules.git//modules/synapse-workspace?ref=synapse-workspace/vX.Y.Z"

  # module inputs...
}
```

Always pin `ref` to a released tag — see [Versioning and Releases](../../CONTRIBUTING.md#versioning-and-releases) — rather than a branch. Released versions of this module are listed on the repo's [Releases](https://github.com/JoshSLawrence/shared-modules/releases) page as `synapse-workspace/vX.Y.Z`.

See [CHANGELOG.md](./CHANGELOG.md) for version history and upgrade notes.

## Default storage

Every workspace needs an ADLS Gen2 file system as its default storage. Set
exactly one of:

- `storage_account` - create it with a released version of this repo's
  [storage-account](../storage-account) module (public or private to match
  the workspace unless overridden, with its own `private_endpoints`), or
- `existing_storage` - use an existing file system, e.g. one from a
  storage-account module call:

  ```hcl
  existing_storage = {
    data_lake_filesystem_id = module.data_lake.containers["synapse"].data_lake_filesystem_id
    storage_account_id      = module.data_lake.id
  }
  ```

Either way, the workspace's managed identity gets
`Storage Blob Data Contributor` on the account. `storage_managed_private_endpoints`
adds managed private endpoints to it, so Spark and serverless SQL can reach a
private account from the managed virtual network.

## Defaults

The workspace is private and locked down unless you opt out:

- **Private** (`public_network_access_enabled = false`): no public
  endpoints; reach the workspace through `private_endpoints` (`Dev`, `Sql`,
  `SqlOnDemand`). Set `public_network_access_enabled = true` to open it to
  every network instead: Synapse's firewall blocks everything even with
  public access on, so the module adds an `AllowAll` rule
  (0.0.0.0-255.255.255.255). There's no IP-restricted middle state.
  Public workspaces can also set `azure_services_access_enabled = true` to
  add the `AllowAllWindowsAzureIps` rule (0.0.0.0-0.0.0.0). That is the
  "Allow Azure services and resources to access this workspace" setting,
  distinct from the `AllowAll` IP rule: it also covers Azure services
  reaching the workspace from Azure networks via service endpoints, and
  features and portal checks that look for it.
- **Managed virtual network always on** (it can only be chosen at
  creation), with optional data exfiltration
  protection and `managed_private_endpoints`.
- **Entra ID authentication only** for SQL. Synapse still requires a SQL
  administrator password: pass one in `sql_administrator_password` or let
  the module generate one. It's exposed as a sensitive output and can be
  stored in Key Vault with `sql_administrator_password_secret`.
- Optional `entra_admin`, `spark_pools`, `github_repo`, `access`,
  `synapse_role_assignments`, `role_assignments`, `diagnostic_settings`
  (with per-category control for the workspace and its storage account)
  and `lock` (an Azure management lock, also applied to a storage account
  this module creates).

## Data plane access

Most of the workspace is managed through Azure Resource Manager, but
`synapse_role_assignments` (and `access` entries with a `synapse_role` or
`credential_user`), `managed_private_endpoints` and
`storage_managed_private_endpoints` use the workspace's dev endpoint, and
`sql_administrator_password_secret` the Key Vault data plane. For those,
the machine running OpenTofu needs network access (a public workspace, or
line of sight to the `Dev` private endpoint) and, for the vault, a role like
`Key Vault Secrets Officer`.

Managed private endpoints are created pending approval; approve them on the
target resource's private endpoint connections.

## Access

`access` grants the usual role combinations per principal, keyed by a static
name, without spelling out each role assignment:

```hcl
access = {
  admins = {
    principal_id   = "<group object ID>"
    principal_type = "Group"
    synapse_role   = "Synapse Administrator"
    workspace_role = "Reader"
  }
  developers = {
    principal_id    = "<group object ID>"
    principal_type  = "Group"
    synapse_role    = "Synapse Contributor"
    credential_user = true
  }
}
```

Each entry becomes up to three role assignments: the Synapse role, keyed
`<key>`; `Synapse Credential User`, keyed `<key>_credential_user`; and the
Azure role on the workspace, keyed `<key>`. They join
`synapse_role_assignments` and `role_assignments`, whose keys must not
collide with them, so moving a principal from those maps to `access` under
the same key keeps its role assignments, and changing an entry's
`synapse_role` replaces only that one assignment. Use the maps directly for
anything else (e.g. two Synapse roles for one principal, or role assignment
conditions), and `storage_account.role_assignments` for roles on the
default storage.

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

A storage account this module creates follows the workspace's setting unless
`storage_account.private_endpoints_manage_dns_zone_group` overrides it.

## Managed private endpoints and Git

Managed private endpoints point at a specific environment's resources (dev's
storage account isn't prod's), so let this module own them in every
environment and keep them out of Git deployments: leave the
`deployManagedPrivateEndpoint` option of the
[Synapse workspace deployment](https://github.com/Azure/synapse-workspace-deployment)
action off. Linked services stay in Git; they name their targets (e.g. a
`dfs` URL), and Synapse routes them through the matching approved managed
private endpoint.

The module never sets a managed private endpoint's
`fully_qualified_domain_names` and ignores whatever Azure reports for it
(it fills them in for some targets, e.g. Key Vault), so the endpoints aren't
replaced over it.

## Git integration

Synapse records the collaboration branch's latest commit in the workspace's
Git settings as people work in Synapse Studio in Git mode. The module
ignores that value (`github_repo.last_commit_id` only seeds it), so a
moving branch doesn't plan an update.

## Updating an Entra ID-only workspace

azurerm (checked at v5.8.0 and v5.9.0) can't update an Entra ID-only
workspace in place: every update sends the SQL administrator password, and
Synapse rejects its presence in the update, even an unchanged one, while
`azuread_authentication_only = true`, with `AadOnlyAuthenticationIsEnabled`.
See
[hashicorp/terraform-provider-azurerm#25755](https://github.com/hashicorp/terraform-provider-azurerm/issues/25755).

That affects changes to the workspace resource itself: `tags`,
the Git settings (`github_repo`, including removing it),
`public_network_access_enabled`, `sql_administrator_password` and
the customer-managed key. It doesn't affect separate resources such as Spark
pools, firewall rules, managed private endpoints and role assignments, which
update normally, or the Entra ID-only setting (`azuread_authentication_only`)
itself.

To make one of those changes, apply twice:

1. Set `azuread_authentication_only = false` and apply. The plan must show
   nothing but that change: any other pending difference (e.g. tag drift from
   the portal) fails this apply the same way. Once it succeeds, SQL
   authentication is allowed.
2. Make the change, set `azuread_authentication_only = true` again, and
   apply. The provider updates the workspace first, while SQL
   authentication is still allowed, then turns Entra ID-only back on. This
   apply re-sends the configured SQL administrator password, so it resets
   one that was rotated outside OpenTofu.

Keep the time between the two applies short: SQL authentication with the
administrator password works until the second apply finishes.

## Example

```hcl
module "synapse_workspace" {
  source = "git::https://github.com/JoshSLawrence/shared-modules.git//modules/synapse-workspace?ref=synapse-workspace/vX.Y.Z"

  name                = "synw-myapp-prod"
  resource_group_name = "rg-myapp-prod"
  location            = "eastus"

  storage_account = {
    name = "stsynwmyappprod"
  }

  private_endpoints = {
    Dev = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.synapse_dev.id]
    }
    Sql = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.synapse_sql.id]
    }
    SqlOnDemand = {
      subnet_id            = data.azurerm_subnet.private_endpoints.id
      private_dns_zone_ids = [data.azurerm_private_dns_zone.synapse_sql.id]
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
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.9.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 5.7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | >= 3.9.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_storage_account"></a> [storage\_account](#module\_storage\_account) | git::https://github.com/JoshSLawrence/shared-modules.git//modules/storage-account | storage-account/v0.1.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_key_vault_secret.sql_administrator_password](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_secret) | resource |
| [azurerm_management_lock.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_lock) | resource |
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_private_endpoint.this_unmanaged_dns_zone_group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_role_assignment.storage_blob_data_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_synapse_firewall_rule.allow_all](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_firewall_rule) | resource |
| [azurerm_synapse_firewall_rule.azure_services](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_firewall_rule) | resource |
| [azurerm_synapse_managed_private_endpoint.storage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_managed_private_endpoint) | resource |
| [azurerm_synapse_managed_private_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_managed_private_endpoint) | resource |
| [azurerm_synapse_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_role_assignment) | resource |
| [azurerm_synapse_spark_pool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_spark_pool) | resource |
| [azurerm_synapse_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_workspace) | resource |
| [azurerm_synapse_workspace_aad_admin.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/synapse_workspace_aad_admin) | resource |
| [random_password.sql_administrator](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_access"></a> [access](#input\_access) | Access to grant, per principal, keyed by an arbitrary static name: a<br/>shorthand for the usual combinations of Synapse RBAC roles and an Azure<br/>RBAC role on the workspace, which the module adds to<br/>`synapse_role_assignments` and `role_assignments`. For example, a group<br/>that develops and debugs Synapse artifacts, and an administrators group:<pre>hcl<br/>access = {<br/>  developers = {<br/>    principal_id    = "<group object ID>"<br/>    principal_type  = "Group"<br/>    synapse_role    = "Synapse Contributor"<br/>    credential_user = true<br/>  }<br/>  admins = {<br/>    principal_id   = "<group object ID>"<br/>    principal_type = "Group"<br/>    synapse_role   = "Synapse Administrator"<br/>    workspace_role = "Reader"<br/>  }<br/>}</pre>- `principal_type` - `User`, `Group` or `ServicePrincipal`, as in the<br/>  role assignment maps.<br/>- `synapse_role` - a Synapse RBAC role, e.g. `Synapse Administrator`,<br/>  `Synapse Contributor` or `Synapse Artifact User`. Its Synapse role<br/>  assignment is keyed `<key>`, so changing the role replaces that one<br/>  assignment.<br/>- `credential_user` - also grant `Synapse Credential User`, keyed<br/>  `<key>_credential_user`. Synapse Contributor alone can't run pipelines<br/>  or debug linked services that use the workspace identity.<br/>- `workspace_role` - an Azure RBAC role on the workspace (a built-in role<br/>  name or a role definition ID starting with `/`), keyed `<key>`.<br/>  `Reader` makes Synapse Studio list the workspace for a principal that<br/>  can't already read it through a wider scope.<br/><br/>Each entry must grant at least one role. The derived keys share the<br/>explicit maps' keys, so they must not collide with them. Synapse roles<br/>are granted through the data plane, as for `synapse_role_assignments`. | <pre>map(object({<br/>    principal_id    = string<br/>    principal_type  = optional(string)<br/>    synapse_role    = optional(string)<br/>    credential_user = optional(bool, false)<br/>    workspace_role  = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_azure_services_access_enabled"></a> [azure\_services\_access\_enabled](#input\_azure\_services\_access\_enabled) | Add the `AllowAllWindowsAzureIps` firewall rule (0.0.0.0-0.0.0.0), which<br/>lets Azure services reach the workspace's public endpoints. Only valid<br/>with `public_network_access_enabled = true`; a private workspace is<br/>reached through `private_endpoints` instead. Default `false`.<br/><br/>This is separate from `public_network_access_enabled`'s `AllowAll` rule<br/>(an IP range): it is the portal's "Allow Azure services and resources to<br/>access this workspace" setting, which also covers traffic the IP rule<br/>doesn't, such as Azure services reaching the workspace from Azure<br/>networks via service endpoints, and features and portal checks that look<br/>for this rule. | `bool` | `false` | no |
| <a name="input_azuread_authentication_only"></a> [azuread\_authentication\_only](#input\_azuread\_authentication\_only) | Allow only Entra ID authentication to the workspace's SQL endpoints<br/>(`true`, the default), disabling the SQL administrator login. Some<br/>deployment tooling still needs SQL auth; set `false` if so. | `bool` | `true` | no |
| <a name="input_data_exfiltration_protection_enabled"></a> [data\_exfiltration\_protection\_enabled](#input\_data\_exfiltration\_protection\_enabled) | Only allow outbound connections from the managed virtual network through<br/>approved managed private endpoints (to tenants in<br/>`linking_allowed_for_aad_tenant_ids`). Can't be changed after creation. | `bool` | `false` | no |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | Send the workspace's logs (and, for a storage account this module<br/>creates, its storage logs and metrics) to a Log Analytics workspace.<br/>`null` (the default) disables diagnostics.<br/><br/>- `log_categories`: workspace log categories to enable. `null` (the<br/>  default) enables the `allLogs` category group; `[]` enables no logs.<br/>- `metric_categories`: workspace metric categories to enable. `null` or<br/>  `[]` (the default) enables none; the workspace sets no metrics unless<br/>  asked.<br/>- `storage_log_categories`, `storage_metric_categories`: the same for the<br/>  storage account this module creates (passed as the storage-account<br/>  module's `log_categories` and `metric_categories`). `null` (the<br/>  default) uses that module's defaults; `[]` enables none. Ignored with<br/>  `existing_storage`.<br/><br/>The workspace's setting must end up with at least one log or metric<br/>category enabled. | <pre>object({<br/>    log_analytics_workspace_id = string<br/>    name                       = optional(string, "diag-log-analytics")<br/>    log_categories             = optional(list(string))<br/>    metric_categories          = optional(list(string))<br/>    storage_log_categories     = optional(list(string))<br/>    storage_metric_categories  = optional(list(string))<br/>  })</pre> | `null` | no |
| <a name="input_entra_admin"></a> [entra\_admin](#input\_entra\_admin) | Entra ID administrator for the workspace's SQL endpoints (a user or,<br/>preferably, a group). `login` is the user principal name or group<br/>display name. `tenant_id` defaults to the tenant of the identity running<br/>OpenTofu. `null` (the default) sets no Entra administrator.<br/><br/>This is the SQL administrator only. Grant Synapse RBAC roles (e.g.<br/>`Synapse Administrator`) with `synapse_role_assignments`. | <pre>object({<br/>    login     = string<br/>    object_id = string<br/>    tenant_id = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_existing_storage"></a> [existing\_storage](#input\_existing\_storage) | Use an existing ADLS Gen2 file system as the workspace's default storage<br/>instead of creating one. Set this or `storage_account`, not both.<br/><br/>- `data_lake_filesystem_id` - `https://<account>.dfs.core.windows.net/<file system>`<br/>  (e.g. the `data_lake_filesystem_id` of a storage-account module<br/>  container, or `azurerm_storage_data_lake_gen2_filesystem.id`).<br/>- `storage_account_id` - resource ID of the account holding it.<br/>- `assign_blob_data_contributor` - grant the workspace's managed<br/>  identity `Storage Blob Data Contributor` on the account (default<br/>  `true`). Synapse needs it; set `false` only if it's granted elsewhere. | <pre>object({<br/>    data_lake_filesystem_id      = string<br/>    storage_account_id           = string<br/>    assign_blob_data_contributor = optional(bool, true)<br/>  })</pre> | `null` | no |
| <a name="input_github_repo"></a> [github\_repo](#input\_github\_repo) | Connect Synapse Studio to a GitHub repository for source control.<br/>`branch_name` is the collaboration branch and `root_folder` the folder<br/>holding Synapse artifacts (e.g. `/synapse`). `git_url` is only needed for<br/>GitHub Enterprise Server. `last_commit_id` only seeds the commit Synapse<br/>records when Git integration is first configured: Synapse updates it as<br/>people work in Synapse Studio, and the module ignores later changes to<br/>it. A repository admin still has to approve the Synapse app's access.<br/>`null` (the default) leaves Git integration off. | <pre>object({<br/>    account_name    = string<br/>    repository_name = string<br/>    branch_name     = string<br/>    root_folder     = optional(string, "/")<br/>    git_url         = optional(string)<br/>    last_commit_id  = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_identity_ids"></a> [identity\_ids](#input\_identity\_ids) | User-assigned managed identities to attach in addition to the always-on system-assigned identity. | `list(string)` | `[]` | no |
| <a name="input_linking_allowed_for_aad_tenant_ids"></a> [linking\_allowed\_for\_aad\_tenant\_ids](#input\_linking\_allowed\_for\_aad\_tenant\_ids) | Entra ID tenants that managed private endpoints may connect to while data exfiltration protection is enabled. Requires `data_exfiltration_protection_enabled`. | `list(string)` | `[]` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region to create the workspace and its storage account in (e.g. `eastus`). | `string` | n/a | yes |
| <a name="input_lock"></a> [lock](#input\_lock) | Management lock on the workspace, and on the storage account this module<br/>creates, protecting them from accidental deletion (`CanNotDelete`) or any<br/>change (`ReadOnly`). `name` defaults to `lock-<resource name>`. `null`<br/>(the default) creates no lock.<br/><br/>A `CanNotDelete` lock also blocks deleting role assignments and diagnostic<br/>settings under its scope, so revoking a grant or removing a diagnostic<br/>setting needs the lock lifted first. | <pre>object({<br/>    kind  = string<br/>    name  = optional(string)<br/>    notes = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_managed_private_endpoints"></a> [managed\_private\_endpoints](#input\_managed\_private\_endpoints) | Managed private endpoints from the workspace's managed virtual network,<br/>keyed by an arbitrary static name (the default endpoint name), e.g. so<br/>Spark can reach a private storage account:<pre>hcl<br/>managed_private_endpoints = {<br/>  default-storage-dfs = {<br/>    target_resource_id = module.storage_account.id<br/>    subresource_name   = "dfs"<br/>  }<br/>}</pre>Each endpoint is created pending approval: approve it on the target<br/>resource's private endpoint connections before it carries traffic. | <pre>map(object({<br/>    target_resource_id = string<br/>    subresource_name   = string<br/>    name               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_managed_resource_group_name"></a> [managed\_resource\_group\_name](#input\_managed\_resource\_group\_name) | Name of the resource group Azure creates to hold the workspace's managed resources. `null` lets Azure generate one. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the Synapse workspace (e.g. `synw-myapp-prod`). Must be globally unique. | `string` | n/a | yes |
| <a name="input_private_endpoints"></a> [private\_endpoints](#input\_private\_endpoints) | Private endpoints to create, keyed by target sub-resource:<br/><br/>- `Dev` - Synapse Studio and the dev (REST/data plane) endpoint<br/>  (`privatelink.dev.azuresynapse.net`).<br/>- `Sql` - dedicated SQL pools (`privatelink.sql.azuresynapse.net`).<br/>- `SqlOnDemand` - serverless SQL (`privatelink.sql.azuresynapse.net`).<br/><br/>Per endpoint:<br/><br/>- `subnet_id` - subnet to place the endpoint's network interface in.<br/>- `private_dns_zone_ids` - private DNS zones to register the<br/>  endpoint in. Leave empty when DNS is managed elsewhere: set<br/>  `private_endpoints_manage_dns_zone_group = false` if an Azure<br/>  Policy registers the endpoints.<br/>- `private_ip_address` - static IP from the subnet. `null` lets Azure<br/>  assign one.<br/>- `name` / `network_interface_name` - default to<br/>  `pep-<workspace name>-<sub-resource>` and `nic-pep-<workspace name>-<sub-resource>`<br/>  (sub-resource lowercased).<br/>- `resource_group_name` / `location` - default to the workspace's.<br/><br/>Loading Synapse Studio itself privately also needs a Synapse private link<br/>hub (sub-resource `Web`), which isn't workspace-specific and isn't<br/>created by this module. | <pre>map(object({<br/>    subnet_id              = string<br/>    private_dns_zone_ids   = optional(list(string), [])<br/>    private_ip_address     = optional(string)<br/>    name                   = optional(string)<br/>    network_interface_name = optional(string)<br/>    resource_group_name    = optional(string)<br/>    location               = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_private_endpoints_manage_dns_zone_group"></a> [private\_endpoints\_manage\_dns\_zone\_group](#input\_private\_endpoints\_manage\_dns\_zone\_group) | Who registers `private_endpoints` in private DNS:<br/><br/>- `true` (the default) - this module: each endpoint gets a private DNS<br/>  zone group for its `private_dns_zone_ids`, and Azure writes the A<br/>  records.<br/>- `false` - something else, typically an Azure Policy that attaches a<br/>  zone group pointing at centrally managed zones after the endpoint is<br/>  created (as in Azure landing zones). The module leaves zone groups<br/>  alone so applies don't remove them, and `private_dns_zone_ids` must be<br/>  empty.<br/><br/>Changing this recreates the endpoints. | `bool` | `true` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Network access to the workspace:<br/><br/>- `false` (the default) - private: the public endpoints are disabled and<br/>  the workspace (Studio, dev and SQL endpoints) is reachable only through<br/>  `private_endpoints`.<br/>- `true` - public: the endpoints are enabled and an `AllowAll` firewall<br/>  rule (0.0.0.0-255.255.255.255) admits every network (still subject to<br/>  Entra ID or SQL authentication). Synapse's firewall otherwise blocks<br/>  everything even with public access on. | `bool` | `false` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to create the workspace (and, unless overridden, its storage account and private endpoints) in. | `string` | n/a | yes |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | Azure RBAC role assignments scoped to the workspace, keyed by an<br/>arbitrary static name. `role_definition_id_or_name` takes a built-in role<br/>name or a full role definition resource ID (starting with `/`). | <pre>map(object({<br/>    role_definition_id_or_name       = string<br/>    principal_id                     = string<br/>    principal_type                   = optional(string)<br/>    description                      = optional(string)<br/>    condition                        = optional(string)<br/>    condition_version                = optional(string)<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_spark_pools"></a> [spark\_pools](#input\_spark\_pools) | Apache Spark pools, keyed by an arbitrary static name. `name` defaults to<br/>the key; keep it free of environment names, since notebooks reference<br/>pools by name and are promoted between environments unchanged.<br/><br/>Pools auto-scale between `auto_scale_min_node_count` and<br/>`auto_scale_max_node_count` nodes (default 3-10) unless `node_count`<br/>sets a fixed size, and pause after `auto_pause_delay_in_minutes` idle<br/>(default 15; `0` never pauses). | <pre>map(object({<br/>    name                                = optional(string)<br/>    spark_version                       = optional(string, "3.5")<br/>    node_size_family                    = optional(string, "MemoryOptimized")<br/>    node_size                           = optional(string, "Small")<br/>    node_count                          = optional(number)<br/>    auto_scale_min_node_count           = optional(number, 3)<br/>    auto_scale_max_node_count           = optional(number, 10)<br/>    auto_pause_delay_in_minutes         = optional(number, 15)<br/>    cache_size                          = optional(number)<br/>    dynamic_executor_allocation_enabled = optional(bool, false)<br/>    session_level_packages_enabled      = optional(bool, false)<br/>    spark_events_folder                 = optional(string, "/events")<br/>    spark_log_folder                    = optional(string, "/logs")<br/>  }))</pre> | `{}` | no |
| <a name="input_sql_administrator_login"></a> [sql\_administrator\_login](#input\_sql\_administrator\_login) | SQL administrator login name. Synapse requires one even when<br/>`azuread_authentication_only` is `true`. Can't be changed after<br/>creation. | `string` | `"sqladminuser"` | no |
| <a name="input_sql_administrator_password"></a> [sql\_administrator\_password](#input\_sql\_administrator\_password) | SQL administrator password to use, e.g. one managed outside OpenTofu.<br/>8-128 characters with at least three of: lowercase, uppercase, digits and<br/>symbols. `null` (the default) generates a 32-character password. Synapse<br/>requires one even when `azuread_authentication_only` is `true`. | `string` | `null` | no |
| <a name="input_sql_administrator_password_secret"></a> [sql\_administrator\_password\_secret](#input\_sql\_administrator\_password\_secret) | Store the SQL administrator password (generated or supplied) as a Key<br/>Vault secret<br/>(e.g. in a vault from the key-vault module). `name` defaults to<br/>`<workspace name>-sql-admin-password`. `expiration_date` is an optional<br/>RFC 3339 UTC timestamp (e.g. `2027-01-01T00:00:00Z`). `null` (the<br/>default) stores it nowhere but state and the sensitive<br/>`sql_administrator_password` output.<br/><br/>Writing the secret uses the Key Vault data plane: the identity running<br/>OpenTofu needs a role like `Key Vault Secrets Officer` on the vault, and<br/>network access to it (e.g. through its private endpoint). | <pre>object({<br/>    key_vault_id    = string<br/>    name            = optional(string)<br/>    expiration_date = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_storage_account"></a> [storage\_account](#input\_storage\_account) | Create the workspace's default ADLS Gen2 storage account with the<br/>storage-account module (in the same resource group and region, with the<br/>same tags, `lock` and `diagnostic_settings`). Set this or<br/>`existing_storage`, not both.<br/><br/>- `name` - storage account name (e.g. `stsynwmyappprod`).<br/>- `filesystem_name` - file system (container) for the workspace; default<br/>  `synapse`.<br/>- `public_network_access_enabled` - defaults to the workspace's<br/>  `public_network_access_enabled`, so a public workspace gets public<br/>  storage it can use straight away and a private workspace gets private<br/>  storage.<br/>- `private_endpoints_manage_dns_zone_group` - defaults to the<br/>  workspace's `private_endpoints_manage_dns_zone_group`.<br/>- `private_endpoints`, `account_replication_type`,<br/>  `infrastructure_encryption_enabled` - passed to the storage-account<br/>  module; see its README.<br/>- `role_assignments` - extra Azure RBAC role assignments on the storage<br/>  account, keyed by an arbitrary static name; the same shape as the<br/>  storage-account module's `role_assignments`. The workspace identity's<br/>  `Storage Blob Data Contributor` is always granted separately.<br/><br/>Blob versioning and soft delete are always disabled on this account:<br/>Synapse doesn't support them on its default storage. | <pre>object({<br/>    name                                    = string<br/>    filesystem_name                         = optional(string, "synapse")<br/>    account_replication_type                = optional(string, "RAGRS")<br/>    infrastructure_encryption_enabled       = optional(bool, true)<br/>    public_network_access_enabled           = optional(bool)<br/>    private_endpoints_manage_dns_zone_group = optional(bool)<br/>    private_endpoints = optional(map(object({<br/>      subnet_id              = string<br/>      private_dns_zone_ids   = optional(list(string), [])<br/>      private_ip_address     = optional(string)<br/>      name                   = optional(string)<br/>      network_interface_name = optional(string)<br/>      resource_group_name    = optional(string)<br/>      location               = optional(string)<br/>    })), {})<br/>    role_assignments = optional(map(object({<br/>      role_definition_id_or_name       = string<br/>      principal_id                     = string<br/>      principal_type                   = optional(string)<br/>      description                      = optional(string)<br/>      condition                        = optional(string)<br/>      condition_version                = optional(string)<br/>      skip_service_principal_aad_check = optional(bool, false)<br/>    })), {})<br/>  })</pre> | `null` | no |
| <a name="input_storage_managed_private_endpoints"></a> [storage\_managed\_private\_endpoints](#input\_storage\_managed\_private\_endpoints) | Sub-resources of the default storage account (`dfs` and/or `blob`) to<br/>create managed private endpoints to, so Spark and serverless SQL can<br/>reach it from the managed virtual network when its public access is<br/>disabled. Named `<storage account name>-<sub-resource>`.<br/><br/>Like any managed private endpoint, each is created pending approval and<br/>through the workspace's dev endpoint (see `managed_private_endpoints`). | `list(string)` | `[]` | no |
| <a name="input_synapse_role_assignments"></a> [synapse\_role\_assignments](#input\_synapse\_role\_assignments) | Synapse RBAC role assignments (workspace-scoped roles inside Synapse,<br/>separate from Azure RBAC), keyed by an arbitrary static name, e.g.:<pre>hcl<br/>synapse_role_assignments = {<br/>  admins = {<br/>    role_name      = "Synapse Administrator"<br/>    principal_id   = "<group object ID>"<br/>    principal_type = "Group"<br/>  }<br/>}</pre>These use the workspace's dev (data plane) endpoint: the identity running<br/>OpenTofu must be a Synapse Administrator (the workspace creator is one<br/>automatically) and able to reach the workspace (public access, or the<br/>`Dev` private endpoint). | <pre>map(object({<br/>    role_name      = string<br/>    principal_id   = string<br/>    principal_type = optional(string)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to every resource this module creates, including the storage account. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_connectivity_endpoints"></a> [connectivity\_endpoints](#output\_connectivity\_endpoints) | The workspace's endpoints (`dev`, `sql`, `sqlOnDemand`, `web`). |
| <a name="output_data_lake_filesystem_id"></a> [data\_lake\_filesystem\_id](#output\_data\_lake\_filesystem\_id) | Data Lake file system the workspace uses as its default storage. |
| <a name="output_id"></a> [id](#output\_id) | Resource ID of the Synapse workspace. |
| <a name="output_identity_principal_id"></a> [identity\_principal\_id](#output\_identity\_principal\_id) | Object ID of the workspace's system-assigned managed identity, e.g. to grant it access to other resources. |
| <a name="output_managed_private_endpoint_ids"></a> [managed\_private\_endpoint\_ids](#output\_managed\_private\_endpoint\_ids) | IDs of the managed private endpoints created, keyed like `var.managed_private_endpoints`. |
| <a name="output_managed_resource_group_name"></a> [managed\_resource\_group\_name](#output\_managed\_resource\_group\_name) | Name of the resource group holding the workspace's managed resources. |
| <a name="output_name"></a> [name](#output\_name) | Name of the Synapse workspace. |
| <a name="output_private_dns_records"></a> [private\_dns\_records](#output\_private\_dns\_records) | DNS records Azure registered for this module's private endpoints,<br/>including those of the default storage account it creates (one per<br/>record), e.g. to check name resolution or document the network:<br/><br/>- `resource` / `subresource` - the resource and sub-resource (the<br/>  `private_endpoints` key) the record points at.<br/>- `zone_name` - private DNS zone holding the record (e.g.<br/>  `privatelink.blob.core.windows.net`).<br/>- `name` / `fqdn` - host name within the zone and its fully qualified<br/>  name.<br/>- `type` - record type (`A`).<br/>- `ip_addresses` - the endpoint's private IP address(es).<br/>- `ttl` - time to live, in seconds.<br/><br/>Includes records registered by an Azure Policy when<br/>`private_endpoints_manage_dns_zone_group` is `false`, once the policy<br/>has run and state is refreshed. Known after apply. |
| <a name="output_private_endpoints"></a> [private\_endpoints](#output\_private\_endpoints) | Private endpoints created, keyed by sub-resource, with their `id` and `private_ip_address`. |
| <a name="output_spark_pool_ids"></a> [spark\_pool\_ids](#output\_spark\_pool\_ids) | IDs of the Spark pools created, keyed like `var.spark_pools`. |
| <a name="output_sql_administrator_login"></a> [sql\_administrator\_login](#output\_sql\_administrator\_login) | SQL administrator login name. |
| <a name="output_sql_administrator_password"></a> [sql\_administrator\_password](#output\_sql\_administrator\_password) | SQL administrator password (supplied or generated). |
| <a name="output_sql_administrator_password_secret_id"></a> [sql\_administrator\_password\_secret\_id](#output\_sql\_administrator\_password\_secret\_id) | Versionless ID of the Key Vault secret holding the SQL administrator password. `null` unless `sql_administrator_password_secret` is set. |
| <a name="output_storage_account_id"></a> [storage\_account\_id](#output\_storage\_account\_id) | Resource ID of the workspace's default storage account (created or existing). |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | Name of the default storage account this module created. `null` when using `existing_storage`. |
| <a name="output_storage_managed_private_endpoint_ids"></a> [storage\_managed\_private\_endpoint\_ids](#output\_storage\_managed\_private\_endpoint\_ids) | IDs of the managed private endpoints to the default storage account, keyed by sub-resource. |
| <a name="output_storage_private_endpoints"></a> [storage\_private\_endpoints](#output\_storage\_private\_endpoints) | Private endpoints of the default storage account this module created, keyed by sub-resource. Empty when using `existing_storage`. |
<!-- END_TF_DOCS -->