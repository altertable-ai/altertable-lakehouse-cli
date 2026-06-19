# Development

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

## Credential storage

Where things are stored:

- **Non-secret config** (username, api-key environment): `~/.config/altertable/config`.
- **Secret** (password, Basic token, or API key): the **macOS Keychain** when available,
  otherwise a `~/.config/altertable/credentials` file with `chmod 600`. Force a backend
  with `ALTERTABLE_SECRET_BACKEND=keychain|file`. `altertable configure --show` shows
  which is in use (`MacOS keychain` or the file path). For security, the CLI **refuses to
  read the credentials file if its permissions are looser than `600`** — run
  `chmod 600 ~/.config/altertable/credentials` if prompted.

## Targeting a local deployment

`configure` accepts endpoint overrides, used only for local development for now. They are
only valid alongside a credential and are stored with it; the control-plane URL is a server
root (the CLI appends `/rest/v1`). Omitting an endpoint on a later `configure` resets it to
the production default.

```bash
# Point the management commands at a local control plane:
altertable configure --api-key atm_xxxx --env production --control-plane-url http://localhost:13000

# Point the lakehouse commands at a local data plane:
altertable configure --user your_username --password your_password --data-plane-url http://localhost:15000
```

The control-plane server root can also be overridden via the environment (the CLI appends
`/rest/v1`):

```bash
export ALTERTABLE_MANAGEMENT_API_BASE="http://localhost:13000"
```

## Tests

Integration tests run against the Altertable mock server:

```bash
docker run -d --rm --name at-mock -p 15000:15000 \
  -e ALTERTABLE_MOCK_USERS=testuser:testpass \
  ghcr.io/altertable-ai/altertable-mock:latest
./tests/integration_test.sh
docker stop at-mock
```
