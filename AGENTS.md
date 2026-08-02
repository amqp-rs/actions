# CLAUDE.md — amqp-rs/actions

This repository contains shared [composite GitHub Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) used by all CI workflows in the amqp-rs ecosystem. Each action lives in its own directory as an `action.yml` file.

## Structure

```
actions/
  checkout/action.yml                # wrapper around actions/checkout
  actionlint/action.yml              # GitHub Actions workflow linting
  build/action.yml                   # cargo hack check (each-feature) + cargo test
  lint/action.yml                    # clippy + rustfmt + cargo doc
  security/action.yml                # cargo audit (rustsec)
  semver/action.yml                  # cargo-semver-checks
  aws-lc-sys-deps/action.yml         # NASM + ninja on Windows
  openssl-no-vendor/action.yml       # sets OPENSSL_NO_VENDOR=1
  openssl-vcpkg/action.yml           # OpenSSL via vcpkg on Windows
  windows-setup-tls-env/action.yml   # combines aws-lc-sys-deps + openssl-vcpkg + openssl-no-vendor
```

## Composite action constraints

- Every `run:` step **must** declare a `shell:` — there is no default in composite actions. Use `shell: bash` for cross-platform commands and `shell: pwsh` for PowerShell (Windows-only steps).
- `if:` conditions on steps support `inputs.<name>` and `runner.os` expressions.
- Boolean inputs are strings: compare with `== 'true'` / `== 'false'`, not `== true`.
- Steps using `uses:` do not require `shell:`.
- Composite actions cannot define job-level `env`, matrix strategies, or services — those stay in the calling workflow.
- `$GITHUB_ENV` writes persist for the remainder of the job (including steps in the calling workflow after this action returns). The `build` action uses this to set `RUSTFLAGS=-D warnings` once rather than repeating it per step.

## Consumers

All six amqp-rs crate repositories call these actions. Their workflow files are the canonical examples of intended usage:

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
