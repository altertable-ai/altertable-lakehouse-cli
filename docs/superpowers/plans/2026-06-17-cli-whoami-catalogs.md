# whoami and catalogs Commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `altertable whoami`, `altertable catalogs create`, and `altertable catalogs list` commands targeting the management REST API.

**Architecture:** The new commands talk to the management API (`https://app.altertable.ai/rest/v1`) using `Bearer` auth, distinct from the existing data plane (Basic auth). The transport core of `http_request` is extracted into a reusable `http_send`; a new `src/lib/management.sh` adds the management base URL, Bearer auth header, environment-slug resolution, and a `management_request` wrapper. Commands parse and reformat JSON responses into human-readable output with `jq`.

**Tech Stack:** Bash, [bashly](https://bashly.dannyb.co/) 1.3.8 (generates `bin/altertable` from `src/`), `curl`, `jq`, `column`.

## Global Constraints

- This is a [bashly](https://bashly.dannyb.co/) project: **never edit `bin/altertable` by hand.** Edit files under `src/` and run `bundle exec bashly generate` to regenerate `bin/altertable`. CI fails if `bin/altertable` is out of sync.
- Everything in `src/lib/*.sh` is auto-bundled into `bin/altertable`; no manual `source` wiring is needed.
- Command logic lives in `src/<command>_command.sh` (nested: `src/catalogs_create_command.sh`, `src/catalogs_list_command.sh`); shared helpers live in `src/lib/*.sh`. Match this split.
- Bashly command bodies read arguments from the global `args` associative array (e.g. `${args[--name]}`), exactly like existing commands.
- ShellCheck runs at `severity: warning` over `bin/` and `tests/` (not `src/`). Keep generated output clean.
- Management API base default: `https://app.altertable.ai/rest/v1` (no trailing slash). Env override: `ALTERTABLE_MANAGEMENT_API_BASE`.
- Management auth header is always `Authorization: Bearer <key>`. The data plane stays Basic — do not change it.
- Environment is addressed by **slug** in the URL path; the slug is the value `configure` stores in `api_key_env` (or the `ALTERTABLE_ENV` override).
- Error messages must match the spec verbatim (see each task).
- `jq` is REQUIRED for `whoami` and `catalogs`; on absence, error and exit non-zero. Data-plane commands keep their optional-`jq` behavior — do not touch them.
- All new tests are offline (no network, no real keychain), using `ALTERTABLE_SECRET_BACKEND=file` and a fake `curl` on `PATH`.

---

### Task 1: Extract `http_send` transport core

Refactor `src/lib/http.sh` so the curl/status-handling core is reusable by both the data plane and the management API, with zero behavior change for existing commands.

**Files:**
- Modify: `src/lib/http.sh` (entire file)
- Regenerate: `bin/altertable`
- Test (existing, must still pass): `tests/integration_test.sh`, `tests/configure_test.sh`

**Interfaces:**
- Produces: `http_send(method, url, auth_header, data, extra_headers…)` — builds curl options, honors `${args[--debug]}`, writes body to a temp file, echoes body on HTTP 2xx, and on non-2xx logs status + body via `log_error` and `exit 1`.
- Produces (unchanged signature): `http_request(method, endpoint, data, extra_headers…)` — resolves `resolve_api_base + endpoint`, gets the Basic `get_auth_header`, delegates to `http_send`.

- [ ] **Step 1: Replace `src/lib/http.sh` with the refactored version**

```bash
http_send() {
  local method="$1"
  local url="$2"
  local auth_header="$3"
  local data="$4"
  local extra_headers=("${@:5}")

  local user_agent="altertable-lakehouse-cli/${version}"

  local curl_opts=(
    -s
    -X "${method}"
    -H "${auth_header}"
    -H "User-Agent: ${user_agent}"
    -w "%{http_code}"
  )

  if [[ "${args[--debug]:-}" ]]; then
    curl_opts+=(-v)
  fi

  if [[ -n "${data}" ]]; then
    if [[ "${data}" == "@"* ]]; then
      local is_binary=false
      for h in "${extra_headers[@]}"; do
        if [[ "$h" == *"Content-Type: application/octet-stream"* ]]; then
          is_binary=true
          break
        fi
      done

      if [[ "$is_binary" == "true" ]]; then
        curl_opts+=(--data-binary "${data}")
      else
        curl_opts+=(-d "${data}")
      fi
    else
      curl_opts+=(-H "Content-Type: application/json")
      curl_opts+=(-d "${data}")
    fi
  fi

  for h in "${extra_headers[@]}"; do
    curl_opts+=(-H "${h}")
  done

  log_debug "Request: ${method} ${url}"

  local response_body
  local http_code
  local response_file
  response_file=$(mktemp)

  http_code=$(curl "${curl_opts[@]}" -o "${response_file}" "${url}")
  local curl_exit_code=$?

  if [[ $curl_exit_code -ne 0 ]]; then
    log_error "Request failed (curl error: ${curl_exit_code})."
    rm -f "${response_file}"
    exit 1
  fi

  response_body=$(cat "${response_file}")
  rm -f "${response_file}"

  if [[ "${http_code}" -ge 200 && "${http_code}" -lt 300 ]]; then
    echo "${response_body}"
  else
    log_error "HTTP Request failed with status ${http_code}"
    if [[ -n "${response_body}" ]]; then
      log_error "Response: ${response_body}"
    fi
    exit 1
  fi
}

http_request() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local extra_headers=("${@:4}")

  local url; url="$(resolve_api_base)${endpoint}"
  local auth_header
  auth_header=$(get_auth_header)

  http_send "${method}" "${url}" "${auth_header}" "${data}" "${extra_headers[@]}"
}
```

- [ ] **Step 2: Regenerate the CLI**

Run: `bundle exec bashly generate`
Expected: regenerates `bin/altertable`; prints a list of generated files, no errors.

- [ ] **Step 3: Run the existing test suites to verify no behavior change**

Run: `./tests/configure_test.sh && ./tests/integration_test.sh`
Expected: both suites pass (the integration suite needs the mock server / `ALTERTABLE_API_BASE` per the repo; if the mock server is unavailable locally, at minimum `./tests/configure_test.sh` must pass and the curl-spy assertions in it confirm the Basic header and payload are unchanged).

Note: if the mock data-plane server is not running locally, run `./tests/configure_test.sh` (fully offline) — it exercises `http_request` via the curl mock and asserts the Basic `Authorization` header and payload, which is the behavior this refactor must preserve.

- [ ] **Step 4: Commit**

```bash
git add src/lib/http.sh bin/altertable
git commit -m "refactor(http): extract reusable http_send transport core

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Add `src/lib/management.sh` (management API helpers)

Create the management-API library: base URL, Bearer auth header, environment-slug resolution, `jq` guard, and the `management_request` wrapper. Cover it with an offline unit test.

**Files:**
- Create: `src/lib/management.sh`
- Create: `tests/management_test.sh`
- Regenerate: `bin/altertable`
- Modify: `.github/workflows/test.yml` (add the new test step)

**Interfaces:**
- Consumes: `http_send` (Task 1), `secret_get` / `secret_exists` (`src/lib/secret.sh`), `config_get` (`src/lib/config.sh`), `log_error` (`src/lib/log.sh`).
- Produces:
  - `resolve_management_api_base()` → echoes `${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}`.
  - `get_management_auth_header()` → echoes `Authorization: Bearer <key>`; `<key>` is `$ALTERTABLE_API_KEY` if set, else the stored `api-key` secret; errors + `exit 1` if neither.
  - `management_env()` → echoes `$ALTERTABLE_ENV` if set, else `config_get api_key_env` (may be empty; caller decides whether to require it).
  - `require_management_env()` → echoes the env slug, or errors + `exit 1` if empty.
  - `require_jq()` → no-op if `jq` is on `PATH`, else errors + `exit 1`.
  - `management_request(method, endpoint, data, extra_headers…)` → `http_send` against `resolve_management_api_base + endpoint` with the Bearer header.

- [ ] **Step 1: Write the failing test `tests/management_test.sh`**

```bash
#!/usr/bin/env bash
# Offline tests for the management API helpers (whoami / catalogs share these).
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
unset ALTERTABLE_API_KEY ALTERTABLE_ENV ALTERTABLE_MANAGEMENT_API_BASE 2>/dev/null || true
cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

# A fake curl recording method, URL, Authorization header and -d payload to a log,
# returning a canned 200 JSON body. Per-path canned bodies are keyed off the URL.
setup_mgmt_curl_mock() {
  _M_DIR="$(mktemp -d)"
  export _M_LOG="${_M_DIR}/req.log"
  : > "${_M_LOG}"
  cat > "${_M_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
method=""; url=""; auth=""; payload=""; out=""; prev=""
for arg in "$@"; do
  case "$prev" in
    -X) method="$arg" ;;
    -H) case "$arg" in Authorization:*) auth="$arg" ;; esac ;;
    -d) payload="$arg" ;;
    -o) out="$arg" ;;
  esac
  case "$arg" in http*://*) url="$arg" ;; esac
  prev="$arg"
done
{ printf 'METHOD=%s\n' "$method"; printf 'URL=%s\n' "$url"; printf 'AUTH=%s\n' "$auth"; printf 'PAYLOAD=%s\n' "$payload"; } >> "${_M_LOG}"
[[ -n "$out" ]] && printf '{"principal":{"type":"User","name":"Jane","email":"j@x.io"},"organization":{"name":"Acme","slug":"acme"}}' > "$out"
printf '200'
MOCK
  chmod +x "${_M_DIR}/curl"
  _M_SAVED_PATH="${PATH}"
  export PATH="${_M_DIR}:${PATH}"
}
teardown_mgmt_curl_mock() { export PATH="${_M_SAVED_PATH}"; rm -rf "${_M_DIR}"; }

# ── Bearer auth from stored api-key, default base URL ──
"${CLI}" configure --api-key atm_stored --env production >/dev/null 2>&1
setup_mgmt_curl_mock
"${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_stored$' "${_M_LOG}" || fail "mgmt: expected Bearer atm_stored, got '$(grep '^AUTH=' "${_M_LOG}")'"
grep -q '^URL=https://app.altertable.ai/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: expected default base /whoami URL, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "management auth uses stored Bearer api-key against the default base URL"

# ── ALTERTABLE_API_KEY overrides the stored key; ALTERTABLE_MANAGEMENT_API_BASE overrides base ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:9/rest/v1 \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_env$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_API_KEY should win"
grep -q '^URL=http://localhost:9/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_MANAGEMENT_API_BASE should win"
teardown_mgmt_curl_mock
pass "ALTERTABLE_API_KEY and ALTERTABLE_MANAGEMENT_API_BASE take precedence"

# ── no api-key configured → clear error ──
"${CLI}" configure --clear >/dev/null 2>&1
ERR="$(ALTERTABLE_SECRET_BACKEND=file "${CLI}" whoami 2>&1 >/dev/null)"
echo "${ERR}" | grep -q "No management API key" || fail "mgmt: expected 'No management API key' error, got '${ERR}'"
pass "missing management API key errors clearly"

echo ""
echo -e "${GREEN}All management tests passed.${NC}"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `chmod +x tests/management_test.sh && ./tests/management_test.sh`
Expected: FAIL — `altertable whoami` does not exist yet (or `management.sh` functions are undefined). The first assertion fails.

- [ ] **Step 3: Create `src/lib/management.sh`**

```bash
# Management REST API helpers (app.altertable.ai/rest/v1). Bearer auth, env-scoped.
# Distinct from the data plane (api.altertable.ai, Basic auth) in src/lib/http.sh.

resolve_management_api_base() {
  echo "${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}"
}

# Echo "Authorization: Bearer <key>" from ALTERTABLE_API_KEY or the stored api-key secret.
get_management_auth_header() {
  local key="${ALTERTABLE_API_KEY:-}"
  if [[ -z "$key" ]] && secret_exists "api-key"; then
    key="$(secret_get 'api-key')"
  fi
  if [[ -z "$key" ]]; then
    log_error "No management API key. Run 'altertable configure --api-key atm_xxx --env <name>' or set ALTERTABLE_API_KEY."
    exit 1
  fi
  echo "Authorization: Bearer ${key}"
}

# Environment slug: ALTERTABLE_ENV, else the stored api_key_env. May be empty.
management_env() {
  local env="${ALTERTABLE_ENV:-}"
  [[ -z "$env" ]] && env="$(config_get api_key_env)"
  printf '%s' "$env"
}

# Environment slug, required.
require_management_env() {
  local env; env="$(management_env)"
  if [[ -z "$env" ]]; then
    log_error "No environment set. Run 'altertable configure --api-key atm_xxx --env <name>' or set ALTERTABLE_ENV."
    exit 1
  fi
  printf '%s' "$env"
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    log_error "This command requires 'jq'. Install it: https://jqlang.github.io/jq/"
    exit 1
  fi
}

management_request() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local extra_headers=("${@:4}")

  local url; url="$(resolve_management_api_base)${endpoint}"
  local auth_header
  auth_header=$(get_management_auth_header)

  http_send "${method}" "${url}" "${auth_header}" "${data}" "${extra_headers[@]}"
}
```

- [ ] **Step 4: Add the `whoami` command so the test can exercise the helpers**

This is the minimal command needed by `tests/management_test.sh`. Add to `src/bashly.yml` under `commands:` (after the `configure` command block), keeping the shared `--debug` anchor:

```yaml
- name: whoami
  help: Show the authenticated principal and organization (management API).
  flags:
  - *debug_flag
```

Create `src/whoami_command.sh`:

```bash
require_jq
response="$(management_request "GET" "/whoami" "")"

ptype="$(printf '%s' "$response" | jq -r '.principal.type // empty')"
pname="$(printf '%s' "$response" | jq -r '.principal.name // empty')"
pemail="$(printf '%s' "$response" | jq -r '.principal.email // empty')"
pslug="$(printf '%s' "$response" | jq -r '.principal.slug // empty')"
oname="$(printf '%s' "$response" | jq -r '.organization.name // empty')"
oslug="$(printf '%s' "$response" | jq -r '.organization.slug // empty')"

if [[ "$ptype" == "ServiceAccount" ]]; then
  printf 'Service account: %s (%s)\n' "$pname" "$pslug"
elif [[ -n "$pemail" ]]; then
  printf 'User: %s <%s>\n' "$pname" "$pemail"
else
  printf 'User: %s\n' "$pname"
fi
printf 'Organization: %s (%s)\n' "$oname" "$oslug"
```

- [ ] **Step 5: Regenerate the CLI**

Run: `bundle exec bashly generate`
Expected: regenerates `bin/altertable` with `altertable_whoami_command`; no errors.

- [ ] **Step 6: Run the management test to verify it passes**

Run: `./tests/management_test.sh`
Expected: PASS — all three assertions pass.

- [ ] **Step 7: Wire the new tests into CI**

In `.github/workflows/test.yml`, under the `test` job's steps, add after the `Run Configure Tests` step:

```yaml
      - name: Run Management Tests
        run: ./tests/management_test.sh
```

- [ ] **Step 8: Commit**

```bash
git add src/lib/management.sh src/bashly.yml src/whoami_command.sh tests/management_test.sh .github/workflows/test.yml bin/altertable
git commit -m "feat(whoami): add whoami command and management API helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `whoami` output test

Lock the human-readable `whoami` formatting with its own assertions (the helper test only checked the request; this checks the rendered output for both principal types).

**Files:**
- Create: `tests/whoami_test.sh`
- Modify: `.github/workflows/test.yml` (add test step)

**Interfaces:**
- Consumes: `altertable whoami` (Task 2), the curl-mock pattern from `tests/management_test.sh`.

- [ ] **Step 1: Write the failing test `tests/whoami_test.sh`**

```bash
#!/usr/bin/env bash
# Offline tests for `altertable whoami` output formatting.
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
export ALTERTABLE_API_KEY=atm_test
unset ALTERTABLE_ENV ALTERTABLE_MANAGEMENT_API_BASE 2>/dev/null || true
cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

# Fake curl returning a caller-supplied body via $_BODY.
mock_curl_body() {
  _D="$(mktemp -d)"
  cat > "${_D}/curl" <<MOCK
#!/usr/bin/env bash
out=""; prev=""
for arg in "\$@"; do case "\$prev" in -o) out="\$arg" ;; esac; prev="\$arg"; done
[[ -n "\$out" ]] && printf '%s' '${_BODY}' > "\$out"
printf '200'
MOCK
  chmod +x "${_D}/curl"; _SP="${PATH}"; export PATH="${_D}:${PATH}"
}
unmock_curl() { export PATH="${_SP}"; rm -rf "${_D}"; }

# ── User principal ──
_BODY='{"principal":{"type":"User","name":"Jane Doe","email":"jane@x.io"},"organization":{"name":"Acme","slug":"acme"}}'
mock_curl_body
OUT="$("${CLI}" whoami 2>/dev/null)"
unmock_curl
echo "${OUT}" | grep -Fq 'User: Jane Doe <jane@x.io>' || fail "whoami user line wrong: '${OUT}'"
echo "${OUT}" | grep -Fq 'Organization: Acme (acme)' || fail "whoami org line wrong: '${OUT}'"
pass "whoami formats a User principal"

# ── ServiceAccount principal ──
_BODY='{"principal":{"type":"ServiceAccount","name":"ci-bot","slug":"ci-bot"},"organization":{"name":"Acme","slug":"acme"}}'
mock_curl_body
OUT="$("${CLI}" whoami 2>/dev/null)"
unmock_curl
echo "${OUT}" | grep -Fq 'Service account: ci-bot (ci-bot)' || fail "whoami service-account line wrong: '${OUT}'"
pass "whoami formats a ServiceAccount principal"

echo ""
echo -e "${GREEN}All whoami tests passed.${NC}"
```

- [ ] **Step 2: Run to verify it passes** (the command already exists from Task 2)

Run: `chmod +x tests/whoami_test.sh && ./tests/whoami_test.sh`
Expected: PASS — both principal types render correctly. (If a line fails, fix `src/whoami_command.sh`, regenerate, re-run.)

- [ ] **Step 3: Wire into CI**

In `.github/workflows/test.yml`, add after the `Run Management Tests` step:

```yaml
      - name: Run Whoami Tests
        run: ./tests/whoami_test.sh
```

- [ ] **Step 4: Commit**

```bash
git add tests/whoami_test.sh .github/workflows/test.yml
git commit -m "test(whoami): assert human-readable output for both principal types

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `catalogs create` command

Add the `catalogs` parent command with a `create` subcommand: engine validation, env-scoped POST to `/databases`, readable confirmation.

**Files:**
- Modify: `src/bashly.yml` (add `catalogs` parent + `create` subcommand)
- Create: `src/catalogs_create_command.sh`
- Create: `tests/catalogs_test.sh`
- Modify: `.github/workflows/test.yml` (add test step)
- Regenerate: `bin/altertable`

**Interfaces:**
- Consumes: `require_jq`, `require_management_env`, `management_request` (Task 2).
- Produces: `altertable catalogs create --engine <e> --name <n>` → POST `/environments/<env>/databases` with body `{"name":<n>,"engine":"altertable"}`; rejects engines ≠ `altertable`.

- [ ] **Step 1: Write the failing test `tests/catalogs_test.sh`**

```bash
#!/usr/bin/env bash
# Offline tests for `altertable catalogs` (create + list).
set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils.sh"
CLI="${SCRIPT_DIR}/../bin/altertable"

TEST_HOME="$(mktemp -d)"
export ALTERTABLE_CONFIG_HOME="${TEST_HOME}"
export ALTERTABLE_SECRET_BACKEND=file
export ALTERTABLE_API_KEY=atm_test
export ALTERTABLE_ENV=production
unset ALTERTABLE_MANAGEMENT_API_BASE 2>/dev/null || true
cleanup() { rm -rf "${TEST_HOME}"; }
trap cleanup EXIT

# Fake curl: logs METHOD/URL/AUTH/PAYLOAD per call; returns a per-path canned body.
# A database response is returned for .../databases, connections for .../connections.
setup_cat_mock() {
  _C="$(mktemp -d)"; export _C_LOG="${_C}/req.log"; : > "${_C_LOG}"
  cat > "${_C}/curl" <<'MOCK'
#!/usr/bin/env bash
method="GET"; url=""; auth=""; payload=""; out=""; prev=""
for arg in "$@"; do
  case "$prev" in
    -X) method="$arg" ;;
    -H) case "$arg" in Authorization:*) auth="$arg" ;; esac ;;
    -d) payload="$arg" ;;
    -o) out="$arg" ;;
  esac
  case "$arg" in http*://*) url="$arg" ;; esac
  prev="$arg"
done
{ printf 'METHOD=%s\n' "$method"; printf 'URL=%s\n' "$url"; printf 'AUTH=%s\n' "$auth"; printf 'PAYLOAD=%s\n' "$payload"; printf -- '---\n'; } >> "${_C_LOG}"
body='{}'
case "$url" in
  *"/databases")
    if [[ "$method" == "POST" ]]; then
      body='{"database":{"name":"My Cat","slug":"my-cat","engine":"altertable","catalog":"my_cat"}}'
    else
      body='{"databases":[{"name":"My Cat","slug":"my-cat","engine":"altertable","catalog":"my_cat"}]}'
    fi ;;
  *"/connections") body='{"connections":[{"name":"Prod PG","slug":"prod-pg","engine":"postgres","catalog":"prod_pg"}]}';;
esac
[[ -n "$out" ]] && printf '%s' "$body" > "$out"
printf '200'
MOCK
  chmod +x "${_C}/curl"; _CSP="${PATH}"; export PATH="${_C}:${PATH}"
}
teardown_cat_mock() { export PATH="${_CSP}"; rm -rf "${_C}"; }

# ── create: engine validation ──
ERR="$("${CLI}" catalogs create --engine postgres --name "X" 2>&1 >/dev/null)"
echo "${ERR}" | grep -Fq "Only the 'altertable' engine is supported" || fail "create: expected engine rejection, got '${ERR}'"
pass "catalogs create rejects non-altertable engines"

# ── create: request shape ──
setup_cat_mock
OUT="$("${CLI}" catalogs create --engine altertable --name "My Cat" 2>/dev/null)"
teardown_cat_mock
grep -q '^METHOD=POST$' "${_C_LOG}" || fail "create: expected POST"
grep -q '^URL=https://app.altertable.ai/rest/v1/environments/production/databases$' "${_C_LOG}" || fail "create: wrong URL: $(grep '^URL=' "${_C_LOG}")"
grep -q '^AUTH=Authorization: Bearer atm_test$' "${_C_LOG}" || fail "create: wrong auth"
PAYLOAD="$(grep '^PAYLOAD=' "${_C_LOG}" | sed 's/^PAYLOAD=//')"
[[ "$(printf '%s' "$PAYLOAD" | jq -cS '.')" == '{"engine":"altertable","name":"My Cat"}' ]] || fail "create: wrong payload: '${PAYLOAD}'"
echo "${OUT}" | grep -Fq 'Created catalog "My Cat"' || fail "create: missing confirmation: '${OUT}'"
pass "catalogs create posts to /databases with the right payload and confirms"

# ── create: requires an environment ──
ERR="$(ALTERTABLE_ENV='' "${CLI}" catalogs create --engine altertable --name "X" 2>&1 >/dev/null)"
echo "${ERR}" | grep -Fq "No environment set" || fail "create: expected env-required error, got '${ERR}'"
pass "catalogs create requires an environment"

echo ""
echo -e "${GREEN}All catalogs tests passed.${NC}"
```

- [ ] **Step 2: Run to verify it fails**

Run: `chmod +x tests/catalogs_test.sh && ./tests/catalogs_test.sh`
Expected: FAIL — `catalogs` command does not exist yet.

- [ ] **Step 3: Add the `catalogs` command to `src/bashly.yml`**

Add after the `whoami` command block:

```yaml
- name: catalogs
  help: Manage catalogs (databases and connections) in the current environment.
  commands:
  - name: create
    help: Create a catalog. Only the 'altertable' engine is supported.
    examples:
    - altertable catalogs create --engine altertable --name "My Cat"
    flags:
    - long: --engine
      arg: name
      help: Catalog engine (only 'altertable' is supported)
      required: true
    - long: --name
      arg: name
      help: Catalog name
      required: true
    - *debug_flag
  - name: list
    help: List catalogs (databases and connections) in the current environment.
    flags:
    - *debug_flag
```

(The `list` subcommand is declared now so the parent command is well-formed; its body is added in Task 5. Bashly requires a command file for every leaf command, so Task 5 creates `src/catalogs_list_command.sh`. Until then, generating will create a stub — that is fine; the `create` tests do not invoke `list`.)

- [ ] **Step 4: Create `src/catalogs_create_command.sh`**

```bash
require_jq

engine="${args[--engine]}"
name="${args[--name]}"

if [[ "$engine" != "altertable" ]]; then
  log_error "Only the 'altertable' engine is supported (got '${engine}')."
  exit 1
fi

env="$(require_management_env)"
body="$(jq -n --arg name "$name" '{name: $name, engine: "altertable"}')"

response="$(management_request "POST" "/environments/${env}/databases" "$body")"

cslug="$(printf '%s' "$response" | jq -r '(.database // .connection).slug // empty')"
cname="$(printf '%s' "$response" | jq -r '(.database // .connection).name // empty')"
cengine="$(printf '%s' "$response" | jq -r '(.database // .connection).engine // "altertable"')"
[[ -z "$cname" ]] && cname="$name"

printf 'Created catalog "%s" (slug: %s, engine: %s, environment: %s).\n' \
  "$cname" "$cslug" "$cengine" "$env"
```

- [ ] **Step 5: Create a placeholder `src/catalogs_list_command.sh` so generation succeeds**

```bash
require_jq
log_error "Not implemented yet."
exit 1
```

(Replaced with the real implementation in Task 5.)

- [ ] **Step 6: Regenerate the CLI**

Run: `bundle exec bashly generate`
Expected: regenerates `bin/altertable` with `altertable_catalogs_create_command` and `altertable_catalogs_list_command`; no errors.

- [ ] **Step 7: Run the catalogs test to verify create passes**

Run: `./tests/catalogs_test.sh`
Expected: PASS for the create assertions. (The list test is added in Task 5; the current file has no list assertions yet.)

- [ ] **Step 8: Wire into CI**

In `.github/workflows/test.yml`, add after the `Run Whoami Tests` step:

```yaml
      - name: Run Catalogs Tests
        run: ./tests/catalogs_test.sh
```

- [ ] **Step 9: Commit**

```bash
git add src/bashly.yml src/catalogs_create_command.sh src/catalogs_list_command.sh tests/catalogs_test.sh .github/workflows/test.yml bin/altertable
git commit -m "feat(catalogs): add 'catalogs create' for the altertable engine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `catalogs list` command

Implement the real `catalogs list`: env-scoped GET of `/databases` then `/connections` (databases first), rendered as an aligned, type-tagged table. Strict — non-2xx (including a 404 from `/databases`) errors out.

**Files:**
- Modify: `src/catalogs_list_command.sh` (replace the placeholder)
- Modify: `tests/catalogs_test.sh` (add list assertions)
- Regenerate: `bin/altertable`

**Interfaces:**
- Consumes: `require_jq`, `require_management_env`, `management_request` (Task 2).
- Produces: `altertable catalogs list` → table with columns `TYPE NAME SLUG ENGINE CATALOG`, databases first.

- [ ] **Step 1: Add the list assertions to `tests/catalogs_test.sh`**

Insert before the final `echo ""` / "All catalogs tests passed" lines:

```bash
# ── list: calls databases then connections, databases first in the table ──
setup_cat_mock
OUT="$("${CLI}" catalogs list 2>/dev/null)"
teardown_cat_mock
# Both endpoints were called, databases before connections.
DB_URL_LINE="$(grep -n '^URL=.*/databases$' "${_C_LOG}" | head -1 | cut -d: -f1)"
CONN_URL_LINE="$(grep -n '^URL=.*/connections$' "${_C_LOG}" | head -1 | cut -d: -f1)"
[[ -n "$DB_URL_LINE" && -n "$CONN_URL_LINE" ]] || fail "list: expected both /databases and /connections calls"
[[ "$DB_URL_LINE" -lt "$CONN_URL_LINE" ]] || fail "list: /databases must be called before /connections"
# Output: header + database row before connection row.
echo "${OUT}" | grep -Eq '^TYPE[[:space:]]+NAME[[:space:]]+SLUG[[:space:]]+ENGINE[[:space:]]+CATALOG' || fail "list: missing header: '${OUT}'"
DB_OUT_LINE="$(echo "${OUT}" | grep -n 'database' | head -1 | cut -d: -f1)"
CONN_OUT_LINE="$(echo "${OUT}" | grep -n 'connection' | head -1 | cut -d: -f1)"
[[ -n "$DB_OUT_LINE" && -n "$CONN_OUT_LINE" && "$DB_OUT_LINE" -lt "$CONN_OUT_LINE" ]] || fail "list: databases must render before connections: '${OUT}'"
pass "catalogs list shows databases before connections in a table"

# ── list: a non-2xx (e.g. 404 from /databases) hard-fails ──
setup_cat_404() {
  _C="$(mktemp -d)"; _CSP="${PATH}"
  cat > "${_C}/curl" <<'MOCK'
#!/usr/bin/env bash
out=""; prev=""
for arg in "$@"; do case "$prev" in -o) out="$arg";; esac; prev="$arg"; done
[[ -n "$out" ]] && printf '{"error":{"code":"not_found"}}' > "$out"
printf '404'
MOCK
  chmod +x "${_C}/curl"; export PATH="${_C}:${PATH}"
}
setup_cat_404
if "${CLI}" catalogs list >/dev/null 2>&1; then export PATH="${_CSP}"; rm -rf "${_C}"; fail "list: a 404 must hard-fail"; fi
export PATH="${_CSP}"; rm -rf "${_C}"
pass "catalogs list hard-fails on a non-2xx response"
```

- [ ] **Step 2: Run to verify the list assertions fail**

Run: `./tests/catalogs_test.sh`
Expected: FAIL — the placeholder `catalogs list` prints "Not implemented yet." and exits 1, so the list assertions fail.

- [ ] **Step 3: Replace `src/catalogs_list_command.sh` with the real implementation**

```bash
require_jq
env="$(require_management_env)"

databases="$(management_request "GET" "/environments/${env}/databases" "")"
connections="$(management_request "GET" "/environments/${env}/connections" "")"

# Emit tab-separated rows: TYPE, NAME, SLUG, ENGINE, CATALOG. Databases first.
rows="$(
  {
    printf '%s' "$databases" | jq -r '
      (.databases // [])[] |
      ["database", (.name // ""), (.slug // ""), (.engine // ""), (.catalog // "")] | @tsv'
    printf '%s' "$connections" | jq -r '
      (.connections // [])[] |
      ["connection", (.name // ""), (.slug // ""), (.engine // ""), (.catalog // "")] | @tsv'
  }
)"

if [[ -z "$rows" ]]; then
  printf 'No catalogs found.\n'
  exit 0
fi

{
  printf 'TYPE\tNAME\tSLUG\tENGINE\tCATALOG\n'
  printf '%s\n' "$rows"
} | column -t -s "$(printf '\t')"
```

- [ ] **Step 4: Regenerate the CLI**

Run: `bundle exec bashly generate`
Expected: regenerates `bin/altertable`; no errors.

- [ ] **Step 5: Run the catalogs test to verify all assertions pass**

Run: `./tests/catalogs_test.sh`
Expected: PASS — create and list assertions all pass.

- [ ] **Step 6: Commit**

```bash
git add src/catalogs_list_command.sh tests/catalogs_test.sh bin/altertable
git commit -m "feat(catalogs): add 'catalogs list' combining databases and connections

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Documentation

Document the new commands, environment variables, and the management-vs-data-plane distinction in `README.md`.

**Files:**
- Modify: `README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Add a "Management API commands" section to `README.md`**

Place it after the existing `## Configuration` section (which already documents `configure --api-key … --env …`). Use this content:

````markdown
## Management API commands

`whoami` and `catalogs` talk to the **management API**
(`https://app.altertable.ai/rest/v1` by default) — a different service from the data plane
used by `query`/`append`/etc. They authenticate with a **management API key** (a `Bearer`
`atm_` token), not lakehouse Basic credentials, and `catalogs` is scoped to an
**environment**.

Set both with `configure`:

```bash
altertable configure --api-key atm_xxxx --env production
```

Or via environment variables (these take precedence over stored config):

```bash
export ALTERTABLE_API_KEY="atm_xxxx"
export ALTERTABLE_ENV="production"
# Override the API base (e.g. for staging/self-hosted):
# export ALTERTABLE_MANAGEMENT_API_BASE="https://app.altertable.ai/rest/v1"
```

These commands require `jq`.

### whoami

```bash
altertable whoami
# User: Jane Doe <jane@example.com>
# Organization: Acme (acme)
```

### catalogs

A *catalog* spans two backend resources — **databases** and **connections** — both scoped
to the current environment.

```bash
# Create a catalog (only the 'altertable' engine is supported):
altertable catalogs create --engine altertable --name "My Cat"

# List catalogs (databases first, then connections):
altertable catalogs list
# TYPE        NAME     SLUG     ENGINE      CATALOG
# database    My Cat   my-cat   altertable  my_cat
# connection  Prod PG  prod-pg  postgres    prod_pg
```
````

- [ ] **Step 2: Document the new environment variables in the existing env-var list**

In `README.md`, find where existing environment variables are listed (the Configuration section references `ALTERTABLE_BASIC_AUTH_TOKEN`, `ALTERTABLE_LAKEHOUSE_USERNAME`/`_PASSWORD`, `ALTERTABLE_SECRET_BACKEND`). Add these three entries in the same style:

- `ALTERTABLE_API_KEY` — management API key (`atm_` token) for `whoami`/`catalogs`; overrides stored config.
- `ALTERTABLE_ENV` — environment slug for `catalogs`; overrides the stored `api_key_env`.
- `ALTERTABLE_MANAGEMENT_API_BASE` — management API base URL (default `https://app.altertable.ai/rest/v1`).

- [ ] **Step 3: Verify the CLI help reflects the new commands**

Run: `./bin/altertable --help && ./bin/altertable catalogs --help`
Expected: `whoami` and `catalogs` appear in top-level help; `create` and `list` appear under `catalogs`.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document whoami and catalogs commands

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Run the full offline suite: `./tests/configure_test.sh && ./tests/management_test.sh && ./tests/whoami_test.sh && ./tests/catalogs_test.sh` — all pass.
- [ ] Confirm `bin/altertable` is in sync: `bundle exec bashly generate && git diff --exit-code -I '^  declare -g version=' bin/altertable` — no diff.
- [ ] Run ShellCheck over `bin/` and `tests/` (matching CI `severity: warning`): `shellcheck -S warning bin/altertable tests/*.sh` — no warnings/errors. (If `shellcheck` is not installed locally, CI covers this.)
