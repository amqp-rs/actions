# CLAUDE.md — amqp-rs/actions

This repository contains shared [composite GitHub Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) used by all CI workflows in the amqp-rs ecosystem. Each action lives in its own directory as an `action.yml` file.

## Structure

```
actions/
  checkout/action.yml                # wrapper around actions/checkout (credentials not persisted)
  actionlint/action.yml              # GitHub Actions workflow linting (pinned actionlint)
  build/action.yml                   # cargo hack check (each-feature, locked) + cargo test
  lint/action.yml                    # clippy + cargo doc (each-feature, -D warnings) + rustfmt
  security/action.yml                # cargo audit (rustsec)
  semver/action.yml                  # cargo-semver-checks
  aws-lc-sys-deps/action.yml         # AWS_LC_SYS_PREBUILT_NASM=1 on Windows
  openssl-no-vendor/action.yml       # sets OPENSSL_NO_VENDOR=1
  openssl-vcpkg/action.yml           # OpenSSL via vcpkg on Windows (release-only triplets, binary cache)
  openssl-vcpkg/triplets/            # overlay triplets used by openssl-vcpkg
  windows-setup-tls-env/action.yml   # combines aws-lc-sys-deps + openssl-vcpkg + openssl-no-vendor (Windows only)
  self-test/                         # fixture crate the self-test workflow runs the actions on
  .github/workflows/self-test.yml    # runs this commit's actions (./<name>) on the fixture
  TODO.md                            # planned work (reusable workflows)
```

## Testing changes

Consumers run `@main`, so a broken action breaks every repository at once.
`self-test.yml` runs the actions from the commit under test (`uses: ./<name>`)
on the fixture crate in `self-test/`, copied to the workspace root, across
the same OS/toolchain matrix the consumers use. actionlint only checks
workflow files, not `action.yml`, so this is the only pre-merge check that
an action loads and runs.

- `windows-setup-tls-env` references its sub-actions as `@main` (see
  "Versioning" in `README.md`), so it cannot test a change to them. The
  self-test runs `aws-lc-sys-deps`, `openssl-vcpkg` and `openssl-no-vendor`
  directly, and only checks that the aggregate loads.
- `security` and `semver` are not exercised: they need a write token for
  check runs and a published baseline crate respectively.
- Keep the fixture clean under the `lint` action (clippy and rustdoc with
  `-D warnings` on every feature set).

## Composite action constraints

- Every `run:` step **must** declare a `shell:` — there is no default in composite actions. Use `shell: bash` for cross-platform commands and `shell: pwsh` for PowerShell (Windows-only steps).
- `if:` conditions on steps support `inputs.<name>` and `runner.os` expressions.
- Boolean inputs are strings: compare with `== 'true'` / `== 'false'`, not `== true`.
- Steps using `uses:` do not require `shell:`.
- Composite actions cannot define job-level `env`, matrix strategies, services, or `GITHUB_TOKEN` permissions — those stay in the calling workflow. See `README.md` for each caller's required token scopes.
- `$GITHUB_ENV` writes persist for the remainder of the job (including steps in the calling workflow after this action returns). The `build` action uses this to export `RUSTUP_TOOLCHAIN` and append `-D warnings` to the caller's `RUSTFLAGS` once rather than repeating them per step; append, never overwrite, so job-level flags survive.

## Consumers

All six amqp-rs crate repositories call these actions. Their workflow files are the canonical examples of intended usage. They reference `@main` on purpose and must not be pinned, because this repository is how action bumps stay in sync across them (see "Versioning" in `README.md`):

| Repo | Setup action | Notes |
|---|---|---|
| `amq-protocol` | `windows-setup-tls-env` | |
| `lapin` | `windows-setup-tls-env` | Split `check` / `test` jobs; `test` needs RabbitMQ service |
| `async-rs` | none | |
| `tcp-stream` | `windows-setup-tls-env` | |
| `rustls-connector` | `aws-lc-sys-deps` | |
| `async-openssl` | `openssl-vcpkg` | |

## Adding a new action

1. Create a new directory and `action.yml` with `runs.using: composite`.
2. Declare all inputs in the `inputs:` block with descriptions and defaults.
3. Add a `shell:` to every `run:` step.
4. Document it in `README.md` with a usage snippet.
5. Add the directory to `directories:` in `.github/dependabot.yml` — see below.
6. Exercise it in `.github/workflows/self-test.yml` — see "Testing changes".

## Tool versions

Dependabot only updates `uses:` refs, never a tool version given through an
action input:

| Tool | Where | Version |
|---|---|---|
| `actionlint` | `version:` in `actionlint/action.yml` | Exact, bumped by hand: a new release can add checks that turn every repository's CI red at once |
| `cargo-hack` | `tool:` in `build/action.yml` and `lint/action.yml` (keep them equal) | `0.6`, which `taiki-e/install-action@v2` resolves to the latest 0.6.x it knows; moving to a new minor is done by hand |

## Dependabot

Every action directory must be listed individually in `.github/dependabot.yml`.
The `github-actions` ecosystem with a plain `directory: /` only scans
`.github/workflows/` plus a *root* `action.yml`, so an unlisted action silently
never gets version updates — which is exactly how `actions/checkout` sat on v6
for six weeks after v7 shipped.

Do not replace the list with a `/*` wildcard. Globbed directories can make
Dependabot scan `.github/workflows` twice and open duplicate PRs
([dependabot-core#10884](https://github.com/dependabot/dependabot-core/issues/10884),
still open).
