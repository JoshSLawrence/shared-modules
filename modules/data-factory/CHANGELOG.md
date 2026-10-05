# Changelog

All notable changes to this module will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this module adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [v0.0.1] - 2026-10-05

### Added

Initial release:

- Data Factory with an always-on managed virtual network and public network access disabled by default
- Optional integration runtime in the managed virtual network and managed private endpoints
- Private endpoints for the dataFactory and portal sub-resources
- Optional GitHub integration, user-assigned identities, RBAC role assignments, diagnostic settings and management lock
- `private_dns_records` output listing the zone, host name, record type and IP of every DNS record registered for the private endpoints
- `private_endpoints_manage_dns_zone_group` to leave private DNS registration to Azure Policy instead of passing `private_dns_zone_ids`
