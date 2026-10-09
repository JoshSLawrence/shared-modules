# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.1.1] - 2026-10-09

### Fixed

- Managed private endpoints whose target Azure fills FQDNs in for (e.g. Key Vault `vault`) are no longer planned for replacement on every run. azurerm declares `fully_qualified_domain_names` as Optional and ForceNew but not Computed, so the module now ignores it (it never sets it).

### Changed

- Upgraded the storage-account dependency from `storage-account/v0.1.0` to `storage-account/v0.1.1`: a public default storage account no longer plans a `network_rules` change on every run. Upgrading applies a one-time in-place update to a public default storage account's network rules (no replacement).

## [v0.1.0] - 2026-10-08

### Added

- `diagnostic_settings.log_categories` and `diagnostic_settings.metric_categories` to choose the workspace's log and metric categories. `null` (the default) keeps the previous behavior (the `allLogs` category group and no metrics); `[]` enables none
- `diagnostic_settings.storage_log_categories` and `diagnostic_settings.storage_metric_categories` for the default storage account this module creates (passed to the storage-account module; `null` uses its defaults)
- Validation rejecting `diagnostic_settings` that would enable no log or metric category at all
- `azure_services_access_enabled` to add the `AllowAllWindowsAzureIps` firewall rule (0.0.0.0-0.0.0.0) so Azure services can reach the workspace. Requires `public_network_access_enabled = true`
- `storage_account.role_assignments` for extra Azure RBAC role assignments on the default storage account (same shape as the storage-account module's `role_assignments`)

### Changed

- Upgraded the storage-account dependency from `storage-account/v0.0.1` to `storage-account/v0.1.0`

## [v0.0.1] - 2026-10-05

### Added

Initial release:

- Synapse workspace whose default storage is created with the storage-account module (v0.0.1) or passed in as an existing file system, with Storage Blob Data Contributor for the workspace identity
- Public network access disabled by default (private endpoints only), or open to every network (with an `AllowAll` firewall rule) when enabled; created storage follows the workspace's setting
- Private endpoints for the Dev, Sql and SqlOnDemand sub-resources
- Managed virtual network (always on), optional data exfiltration protection and managed private endpoints, including to the default storage
- Entra ID-only SQL auth by default, a supplied or generated SQL administrator password (optionally stored in Key Vault) and an optional Entra administrator
- Optional Spark pools, GitHub integration, Synapse and Azure RBAC role assignments, diagnostic settings and management lock
- `private_dns_records` output listing the zone, host name, record type and IP of every DNS record registered for the private endpoints, including the default storage account's
- `private_endpoints_manage_dns_zone_group` to leave private DNS registration to Azure Policy instead of passing `private_dns_zone_ids` (inherited by the default storage account)
