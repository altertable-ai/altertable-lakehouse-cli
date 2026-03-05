# Altertable Lakehouse CLI

A Bash-based CLI for the Altertable Lakehouse API.

## Requirements

- `bash` (4.0+)
- `curl`
- `jq` (optional but recommended for pretty-printing and robust JSON handling)

## Installation

Clone the repository and add the `bin` directory to your PATH, or copy the script:

```bash
cp bin/altertable /usr/local/bin/altertable
chmod +x /usr/local/bin/altertable
```

## Configuration

Set the following environment variables for authentication:

```bash
export ALTERTABLE_USERNAME="your-username"
export ALTERTABLE_PASSWORD="your-password"
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

## License

MIT
