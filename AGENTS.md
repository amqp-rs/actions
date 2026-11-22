# AGENTS.md

This file provides guidance to coding agents working with code in this repository.

This repository contains the shared CI of the amqp-rs ecosystem: reusable workflows in `.github/workflows/` and the [composite GitHub Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) they run. Each action lives in its own directory as an `action.yml` file.

## Structure

```
actions/
  checkout/action.yml                # wrapper around actions/checkout (credentials not persisted)
  actionlint/action.yml              # GitHub Actions workflow linting (pinned actionlint)
  build/action.yml                   # cargo hack check (each-feature, locked) + cargo test
  build/run-tests.sh                 # the build action's cargo test runs (test-args, test-features, test-runs)
  lint/action.yml                    # clippy + cargo doc (each-feature, -D warnings) + rustfmt
  security/action.yml                # cargo audit (rustsec)
  semver/action.yml                  # cargo-semver-checks
  aws-lc-sys-deps/action.yml         # AWS_LC_SYS_PREBUILT_NASM=1 on Windows
  openssl-no-vendor/action.yml       # sets OPENSSL_NO_VENDOR=1
  openssl-vcpkg/action.yml           # OpenSSL via vcpkg on Windows (release-only triplets, binary cache)
  openssl-vcpkg/triplets/            # overlay triplets used by openssl-vcpkg
  windows-setup-tls-env/action.yml   # combines aws-lc-sys-deps + openssl-vcpkg + openssl-no-vendor (Windows only)
  Cargo.toml, Cargo.lock             # the workspace at the repository root, whose only member is the fixture crate
  self-test/                         # fixture crate the self-test workflow runs the actions and reusable workflows on
  self-test/check-run-tests.sh       # checks build/run-tests.sh's cargo invocations and output with a stub cargo
  .github/workflows/self-test.yml    # runs this commit's actions (./<name>) and reusable workflows on the fixture
  .github/workflows/reusable-*.yml   # workflow_call workflows the crates call: actionlint, lint, semver, security, build
  .gitattributes                     # keeps shell scripts LF in Windows checkouts
```

## Testing changes

Consumers run `@main`, so a broken action breaks every repository at once.
`self-test.yml` runs the actions from the commit under test (`uses: ./<name>`)
on the fixture crate in `self-test/`, the only member of the workspace at
the repository root, across the same OS/toolchain matrix the consumers use.
actionlint only checks
workflow files, not `action.yml`, so this is the only pre-merge check that
an action loads and runs.

- `windows-setup-tls-env` references its sub-actions as `@main` (see
  "Versioning" in `README.md`), so it cannot test a change to them. The
  self-test runs `aws-lc-sys-deps`, `openssl-vcpkg` and `openssl-no-vendor`
  directly, and only checks that the aggregate loads.
- The self-test calls this commit's `reusable-actionlint.yml`,
  `reusable-lint.yml` and `reusable-build.yml`
  (`uses: ./.github/workflows/<file>`). They run cargo at the repository
  root, which is why the workspace is there. A called workflow resolves `./`
  in its caller's checkout, so they reference the actions as `@main`: these
  jobs check that a workflow file loads, its matrix and how its inputs reach
  the actions, not this commit's actions. Check a change to one against the
  callers' `with:` blocks too.
- The fixture's `rustflags` test only passes when built with
  `--cfg fixture_rustflags`, which the self-test passes through the job's
  `RUSTFLAGS` (`build`) and through the `rustflags` input (`reusable-build`).
- `security` and `semver`, and the reusable workflows that run them, are not
  exercised: they need a write token for check runs and a published baseline
  crate respectively.
- Keep the fixture clean under the `lint` action (clippy and rustdoc with
  `-D warnings` on every feature set).
- The fixture's tests cannot tell whether `build/run-tests.sh` placed an
  argument right, so `self-test/check-run-tests.sh` checks its cargo
  invocations and its output against a stub cargo; extend it with any change
  to that script. It runs on Linux and on macOS, whose bash is 3.2: keep
  `run-tests.sh` within what that version supports.
- The `build-failure` job fails a real test run through the `build` action.
  The fixture's `greets` test appends its greeting to the file that
  `FIXTURE_GREETINGS` names, which is how the job tells that failure from one
  that came before the test runs or stopped them.

## Composite action constraints

- Every `run:` step **must** declare a `shell:` — there is no default in composite actions. Use `shell: bash` for cross-platform commands and `shell: pwsh` for PowerShell (Windows-only steps).
- `if:` conditions on steps support `inputs.<name>` and `runner.os` expressions.
- Boolean inputs are strings: compare with `== 'true'` / `== 'false'`, not `== true`.
- Steps using `uses:` do not require `shell:`.
- Composite actions cannot define job-level `env`, matrix strategies, services, or `GITHUB_TOKEN` permissions — those stay in the calling workflow. See `README.md` for each caller's required token scopes.
- `$GITHUB_ENV` writes persist for the remainder of the job (including steps in the calling workflow after this action returns). The `build` action uses this to export `RUSTUP_TOOLCHAIN` and append `-D warnings` to the caller's `RUSTFLAGS` once rather than repeating them per step; append, never overwrite, so job-level flags survive.

## Consumers

All six amqp-rs crate repositories call the reusable workflows, and the actions directly where a job needs a service, another target or steps of its own. Their workflow files are the canonical examples of intended usage. They reference `@main` on purpose and must not be pinned, because this repository is how action bumps stay in sync across them (see "Versioning" in `README.md`):

| Repo | `setup` | Notes |
|---|---|---|
| `amq-protocol` | `windows-setup-tls-env` | Lint job uses the `lint` action directly, then checks the generated code |
| `lapin` | `windows-setup-tls-env` | `check` calls the build workflow and runs the tests that need no broker (`test-args`); `test` uses the `build` action with a RabbitMQ service |
| `async-rs` | none | |
| `tcp-stream` | `windows-setup-tls-env` | |
| `rustls-connector` | `aws-lc-sys-deps` | Own `android` job on the `build` action; also triggers on `rustls-connector-0.23.x` |
| `async-openssl` | `openssl-vcpkg` | `timeout-minutes: 30` |

`reusable-build.yml` gives each of its jobs a 60-minute timeout unless the caller passes `timeout-minutes`. Jobs that use the `build` action directly (lapin's `test`, rustls-connector's `android`) are not covered and have to set their own.

## Adding a new action

1. Create a new directory and `action.yml` with `runs.using: composite`.
2. Declare all inputs in the `inputs:` block with descriptions and defaults.
3. Add a `shell:` to every `run:` step.
4. Document it in `README.md` with a usage snippet.
5. Add the directory to `directories:` in `.github/dependabot.yml` — see below.
6. Exercise it in `.github/workflows/self-test.yml` — see "Testing changes".
7. For a setup action, which a build job runs before `build`, make it a
   `setup` value of `.github/workflows/reusable-build.yml`: add it to the
   list in the `Check the setup input` step, add its conditional `uses:`
   step, and name it in the input's description and in the `setup` row of
   the input table in `README.md`. A name missing from the list fails every
   job of a caller that passes it.

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
