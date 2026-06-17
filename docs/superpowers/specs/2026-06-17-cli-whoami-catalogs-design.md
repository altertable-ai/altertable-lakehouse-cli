# Design: `altertable whoami` and `altertable catalogs`

Date: 2026-06-17

## Goal

Add three CLI commands that target the **management REST API**
(`https://app.altertable.ai/rest/v1/` by default):

```
altertable whoami                                     # authenticated principal + organization
altertable catalogs create --engine altertable --name "My Cat"
altertable catalogs list
```

For catalogs, only the `altertable` engine is supported for now. A "catalog" is an
umbrella over two backend resources — **databases** and **connections** — both nested
under an environment. Listing combines them (databases first); creation targets
`databases`.

## Background: the management API differs from the data plane

The existing commands (`query`, `validate`, `append`, `upload`, …) talk to the **data
plane** at `https://api.altertable.ai` with HTTP **Basic** auth. The new commands talk to
a different service:

- **Base URL:** `https://app.altertable.ai/rest/v1`
- **Auth:** `Authorization: Bearer <management API key>` (the `atm_` token). Basic auth is
  rejected here.
- **Environment scoping:** databases and connections are nested under an environment,
  addressed by its **slug** in the URL (e.g. `/environments/production/connections`). The
  backend resolves the slug via FriendlyId `finders`, so the slug stored by
  `altertable configure --env <slug>` is used verbatim as the path segment.

Confirmed backend contract (from `~/code/backend`, `rest/v1` controllers/routes):

- `GET /rest/v1/whoami` →
  `{ "principal": {id, type, name, email|slug}, "organization": {id, name, slug} }`.
  whoami does **not** return an environment.
- `GET /rest/v1/environments/<env>/connections` →
  `{ "connections": [ {id, name, slug, engine, read_only, description, tags, catalog,
  environment_id, created_at, updated_at}, … ] }`.
- `POST /rest/v1/environments/<env>/connections` → the created object under
  `{ "connection": {…} }`, status 201.
- `GET/POST /rest/v1/environments/<env>/databases` — **not yet implemented in the
  backend** (returns 404 today). This design assumes `databases` will mirror the
  `connections` shape: list under `{ "databases": [...] }`, create returns
  `{ "database": {…} }`.

## Configuration & precedence

New environment variables (added to `bashly.yml`), following the existing precedence model
(env vars beat stored config):

- `ALTERTABLE_MANAGEMENT_API_BASE` — management API base URL.
  Default: `https://app.altertable.ai/rest/v1`.
- `ALTERTABLE_API_KEY` — the `atm_` management API key. Overrides the stored key.
- `ALTERTABLE_ENV` — the environment slug. Overrides the stored `api_key_env`.

Resolution:

- **API key:** `ALTERTABLE_API_KEY` → stored `api-key` secret (written by
  `altertable configure --api-key … --env …`). If neither is present, error:
  `No management API key. Run 'altertable configure --api-key atm_xxx --env <name>' or set ALTERTABLE_API_KEY.`
- **Environment slug:** `ALTERTABLE_ENV` → stored `api_key_env`. Required by all `catalogs`
  commands; if empty, error:
  `No environment set. Run 'altertable configure --api-key atm_xxx --env <name>' or set ALTERTABLE_ENV.`
  (`whoami` does not need an environment.)

`jq` is **required** for `whoami` and `catalogs` (they parse and reformat JSON). If `jq` is
missing, these commands print a clear error and exit non-zero. (The data-plane commands
keep their existing optional-`jq` behavior; this requirement is scoped to the new
commands.)

## HTTP layer (refactor)

`src/lib/http.sh` currently hardcodes the data-plane base + Basic auth inside
`http_request`. Extract the transport core so a second caller can reuse it without
duplication:

- `http_send(method, url, auth_header, data, extra_headers…)` — builds `curl` options,
  honors `--debug`, captures status, echoes the body on 2xx, and on non-2xx logs the
  status + body and `exit 1`. This is the existing `http_request` body, parameterized by
  full URL and auth header.
- `http_request(method, endpoint, data, extra_headers…)` — unchanged signature; computes
  `resolve_api_base + endpoint` and `get_auth_header` (Basic), then calls `http_send`.
  Behavior is identical to today, so existing tests are unaffected.

New `src/lib/management.sh`:

- `resolve_management_api_base()` → `${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}`.
- `get_management_auth_header()` → `Authorization: Bearer <key>` per the resolution above,
  or error+exit.
- `management_env()` → environment slug per the resolution above (callers decide whether to
  require it).
- `management_request(method, endpoint, data, extra_headers…)` → computes
  `resolve_management_api_base + endpoint` and the Bearer header, then calls `http_send`.
  Strict: non-2xx (including 404) errors out, consistent with `http_request`.
- `require_jq()` → errors+exits if `jq` is not on `PATH`.

## Commands

Added to `bashly.yml`. `catalogs` is a parent command with `list` and `create`
subcommands (bashly generates `catalogs_list_command.sh`, `catalogs_create_command.sh`,
and `whoami_command.sh`). Each command keeps the shared `--debug` flag.

### `whoami` (`src/whoami_command.sh`)

`require_jq`; `management_request "GET" "/whoami" ""`; format the response as a readable
summary, e.g.:

```
User: Jane Doe <jane@example.com>
Organization: Acme (acme)
```

For a service-account principal (no email), show `Service account: <name> (<slug>)`. The
principal line adapts to `.principal.type`.

### `catalogs create` (`src/catalogs_create_command.sh`)

Flags: `--engine` (required), `--name` (required).

1. `require_jq`.
2. Reject any engine other than `altertable`:
   `Only the 'altertable' engine is supported (got '<engine>').`
3. Resolve the environment slug (required).
4. Build body with `jq -n`: `{"name": <name>, "engine": "altertable"}`.
5. `management_request "POST" "/environments/<env>/databases" "<body>"`.
6. Print a confirmation from the created object (parsed from `.database // .connection`):
   `Created catalog "My Cat" (slug: my-cat, engine: altertable, environment: production).`

### `catalogs list` (`src/catalogs_list_command.sh`)

1. `require_jq`.
2. Resolve the environment slug (required).
3. `management_request "GET" "/environments/<env>/databases" ""` — **databases first**.
4. `management_request "GET" "/environments/<env>/connections" ""`.
5. Render a single human-readable table, databases first, with a leading TYPE column:

   ```
   TYPE        NAME       SLUG      ENGINE      CATALOG
   database    My Cat     my-cat    altertable  my_cat
   connection  Prod PG    prod-pg   postgres    prod_pg
   ```

   Built by emitting tab-separated rows (`jq -r`) and aligning with `column -t -s $'\t'`.
   If both lists are empty, print `No catalogs found.`

Because the call is strict, `catalogs list` fails today while `/databases` returns 404; it
starts working once the backend ships the `databases` resource. This is intentional
(spec-faithful) per the product owner's decision.

## Testing

New offline test `tests/catalogs_test.sh` (no network, no real keychain), following
`tests/configure_test.sh`:

- A fake `curl` on `PATH` that logs method, URL, `Authorization` header, and `-d` payload,
  and returns canned per-path JSON (with the ability to return 404 for `/databases`).
- `whoami`: asserts `GET <base>/whoami` with `Authorization: Bearer <key>`, and that the
  formatted output contains the principal name and organization.
- `catalogs create`: asserts engine validation (rejects `--engine postgres`), the
  `POST <base>/environments/<env>/databases` URL, Bearer header, and the
  `{"name":…,"engine":"altertable"}` payload.
- `catalogs list`: asserts both endpoints are called with databases first, Bearer auth,
  and that databases appear before connections in the rendered table.
- Error paths: missing API key, missing environment, and missing `jq` each error out
  non-zero with the documented message.
- Env-var precedence: `ALTERTABLE_API_KEY` / `ALTERTABLE_ENV` override stored config.

Wire `./tests/catalogs_test.sh` into `.github/workflows/test.yml` alongside the configure
and integration tests. Existing `configure_test.sh` and `integration_test.sh` must still
pass unchanged (the `http_send` refactor preserves data-plane behavior).

Regenerate `bin/altertable` with `bundle exec bashly generate` and commit it (CI enforces
that `bin/altertable` is in sync with `src/`).

## Documentation

Update `README.md`: a `whoami` section and a `catalogs` section (create + list), the new
environment variables, the management-vs-data-plane distinction, and the note that
`catalogs` requires `jq` and a configured management API key + environment.

## Out of scope

- `catalogs update` / `catalogs delete`, environment management commands, service-account
  commands.
- Engines other than `altertable`.
- Implementing the backend `databases` resource (separate repo).
- Pagination of list results (backend returns full lists today).
