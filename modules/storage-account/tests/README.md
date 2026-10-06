# Tests

This directory contains OpenTofu tests for validating module logic. Tests use
mock providers to validate input constraints without creating real Azure
resources.

## Test file conventions

- Use `.tftest.hcl` extension for test files
- Add a `mock_provider` block (e.g. `mock_provider "azurerm" {}`) for each
  provider the module uses at the top of each test file
- Organize tests by variable or feature (e.g. `01_name_validation.tftest.hcl`)
- Test both valid and invalid inputs for each validation rule
- Use numeric prefixes to control execution order — OpenTofu runs test files
  alphabetically, so prefix fast mock-based tests with `01_`–`89_` and slower
  integration tests with `90_`–`99_` (e.g. `99_integration.tftest.hcl`).
  **This convention is enforced by pre-commit hooks** — the `tofu-test` hook
  only runs `01_`–`89_` tests locally; integration tests run in CI.

## Running tests

```bash
cd modules/storage-account
tofu test
```

- **`tofu test`** — runs all tests (unit + integration)
- **`mise run test storage-account`** — runs all tests
- **pre-commit** — runs unit tests only (`01_`–`89_`) for fast local feedback

## Example test structure

```hcl
mock_provider "azurerm" {}

variables {
  # Default values for all runs in this file
  name = "example-name"
  # ... other required variables
}

run "name_valid_example" {
  command = plan

  variables {
    name = "valid-name"
  }

  assert {
    condition     = azurerm_some_resource.this.name == "valid-name"
    error_message = "Name should be set correctly"
  }
}

run "name_invalid_too_short" {
  command = plan

  variables {
    name = "x"
  }

  expect_failures = [var.name]
}
```

## What to test

- **All variable validation blocks** — test valid values pass and invalid
  values fail with the expected error
- **Conditional resource creation** — e.g. when a feature flag is false,
  verify the corresponding resource is not created
- **Default values** — verify defaults work as expected

Do NOT test:
- Azure API behavior or provider implementation details
- Resource creation success (that requires real infrastructure)

See [AGENTS.md](../../../AGENTS.md#testing) for full testing guidelines.
