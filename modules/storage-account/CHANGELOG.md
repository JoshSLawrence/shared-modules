# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
