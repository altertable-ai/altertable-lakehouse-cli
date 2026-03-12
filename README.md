# Altertable Lakehouse CLI

You can use this CLI to query and ingest data in Altertable Lakehouse from shell scripts and terminals.

## Install

```bash
cp bin/altertable /usr/local/bin/altertable
chmod +x /usr/local/bin/altertable
```

## Quick start

```bash
export ALTERTABLE_USERNAME="your-username"
export ALTERTABLE_PASSWORD="your-password"
altertable query --statement "SELECT 1 AS ok"
```

## API reference

### `query`

`altertable query --statement "<sql>"` executes a SQL query.

### `append`

`altertable append --catalog <catalog> --schema <schema> --table <table> --data '<json>'` appends JSON rows.

### `upload`

`altertable upload --catalog <catalog> --schema <schema> --table <table> --format <csv|parquet|...> --mode <append|replace> --file <path>` uploads a file.

### `get-query`

`altertable get-query <query-id>` returns query execution details.

### `cancel`

`altertable cancel --query-id <query-id> --session-id <session-id>` cancels a running query.

### `validate`

`altertable validate --statement "<sql>"` validates SQL without execution.

## Configuration

| Option | Type | Default | Description |
|---|---|---|---|
| `ALTERTABLE_USERNAME` | `string` | unset | Basic Auth username. |
| `ALTERTABLE_PASSWORD` | `string` | unset | Basic Auth password. |
| `ALTERTABLE_BASIC_AUTH_TOKEN` | `string` | unset | Base64 `username:password` token alternative. |
| `ALTERTABLE_BASE_URL` | `string` | `https://api.altertable.ai` | API base URL override. |

## Development

Prerequisites: Bash 4+, `curl`, `jq`, and `shellcheck`.

```bash
bash tests/integration_test.sh
shellcheck bin/* scripts/*
```

## License

See [LICENSE](LICENSE).