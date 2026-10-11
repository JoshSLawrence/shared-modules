# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.2.0] - 2026-10-11

### Added

- `databases[*].short_term_retention_days`: point-in-time restore retention (1-35 days, at most 7 on the `Basic` SKU), set through a `short_term_retention_policy` block
- `databases[*].backup_interval_in_hours`: differential backup interval (`12` or `24`); requires `short_term_retention_days`

Both default to `null` (unmanaged). Upgrading changes nothing unless the new inputs are set.

## [v0.1.0] - 2026-10-08

### Added

Initial release:

- Azure SQL logical server with Entra ID authentication only (no SQL logins), TLS 1.2 minimum and public network access disabled by default
- Databases (`databases`) with configurable SKU, size, backup storage redundancy, collation and zone redundancy, and serverless auto-pause delay and minimum capacity
- Private endpoints with optional static IPs and private DNS zone groups
- `private_endpoints_manage_dns_zone_group` to leave private DNS registration to Azure Policy instead of passing `private_dns_zone_ids`
- `private_dns_records` output listing the zone, host name, record type and IP of every DNS record registered for the private endpoints
- Optional `diagnostic_settings`: logs and metrics for every database to Log Analytics
- Opt-in server auditing (`auditing_enabled`) to Log Analytics, through a `master` database diagnostic setting and the extended auditing policy
- Optional management lock and RBAC role assignments
