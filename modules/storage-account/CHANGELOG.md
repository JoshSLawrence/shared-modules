# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.1.0] - 2026-10-08

### Added

- `diagnostic_settings.log_categories` and `diagnostic_settings.metric_categories` to choose the blob service log categories and the metric categories sent to Log Analytics. `null` (the default) keeps the previous behavior (`StorageRead`, `StorageWrite`, `StorageDelete` and `Transaction`); `[]` enables none
- Validation rejecting `diagnostic_settings` that would enable no log or metric category at all

### Changed

- The account-level diagnostic setting, which only carries metrics, is no longer created when `metric_categories` is `[]`

## [v0.0.1] - 2026-10-05

### Added

Initial release:

- Storage account (optionally ADLS Gen2) with Entra ID-only auth, TLS 1.2 and infrastructure encryption
- Public network access disabled by default (private endpoints only), or open to every network when enabled
- Containers / Data Lake file systems created through Azure Resource Manager, with each file system's Data Lake ID as an output
- Private endpoints for any storage sub-resource, with optional static IPs and private DNS zone groups
- Blob soft delete, versioning and change feed settings
- Optional diagnostic settings, management lock and RBAC role assignments
- `private_dns_records` output listing the zone, host name, record type and IP of every DNS record registered for the private endpoints
- `private_endpoints_manage_dns_zone_group` to leave private DNS registration to Azure Policy instead of passing `private_dns_zone_ids`
