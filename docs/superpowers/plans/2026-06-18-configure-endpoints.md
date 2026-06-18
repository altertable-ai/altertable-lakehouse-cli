# Configure Endpoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `altertable configure` store the data-plane and control-plane base URLs (alongside a credential), with the control-plane URL given as a bare server root that the CLI extends with `/rest/v1`.

**Architecture:** Two base-URL resolvers gain a stored-config layer between their env var and built-in default. The control-plane resolver now treats its input as a server root and appends the constant `/rest/v1`. The `configure` command gets two optional flags (`--data-plane-url`, `--control-plane-url`) that are valid only alongside a credential and are wiped/rewritten under the existing single-override model.

**Tech Stack:** Bash, [bashly](https://bashly.dannyb.co/) 1.3.8 (generates `bin/altertable` from `src/`), `curl`, `jq`.

## Global Constraints

- This is a [bashly](https://bashly.dannyb.co/) project: **never edit `bin/altertable` by hand.** Edit files under `src/` and run `bundle exec bashly generate`. CI fails if `bin/altertable` is out of sync.
- Everything in `src/lib/*.sh` is auto-bundled; no manual `source` wiring is needed. `config_get`/`config_set` (in `src/lib/config.sh`) are available to all libs at runtime.
- Bashly command bodies read flags from the global `args` array (e.g. `${args[--data-plane-url]}`).
- ShellCheck runs at `severity: warning` over `bin/` and `tests/` (not `src/`). Keep generated output clean.
- Resolution precedence (highest first): **environment variable → stored config → built-in default.**
- Data-plane default: `https://api.altertable.ai` (full base; endpoints attach directly).
- Control-plane default **root**: `https://app.altertable.ai`; resolver appends `/rest/v1`, so the effective management base is `https://app.altertable.ai/rest/v1`.
- Stored config keys: `api_base` (data plane), `management_api_base` (control-plane root). Non-secret — config file only, never the keychain.
- A single trailing `/` is trimmed during resolution.
- Endpoint flags are valid only when a credential is also being set; otherwise error `endpoint flags must be set together with a credential.` and exit non-zero.
- All new tests are offline (`ALTERTABLE_SECRET_BACKEND=file`, fake `curl` on `PATH`).

---

### Task 1: Control-plane resolver takes a server root and appends `/rest/v1`

Change `resolve_management_api_base` so its input (env var, stored config, or default) is a server root without `/rest/v1`, and it appends the constant API path. Update the management tests to the new root semantics and add stored-config + trailing-slash coverage.

**Files:**
- Modify: `src/lib/management.sh` (`resolve_management_api_base`)
- Modify: `tests/management_test.sh`
- Regenerate: `bin/altertable`

**Interfaces:**
- Consumes: `config_get` (`src/lib/config.sh`).
- Produces: `resolve_management_api_base()` → still returns the **full** management base ending in `/rest/v1` (e.g. `https://app.altertable.ai/rest/v1`). `management_request` and the whoami/catalogs commands are unchanged.

- [ ] **Step 1: Update the precedence assertion and add new cases in `tests/management_test.sh`**

Replace the existing precedence block:

```bash
# ── ALTERTABLE_API_KEY overrides the stored key; ALTERTABLE_MANAGEMENT_API_BASE overrides base ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:9/rest/v1 \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_env$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_API_KEY should win"
grep -q '^URL=http://localhost:9/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_MANAGEMENT_API_BASE should win"
teardown_mgmt_curl_mock
pass "ALTERTABLE_API_KEY and ALTERTABLE_MANAGEMENT_API_BASE take precedence"
```

with this (env var is now a bare root; CLI appends `/rest/v1`), followed by two new cases:

```bash
# ── ALTERTABLE_API_KEY overrides the stored key; ALTERTABLE_MANAGEMENT_API_BASE (a root) overrides base ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:9 \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^AUTH=Authorization: Bearer atm_env$' "${_M_LOG}" || fail "mgmt: ALTERTABLE_API_KEY should win"
grep -q '^URL=http://localhost:9/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: expected root + /rest/v1, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "ALTERTABLE_MANAGEMENT_API_BASE is a root; the CLI appends /rest/v1"

# ── stored management_api_base (a root) is used when no env var is set ──
printf 'management_api_base=http://localhost:7\n' >> "${ALTERTABLE_CONFIG_HOME}/config"
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env "${CLI}" whoami >/dev/null 2>&1
grep -q '^URL=http://localhost:7/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: stored root should be used, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "a stored management_api_base root is honored"

# ── a trailing slash on the root is trimmed ──
setup_mgmt_curl_mock
ALTERTABLE_API_KEY=atm_env ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:8/ \
  "${CLI}" whoami >/dev/null 2>&1
grep -q '^URL=http://localhost:8/rest/v1/whoami$' "${_M_LOG}" || fail "mgmt: trailing slash should be trimmed, got '$(grep '^URL=' "${_M_LOG}")'"
teardown_mgmt_curl_mock
pass "a trailing slash on the control-plane root is trimmed"
```

Note: the stored-config case writes `management_api_base` directly into the test's config file (`${ALTERTABLE_CONFIG_HOME}/config`); the first test case already ran `configure --api-key atm_stored --env production`, so that file exists. The `ALTERTABLE_API_KEY=atm_env` prefix just satisfies the auth requirement without depending on stored secrets.

- [ ] **Step 2: Run the management test to verify the new cases fail**

Run: `./tests/management_test.sh`
Expected: FAIL — the current resolver returns `${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}`, so `ALTERTABLE_MANAGEMENT_API_BASE=http://localhost:9` produces `http://localhost:9/whoami` (missing `/rest/v1`), failing the first updated assertion.

- [ ] **Step 3: Rewrite `resolve_management_api_base` in `src/lib/management.sh`**

Replace:

```bash
resolve_management_api_base() {
  echo "${ALTERTABLE_MANAGEMENT_API_BASE:-https://app.altertable.ai/rest/v1}"
}
```

with:

```bash
# Resolve the control-plane server root (env var -> stored config -> default), trim a
# trailing slash, and append the constant /rest/v1 API path.
resolve_management_api_base() {
  local root="${ALTERTABLE_MANAGEMENT_API_BASE:-}"
  [[ -z "$root" ]] && root="$(config_get management_api_base)"
  [[ -z "$root" ]] && root="https://app.altertable.ai"
  root="${root%/}"
  echo "${root}/rest/v1"
}
```

- [ ] **Step 4: Regenerate and run the management + whoami + catalogs tests**

Run: `bundle exec bashly generate && ./tests/management_test.sh && ./tests/whoami_test.sh && ./tests/catalogs_test.sh`
Expected: all PASS. (whoami/catalogs use default or `ALTERTABLE_MANAGEMENT_API_BASE`/explicit values that still resolve to `<root>/rest/v1`; the catalogs test sets no management base so it uses the default root → `https://app.altertable.ai/rest/v1/...`.)

- [ ] **Step 5: Commit**

```bash
git add src/lib/management.sh tests/management_test.sh bin/altertable
git commit -m "feat(config): control-plane URL is a server root; CLI appends /rest/v1

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `configure` stores both endpoints; data-plane resolver gains stored layer

Add `--data-plane-url` / `--control-plane-url` to `configure`, store them under the single-override model (only alongside a credential), add the data-plane stored-config layer, and show the control plane in `--show`.

**Files:**
- Modify: `src/bashly.yml` (configure flags)
- Modify: `src/lib/configure.sh` (`configure_clear_all`, `configure_run_set`, `configure_run_show`)
- Modify: `src/lib/config.sh` (`resolve_api_base`)
- Modify: `tests/configure_test.sh` (mock + new cases)
- Regenerate: `bin/altertable`

**Interfaces:**
- Consumes: `config_set` / `config_get` / `config_unset` (`src/lib/config.sh`), `resolve_api_base`, `resolve_management_api_base` (Task 1).
- Produces: `configure --data-plane-url <url>` stores config key `api_base`; `--control-plane-url <url>` stores `management_api_base`. `resolve_api_base()` → full data-plane base (env → `config_get api_base` → default), trailing slash trimmed.

- [ ] **Step 1: Extend the curl mock in `tests/configure_test.sh` to also log the request URL**

In `setup_curl_mock`, add a URL log alongside the auth log. Replace the existing function body's logging setup and loop:

```bash
setup_curl_mock() {
  _CURL_MOCK_DIR="$(mktemp -d)"
  export _CURL_MOCK_AUTH_LOG="${_CURL_MOCK_DIR}/auth.log"
  export _CURL_MOCK_URL_LOG="${_CURL_MOCK_DIR}/url.log"
  : > "${_CURL_MOCK_AUTH_LOG}"
  : > "${_CURL_MOCK_URL_LOG}"
  cat > "${_CURL_MOCK_DIR}/curl" <<'MOCK'
#!/usr/bin/env bash
out=""; prev=""
for arg in "$@"; do
  case "$prev" in
    -H) case "$arg" in Authorization:*) printf '%s\n' "$arg" > "${_CURL_MOCK_AUTH_LOG}" ;; esac ;;
    -o) out="$arg" ;;
  esac
  case "$arg" in http*://*) printf '%s\n' "$arg" > "${_CURL_MOCK_URL_LOG}" ;; esac
  prev="$arg"
done
[[ -n "$out" ]] && printf '{"ok":true}' > "$out"
printf '200'
MOCK
  chmod +x "${_CURL_MOCK_DIR}/curl"
  _CURL_MOCK_SAVED_PATH="${PATH}"
  export PATH="${_CURL_MOCK_DIR}:${PATH}"
}
```

(Only two lines are new: the `_CURL_MOCK_URL_LOG` export + its `: >` reset, and the `case "$arg" in http*://*)` capture. The auth capture and everything else is unchanged.)

- [ ] **Step 2: Add the new endpoint test cases near the end of `tests/configure_test.sh`**

Insert before the final `echo ""` / "All configure tests passed" lines:

```bash
# ── endpoints stored alongside a credential ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --api-key atm_x --env prod --control-plane-url http://localhost:13000 >/dev/null 2>&1
grep -q '^management_api_base=http://localhost:13000$' "${CONFIG_FILE}" || fail "endpoints: control-plane root should be stored verbatim"
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u --password p --data-plane-url http://localhost:15000 >/dev/null 2>&1
grep -q '^api_base=http://localhost:15000$' "${CONFIG_FILE}" || fail "endpoints: data-plane base should be stored"
pass "configure stores endpoints alongside a credential"

# ── stored control-plane root gains /rest/v1 at request time ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --api-key atm_x --env prod --control-plane-url http://localhost:13000 >/dev/null 2>&1
setup_curl_mock
"${CLI}" whoami >/dev/null 2>&1
URL="$(cat "${_CURL_MOCK_URL_LOG}")"
teardown_curl_mock
[[ "${URL}" == "http://localhost:13000/rest/v1/whoami" ]] || fail "endpoints: expected stored root + /rest/v1/whoami, got '${URL}'"
pass "a stored control-plane root resolves to <root>/rest/v1"

# ── endpoint flag without a credential errors ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
ERR="$("${CLI}" configure --data-plane-url http://x 2>&1 >/dev/null)"
echo "${ERR}" | grep -Fq "endpoint flags must be set together with a credential." || fail "endpoints: standalone endpoint should error, got '${ERR}'"
pass "an endpoint flag without a credential is rejected"

# ── omitting an endpoint resets it to the default (override model) ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u --password p --data-plane-url http://localhost:15000 >/dev/null 2>&1
"${CLI}" configure --user u --password p >/dev/null 2>&1
if grep -q '^api_base=' "${CONFIG_FILE}"; then fail "endpoints: a later configure without the flag should drop the stored endpoint"; fi
pass "omitting an endpoint resets it to the default"

# ── env var beats stored data-plane base ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u --password p --data-plane-url http://stored:1111 >/dev/null 2>&1
setup_curl_mock
ALTERTABLE_API_BASE=http://env:2222 "${CLI}" query --statement "SELECT 1" >/dev/null 2>&1
URL="$(cat "${_CURL_MOCK_URL_LOG}")"
teardown_curl_mock
[[ "${URL}" == "http://env:2222/query" ]] || fail "endpoints: ALTERTABLE_API_BASE should beat stored api_base, got '${URL}'"
setup_curl_mock
"${CLI}" query --statement "SELECT 1" >/dev/null 2>&1
URL="$(cat "${_CURL_MOCK_URL_LOG}")"
teardown_curl_mock
[[ "${URL}" == "http://stored:1111/query" ]] || fail "endpoints: stored api_base should be used when no env var, got '${URL}'"
pass "data-plane precedence: env var > stored config"

# ── --show displays both planes ──
rm -f "${CONFIG_FILE}" "${CRED_FILE}"
"${CLI}" configure --user u --password p --data-plane-url http://localhost:15000 --control-plane-url http://localhost:13000 >/dev/null 2>&1
OUT="$("${CLI}" configure --show 2>/dev/null)"
echo "${OUT}" | grep -q 'Data plane:' || fail "--show: missing Data plane line"
echo "${OUT}" | grep -q 'Control plane:' || fail "--show: missing Control plane line"
echo "${OUT}" | grep -Fq 'http://localhost:15000' || fail "--show: should show the stored data-plane base"
echo "${OUT}" | grep -Fq 'http://localhost:13000/rest/v1' || fail "--show: should show the resolved control-plane base"
pass "--show displays both the data plane and the control plane"
```

- [ ] **Step 3: Run the configure test to verify the new cases fail**

Run: `./tests/configure_test.sh`
Expected: FAIL — `--control-plane-url` is an unknown flag (bashly rejects it), so the first new case fails.

- [ ] **Step 4: Add the two flags to the `configure` command in `src/bashly.yml`**

Insert after the `--clear` flag and before the `*debug_flag` line in the `configure` command's `flags:` list:

```yaml
  - long: --data-plane-url
    arg: url
    help: "Data-plane base URL (stored with the credential; default: https://api.altertable.ai)"
  - long: --control-plane-url
    arg: url
    help: "Control-plane server root; the CLI appends /rest/v1 (default: https://app.altertable.ai)"
```

- [ ] **Step 5: Update `src/lib/config.sh` `resolve_api_base` for the stored layer + trim**

Replace:

```bash
resolve_api_base() { echo "${ALTERTABLE_API_BASE:-https://api.altertable.ai}"; }
```

with:

```bash
resolve_api_base() {
  local base="${ALTERTABLE_API_BASE:-}"
  [[ -z "$base" ]] && base="$(config_get api_base)"
  [[ -z "$base" ]] && base="https://api.altertable.ai"
  echo "${base%/}"
}
```

- [ ] **Step 6: Update `configure_clear_all` in `src/lib/configure.sh`**

Replace:

```bash
configure_clear_all() {
  secret_delete "lakehouse/password"
  secret_delete "lakehouse/basic-token"
  secret_delete "api-key"
  config_unset user
  config_unset api_key_env
}
```

with:

```bash
configure_clear_all() {
  secret_delete "lakehouse/password"
  secret_delete "lakehouse/basic-token"
  secret_delete "api-key"
  config_unset user
  config_unset api_key_env
  config_unset api_base
  config_unset management_api_base
}
```

- [ ] **Step 7: Update `configure_run_set` in `src/lib/configure.sh`**

Read the two new flags, include them in the "no input" guard, reject endpoint-without-credential, and write them after the credential. Replace the whole function with:

```bash
configure_run_set() {
  local user="${args[--user]:-}"
  local password="${args[--password]:-}"
  local basic_token="${args[--basic-token]:-}"
  local api_key="${args[--api-key]:-}"
  local env="${args[--env]:-}"
  local want_pw_stdin="${args[--password-stdin]:-}"
  local want_key_stdin="${args[--api-key-stdin]:-}"
  local data_plane_url="${args[--data-plane-url]:-}"
  local control_plane_url="${args[--control-plane-url]:-}"

  # No input at all -> interactive lakehouse setup.
  if [[ -z "$user$password$basic_token$api_key$env$want_pw_stdin$want_key_stdin$data_plane_url$control_plane_url" ]]; then
    configure_run_interactive
    return 0
  fi

  if [[ -n "$want_pw_stdin" ]]; then IFS= read -r password || true; fi
  if [[ -n "$want_key_stdin" ]]; then IFS= read -r api_key || true; fi

  # Identify the requested mechanism; at most one is allowed.
  local m_lakehouse="" m_token="" m_apikey="" count=0
  [[ -n "$user" || -n "$password" ]] && m_lakehouse=1
  [[ -n "$basic_token" ]] && m_token=1
  [[ -n "$api_key" ]] && m_apikey=1
  [[ -n "$m_lakehouse" ]] && count=$((count + 1))
  [[ -n "$m_token" ]] && count=$((count + 1))
  [[ -n "$m_apikey" ]] && count=$((count + 1))

  if [[ "$count" -gt 1 ]]; then
    log_error "Choose a single authentication mechanism: --user/--password, --basic-token, or --api-key (they cannot be combined)."
    exit 1
  fi
  if [[ ( -n "$data_plane_url" || -n "$control_plane_url" ) && "$count" -eq 0 ]]; then
    log_error "endpoint flags must be set together with a credential."
    exit 1
  fi
  if [[ -n "$env" && -z "$m_apikey" ]]; then
    log_error "--env applies only to --api-key."
    exit 1
  fi
  if [[ "$count" -eq 0 ]]; then
    log_error "Nothing to configure. Use --user/--password, --basic-token, or --api-key --env <name>."
    exit 1
  fi
  if [[ -n "$m_lakehouse" && ( -z "$user" || -z "$password" ) ]]; then
    log_error "--user and --password must be provided together."
    exit 1
  fi
  if [[ -n "$m_apikey" && -z "$env" ]]; then
    log_error "--api-key requires --env <name>."
    exit 1
  fi

  # Override: a new configuration replaces any previous one.
  configure_clear_all
  if [[ -n "$m_apikey" ]]; then
    secret_set "api-key" "$api_key"
    config_set api_key_env "$env"
  elif [[ -n "$m_token" ]]; then
    secret_set "lakehouse/basic-token" "$basic_token"
  else
    config_set user "$user"
    secret_set "lakehouse/password" "$password"
  fi
  [[ -n "$data_plane_url" ]] && config_set api_base "$data_plane_url"
  [[ -n "$control_plane_url" ]] && config_set management_api_base "$control_plane_url"
  printf 'Configuration updated.\n' >&2
}
```

- [ ] **Step 8: Add the Control plane line to `configure_run_show` in `src/lib/configure.sh`**

Replace:

```bash
  printf '  Data plane:    %s\n' "$(resolve_api_base)"
```

with:

```bash
  printf '  Data plane:    %s\n' "$(resolve_api_base)"
  printf '  Control plane: %s\n' "$(resolve_management_api_base)"
```

- [ ] **Step 9: Regenerate and run the full offline suite**

Run: `bundle exec bashly generate && ./tests/configure_test.sh && ./tests/management_test.sh && ./tests/whoami_test.sh && ./tests/catalogs_test.sh`
Expected: all PASS.

- [ ] **Step 10: Commit**

```bash
git add src/bashly.yml src/lib/configure.sh src/lib/config.sh tests/configure_test.sh bin/altertable
git commit -m "feat(configure): store data-plane and control-plane endpoints

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Documentation

Document the new flags and update the control-plane env-var semantics in `README.md`.

**Files:**
- Modify: `README.md`

**Interfaces:** none (docs only).

- [ ] **Step 1: Document the endpoint flags in the Configuration section**

In `README.md`, in the `## Configuration` section's first code block (the lakehouse/api-key examples), add two example lines after the `--api-key` examples:

```bash
# ...point the CLI at a non-production deployment (endpoints are stored with the credential):
altertable configure --api-key atm_xxxx --env production --control-plane-url http://localhost:13000
altertable configure --user your_username --password your_password --data-plane-url http://localhost:15000
```

And add a sentence after that block: "Endpoint flags (`--data-plane-url`, `--control-plane-url`) are only valid alongside a credential; the control-plane URL is a server root (the CLI appends `/rest/v1`). Omitting an endpoint on a later `configure` resets it to the production default."

- [ ] **Step 2: Update the control-plane env-var docs in the Management API commands section**

In `README.md`, in the `## Management API commands` section, replace the override comment:

```bash
# Override the API base (e.g. for staging/self-hosted):
# export ALTERTABLE_MANAGEMENT_API_BASE="https://app.altertable.ai/rest/v1"
```

with:

```bash
# Override the control-plane server root (the CLI appends /rest/v1):
# export ALTERTABLE_MANAGEMENT_API_BASE="https://app.altertable.ai"
```

And update the env-var bullet from:

- `ALTERTABLE_MANAGEMENT_API_BASE` — management API base URL (default `https://app.altertable.ai/rest/v1`).

to:

- `ALTERTABLE_MANAGEMENT_API_BASE` — control-plane server root; the CLI appends `/rest/v1` (default `https://app.altertable.ai`).

- [ ] **Step 3: Verify help shows the new flags**

Run: `./bin/altertable configure --help`
Expected: `--data-plane-url` and `--control-plane-url` appear in the flag list.

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document configure endpoint flags and control-plane root semantics

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Full offline suite: `./tests/configure_test.sh && ./tests/management_test.sh && ./tests/whoami_test.sh && ./tests/catalogs_test.sh` — all pass.
- [ ] `bin/altertable` in sync: `bundle exec bashly generate && git diff --exit-code -I '^  declare -g version=' bin/altertable` — no diff.
- [ ] ShellCheck: `shellcheck -S warning bin/altertable tests/*.sh` — clean (CI covers this if not installed locally).
