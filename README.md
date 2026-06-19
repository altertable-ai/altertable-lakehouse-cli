# Altertable Lakehouse CLI

A Bash-based CLI for the Altertable Lakehouse API.

## Requirements

- `bash` (4.2+)
- `curl`
- `jq`

## Installation

Clone the repository and add the `bin` directory to your PATH, or copy the script:

```bash
cp bin/altertable /usr/local/bin/altertable
chmod +x /usr/local/bin/altertable
```

## Usage

### Authentication

`altertable configure` allows you to authenticate using the following mechanisms:
 - Management API key (`--api-key`) and a specified environment (`--env`)
 - Lakehouse credentials (`--user` and `--password`)

For any authentication mechanism, environment variables take precedence over stored
configuration, which keeps CI and scripted usage working unchanged.

Inspect the stored configuration (secrets are masked) or clear everything (no prompt):

```bash
altertable configure --show
altertable configure --clear
```

#### REST API Key

The [management commands](#management-commands) (`whoami`, `catalogs`) authenticate with a
**management API key** — a `Bearer` `atm_` token. `configure`
requires `--env` alongside the key:

```bash
altertable configure --api-key atm_xxxx --env production
printf '%s' "$KEY" | altertable configure --api-key-stdin --env production
```

Or via environment variables (these take precedence over stored config):

```bash
export ALTERTABLE_API_KEY="atm_xxxx"
export ALTERTABLE_ENV="production"
```

#### Lakehouse credentials

The [lakehouse commands](#lakehouse-commands) (`query`, `append`, `upload`, …) authenticate
with a lakehouse username/password. Unlike a [REST API key](#rest-api-key),
these credentials are issued for a specific environment, so the commands automatically
target that credential's environment:

```bash
altertable configure
altertable configure --user your_username --password your_password
printf '%s' "$PASSWORD" | altertable configure --user your_username --password-stdin

# ...or a pre-encoded HTTP Basic token:
altertable configure --basic-token "$(printf '%s' user:pass | base64)"
```

Or via environment variables (these take precedence over stored config):

```bash
export ALTERTABLE_LAKEHOUSE_USERNAME="your_lakehouse_username"
export ALTERTABLE_LAKEHOUSE_PASSWORD="your_lakehouse_password"
# Or use a pre-encoded token
export ALTERTABLE_BASIC_AUTH_TOKEN="base64-token"
```

### Management commands

#### whoami

```bash
altertable whoami
# User: Jane Doe <jane@example.com>
# Organization: Acme (acme)
```

#### catalogs

```bash
# Create a catalog:
altertable catalogs create --engine altertable --name "My Cat"

# List catalogs:
altertable catalogs list
# TYPE        NAME     SLUG     ENGINE      CATALOG
# database    My Cat   my-cat   altertable  my_cat
# connection  Prod PG  prod-pg  postgres    prod_pg
```

### Lakehouse commands

#### Run a Query

```bash
altertable query --statement "SELECT * FROM users LIMIT 10"
```

#### Append Data

```bash
# Append a single record
altertable append --catalog my_cat --schema public --table users --data '{"id": 1, "name": "Alice"}'

# Append a batch of records
altertable append --catalog my_cat --schema public --table users --data '[{"id": 2, "name": "Bob"}, {"id": 3, "name": "Charlie"}]'

# Append from a file
altertable append --catalog my_cat --schema public --table users --data @records.json
```

#### Upload a File

```bash
altertable upload \
  --catalog my_cat \
  --schema public \
  --table users \
  --format csv \
  --mode append \
  --file data.csv
```

#### Get Query Details

```bash
altertable get-query "query-uuid"
```

#### Cancel a Query

```bash
altertable cancel --query-id "query-uuid" --session-id "session-uuid"
```

#### Validate SQL

```bash
altertable validate --statement "SELECT * FROM users"
```

## Development

See [DEVELOPMENT.md](DEVELOPMENT.md) for building the CLI, targeting a local deployment, and
running the tests.

## License

MIT
