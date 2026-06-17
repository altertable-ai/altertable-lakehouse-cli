# Altertable Lakehouse CLI

A Bash-based CLI for the Altertable Lakehouse API.

## Requirements

- `bash` (4.2+)
- `curl`
- `jq` (optional but recommended for pretty-printing and robust JSON handling)

## Installation

Clone the repository and add the `bin` directory to your PATH, or copy the script:

```bash
cp bin/altertable /usr/local/bin/altertable
chmod +x /usr/local/bin/altertable
```

## Configuration

The fastest way to get set up is `altertable configure`, which stores credentials
securely (OS keychain when available, otherwise a `0600` file under
`~/.config/altertable`).

```bash
# Lakehouse credentials (global — the environment is derived from the credential).
# Run with no flags to be prompted (password input is hidden):
altertable configure

# Or pass them directly (prefer the prompt or --password-stdin to keep secrets out of shell history):
altertable configure --user your_username --password your_password
printf '%s' "$PASSWORD" | altertable configure --user your_username --password-stdin

# Management API key (per environment):
altertable configure --api-key atm_xxxx --env production
printf '%s' "$KEY" | altertable configure --api-key-stdin --env production

# Inspect (secrets are masked) and remove:
altertable configure --list
altertable configure --remove --env production
altertable configure --remove --lakehouse
altertable configure --remove --all
```

Where things are stored:

- **Non-secret config** (username, base URLs, default env): `~/.config/altertable/config`.
- **Secrets** (password, API keys, Basic token): the OS keychain — macOS Keychain
  (`security`) or Linux libsecret (`secret-tool`) — or, if neither is present,
  `~/.config/altertable/credentials` (`chmod 600`). Force a backend with
  `ALTERTABLE_SECRET_BACKEND=keychain|file`.

Credential precedence (highest first): environment variables
(`ALTERTABLE_BASIC_AUTH_TOKEN`, `ALTERTABLE_LAKEHOUSE_USERNAME`/`_PASSWORD`) →
stored configuration. This keeps CI and scripted usage working unchanged:

```bash
export ALTERTABLE_LAKEHOUSE_USERNAME="your_lakehouse_username"
export ALTERTABLE_LAKEHOUSE_PASSWORD="your_lakehouse_password"
# Or use a pre-encoded token
# export ALTERTABLE_BASIC_AUTH_TOKEN="base64-token"
```

## Usage

### Run a Query

```bash
altertable query --statement "SELECT * FROM users LIMIT 10"
```

### Append Data

```bash
# Append a single record
altertable append --catalog my_cat --schema public --table users --data '{"id": 1, "name": "Alice"}'

# Append a batch of records
altertable append --catalog my_cat --schema public --table users --data '[{"id": 2, "name": "Bob"}, {"id": 3, "name": "Charlie"}]'

# Append from a file
altertable append --catalog my_cat --schema public --table users --data @records.json
```

### Upload a File

```bash
altertable upload \
  --catalog my_cat \
  --schema public \
  --table users \
  --format csv \
  --mode append \
  --file data.csv
```

### Get Query Details

```bash
altertable get-query "query-uuid"
```

### Cancel a Query

```bash
altertable cancel --query-id "query-uuid" --session-id "session-uuid"
```

### Validate SQL

```bash
altertable validate --statement "SELECT * FROM users"
```

## Development

The CLI is generated with [bashly](https://bashly.dev). The source of truth is the
`src/` directory; `bin/altertable` is a generated artifact and must not be edited
by hand.

```bash
# Install the toolchain (Ruby + Bundler required)
bundle install

# Edit src/bashly.yml (commands/flags) or src/*_command.sh / src/lib/*.sh (logic),
# then regenerate and commit both the source and the generated binary:
bundle exec bashly generate
git add src bin/altertable
```

The version lives in `src/bashly.yml` and is bumped automatically by release-please.

### Tests

Integration tests run against the Altertable mock server:

```bash
docker run -d --rm --name at-mock -p 15000:15000 \
  -e ALTERTABLE_MOCK_USERS=testuser:testpass \
  ghcr.io/altertable-ai/altertable-mock:latest
./tests/integration_test.sh
docker stop at-mock
```

## License

MIT
