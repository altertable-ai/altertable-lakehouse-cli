# Contributing to altertable-lakehouse-cli

## Development Setup

This CLI is generated with [bashly](https://bashly.dev). The source of truth is
the `src/` directory; `bin/altertable` is a generated artifact — never edit it by
hand.

1. Fork and clone the repository
2. Install the toolchain (requires Ruby + Bundler): `bundle install`
3. Generate the CLI: `bundle exec bashly generate`

## Making Changes

1. Create a branch from `main`
2. Edit `src/bashly.yml` (commands/flags) or `src/*_command.sh` / `src/lib/*.sh` (logic)
3. Regenerate and stage both source and binary: `bundle exec bashly generate && git add src bin/altertable`
4. Add or update tests
5. Run the checks: `shellcheck bin/altertable` and `./tests/integration_test.sh`
6. Commit using [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, etc.)
7. Open a pull request

> CI regenerates `bin/altertable` and fails the build if the committed copy is out
> of date (ignoring the version line, which release-please manages), so always
> commit `src/` and the regenerated `bin/altertable` together.

## Code Style

This project uses `ShellCheck` for linting and `shfmt` for formatting. Run `shellcheck bin/altertable` before committing.

## Tests

- Unit tests are required for all new functionality
- Integration tests run in CI when credentials are available
- Run tests locally: `./bin/altertable --help`

## Pull Requests

- Keep PRs focused on a single change
- Update `CHANGELOG.md` under `[Unreleased]`
- Ensure CI passes before requesting review
