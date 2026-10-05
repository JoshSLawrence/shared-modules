# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
