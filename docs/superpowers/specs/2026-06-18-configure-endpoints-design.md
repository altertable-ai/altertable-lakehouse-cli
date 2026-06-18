# Design: endpoint configuration on `altertable configure`

Date: 2026-06-18

## Goal

Let `altertable configure` store the **data-plane** and **control-plane** base URLs, so a
user can point the CLI at a non-production deployment (staging, localhost, self-hosted)
once instead of exporting environment variables on every call.

```bash
altertable configure --api-key atm_xxx --env production \
  --control-plane-url http://localhost:13000/rest/v1
altertable configure --user u --password p \
  --data-plane-url http://localhost:15000
```

## Background

Two base URLs drive the CLI today, each resolved from an environment variable with a
built-in default:

- **Data plane** (`api.altertable.ai`, Basic auth): `resolve_api_base()` in
  `src/lib/config.sh` → `${ALTERTABLE_API_BASE:-https://api.altertable.ai}`.
- **Control plane** / management API (`app.altertable.ai/rest/v1`, Bearer auth):
  `resolve_management_api_base()` in `src/lib/management.sh` →
  `${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}`.

`configure` already follows a **single-override model**: every credential-setting
invocation first calls `configure_clear_all` (wiping all stored config + credentials) and
then writes exactly one credential mechanism. This change extends that model to endpoints —
a `configure` call describes the complete desired state, endpoints included.

## Flags

Two new optional flags on the `configure` command:

- `--data-plane-url <url>` — data-plane base URL (default `https://api.altertable.ai`).
- `--control-plane-url <url>` — control-plane/management base URL (default
  `https://app.altertable.ai/rest/v1`).

## Behavior

- **Endpoints accompany a credential; never standalone.** An endpoint flag is only valid in
  a `configure` invocation that also sets a credential (`--user`/`--password`,
  `--basic-token`, or `--api-key`/`--env`). If an endpoint flag is present but no credential
  mechanism is supplied, error and exit non-zero:
  `endpoint flags must be set together with a credential.`
- **Stored as non-secret config.** Endpoints are written to the flat config file
  (`$(config_file)`, same place as `user` / `api_key_env`) under keys `api_base` and
  `management_api_base` via `config_set`. They are not secrets and never go to the keychain.
- **Override semantics / reset to default.** `configure_clear_all` gains
  `config_unset api_base` and `config_unset management_api_base`. Because every
  credential-setting `configure` calls `configure_clear_all` first, **omitting an endpoint
  resets it to the production default.** Endpoints provided in the same call are written
  after the clear.
- **Trailing-slash trimming.** A single trailing `/` is stripped from each stored endpoint
  so appended paths (e.g. `/whoami`, `/query`) don't produce `//`.
- **Interactive mode unchanged.** The interactive flow (`configure` with no flags) stays
  lakehouse-credential-only; it does not prompt for endpoints, which therefore default.

## Resolution precedence

A stored-config layer is inserted between the environment variable and the built-in
default. Precedence (highest first): **environment variable → stored config → default.**

- `resolve_api_base()` (`src/lib/config.sh`):
  `ALTERTABLE_API_BASE` → `config_get api_base` → `https://api.altertable.ai`.
- `resolve_management_api_base()` (`src/lib/management.sh`):
  `ALTERTABLE_MANAGEMENT_API_BASE` → `config_get management_api_base` →
  `https://app.altertable.ai/rest/v1`.

`resolve_management_api_base()` depends on `config_get` (defined in `config.sh`); both libs
are auto-bundled together by bashly, so the dependency resolves at runtime.

## `--show`

`configure_run_show` already prints `Data plane: $(resolve_api_base)`. Add a sibling line
`Control plane: $(resolve_management_api_base)`. Both call the resolvers, so the displayed
values reflect env-var / stored-config / default automatically — no separate "stored
endpoint" display is needed.

## `--clear`

Unchanged. `configure_run_clear` deletes the config file, so stored endpoints are removed
along with everything else.

## Testing

Extend `tests/configure_test.sh` (offline, file secret backend) with cases:

1. **Stored with a credential:** `configure --api-key atm_x --env prod
   --control-plane-url http://localhost:13000/rest/v1` writes
   `management_api_base=http://localhost:13000/rest/v1` to the config file; and
   `configure --user u --password p --data-plane-url http://localhost:15000` writes
   `api_base=http://localhost:15000`.
2. **Endpoint without a credential errors:** `configure --data-plane-url http://x` exits
   non-zero with `endpoint flags must be set together with a credential.`
3. **Omitted endpoint resets to default:** after storing a custom `api_base`, a subsequent
   `configure --user u --password p` (no endpoint flag) leaves no `api_base` in the config
   file (so `resolve_api_base` returns the default).
4. **Env var beats stored config:** with `api_base` stored, `ALTERTABLE_API_BASE=...` is the
   URL curl is called with (assert via the existing curl mock that logs the request URL —
   extend the mock to capture the URL, or add a focused check).
5. **Trailing slash trimmed:** `--control-plane-url http://localhost:13000/rest/v1/` stores
   `http://localhost:13000/rest/v1` (no trailing slash).
6. **`--show` displays both planes:** output contains a `Data plane:` line and a
   `Control plane:` line.

The existing curl mock in `tests/configure_test.sh` logs only the `Authorization` header;
extend it (or add a second mock) to also log the request URL for case 4.

## Out of scope

- Endpoint prompts in interactive mode.
- URL validation beyond trailing-slash trimming (scheme/host checks).
- Per-environment endpoint storage (endpoints are global, like today's env vars).
- New environment variables (the existing `ALTERTABLE_API_BASE` /
  `ALTERTABLE_MANAGEMENT_API_BASE` keep top precedence).
