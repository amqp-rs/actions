# actions

Shared CI for the [amqp-rs](https://github.com/amqp-rs) ecosystem: [reusable workflows](#reusable-workflows), which a crate's workflow files call for their jobs, and the [composite GitHub Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) they run, [listed below](#available-actions) for the jobs that need a service, another target or steps of their own.

## Available actions

### `checkout`

Checks out the repository. Thin wrapper around `actions/checkout` with `persist-credentials: false`, so the job token is not left in `.git/config` for build scripts and tests to read.

```yaml
- uses: amqp-rs/actions/checkout@main
```

### `actionlint`

Lints GitHub Actions workflow files with [`actionlint`](https://github.com/rhysd/actionlint), at a pinned version and without the unused `pyflakes` integration.

```yaml
- uses: amqp-rs/actions/checkout@main
- uses: amqp-rs/actions/actionlint@main
```

### `lint`

Runs clippy and rustdoc on stable Rust for every feature set [`cargo-hack`](https://github.com/taiki-e/cargo-hack)'s `--each-feature` produces, with warnings denied, and checks formatting. clippy covers all targets (tests, examples and benches included). The formatting and documentation checks still run when clippy fails, so a single push reports every problem.

```yaml
- uses: amqp-rs/actions/checkout@main
- uses: amqp-rs/actions/lint@main
```

### `security`

Runs `cargo audit` via the [RustSec advisory database](https://rustsec.org/).

```yaml
- uses: amqp-rs/actions/checkout@main
- uses: amqp-rs/actions/security@main
```

### `semver`

Checks semver compliance with [`cargo-semver-checks`](https://github.com/obi1kenobi/cargo-semver-checks). Like `lint`, it links the system OpenSSL (`OPENSSL_NO_VENDOR=1`) instead of compiling the vendored one.

```yaml
- uses: amqp-rs/actions/checkout@main
- uses: amqp-rs/actions/semver@main
```

### `build`

Installs a Rust toolchain, sets up build caching, checks the workspace feature by feature with [`cargo-hack`](https://github.com/taiki-e/cargo-hack), and runs `cargo test`. Everything runs with `RUSTFLAGS=-D warnings`, and with `--locked` so a stale `Cargo.lock` fails instead of being rewritten.

```yaml
- uses: amqp-rs/actions/checkout@main
- uses: amqp-rs/actions/build@main
  with:
    rust: stable   # stable, nightly, beta, msrv, or an explicit version; default: stable
    check: 'true'  # set to 'false' to skip cargo check steps
    test: 'true'   # set to 'false' to skip cargo test
    test-features: |  # optional: extra feature sets to test, one per line
      smol
    test-runs: |  # optional: extra cargo test runs, one per line
      -p my-crate --no-default-features
    test-args: ''  # optional: extra cargo test arguments, e.g. --lib
```

| Input | Default | Description |
|---|---|---|
| `rust` | `stable` | Toolchain to install (`stable`, `nightly`, `beta`, `msrv`, or an explicit version such as `1.88.0`); `msrv` reads `rust-version` with `cargo metadata` and fails unless the workspace declares exactly one |
| `check` | `true` | Run `cargo hack check --each-feature --workspace --all-targets`; on `stable`, also again with `--no-dev-deps` to catch features that only dev-dependencies enable; on `beta` and `nightly`, only `cargo check` with `--all-features` and with `--no-default-features` |
| `test` | `true` | Run `cargo test` |
| `test-features` | empty | Extra feature sets to test, one per line; each runs `cargo test --no-default-features --features <set>` after the default-features run |
| `test-runs` | empty | Extra `cargo test` runs, one per line, each given as its arguments split on whitespace (no quoting), after the `test-features` runs; covers what `test-features` cannot, such as no features at all (`--no-default-features`) or a single package |
| `test-args` | empty | Extra arguments for every `cargo test` run, on one or more lines, e.g. `--lib` to run only unit tests where integration tests need a service, or `-p <package>` in a virtual workspace; they come before each run's own arguments, except the test harness arguments after a `--` on each line, which come after them |

Every `cargo test` run uses `--locked` and `--no-fail-fast`, and goes ahead when an earlier one fails, so a single job reports every failing configuration; the step then fails, with an error annotation per failed run. Each run's output is in a log group named after its command, and a failed run's output is printed again after its group, so that it shows without expanding one. cargo refuses a flag given twice: `--no-fail-fast` is left out of a run when `test-args` or the run itself has it, but neither may repeat `--locked`.

Build caches are saved for every toolchain except `nightly`: a new nightly ships every day and the cache key includes it, so a saved nightly cache could only ever serve reruns.

For the rest of the job, the action exports `RUSTUP_TOOLCHAIN` (so a `rust-toolchain.toml` cannot silently swap the matrix toolchain) and appends `-D warnings` to `RUSTFLAGS`. On toolchains older than stable it also appends `-A unknown_lints`, so an `allow` for a lint newer than the MSRV does not fail the build. Pass extra rustflags through a job-level `RUSTFLAGS` (the `rustflags` input of `reusable-build.yml`, whose callers cannot set `env`): they are kept, whereas `.cargo/config.toml` rustflags are ignored by cargo once `RUSTFLAGS` is set.

### `aws-lc-sys-deps`

Sets `AWS_LC_SYS_PREBUILT_NASM=1` on Windows, so `aws-lc-sys` (used by `aws-lc-rs`) assembles nothing and links the prebuilt NASM objects it ships instead; no NASM install is needed. FIPS builds (`aws-lc-fips-sys`) are not supported. No-op on Linux and macOS.

```yaml
- uses: amqp-rs/actions/aws-lc-sys-deps@main
```

### `openssl-no-vendor`

Sets `OPENSSL_NO_VENDOR=1` to prevent `openssl-sys` from building a bundled OpenSSL.

```yaml
- uses: amqp-rs/actions/openssl-no-vendor@main
```

### `openssl-vcpkg`

Installs a static OpenSSL with vcpkg on Windows and points `openssl-sys` at it (`VCPKG_ROOT`, `VCPKGRS_TRIPLET`). It uses a release-only variant of the `x64-windows-static-md` triplet (or `arm64-…` on ARM64 runners), shipped in [`openssl-vcpkg/triplets`](openssl-vcpkg/triplets), because `openssl-sys` never links the debug build. vcpkg's binary packages are cached with `actions/cache`, so OpenSSL is only rebuilt when vcpkg or the runner image changes. No-op on Linux and macOS.

```yaml
- uses: amqp-rs/actions/openssl-vcpkg@main
```

### `windows-setup-tls-env`

Combines `aws-lc-sys-deps`, `openssl-vcpkg`, and `openssl-no-vendor` in one step. Use this for crates that need all three (e.g. `amq-protocol`, `tcp-stream`, `lapin`). Vendoring is only disabled on Windows, so on Linux and macOS the build jobs compile, link and test the `vendored-openssl` feature.

```yaml
- uses: amqp-rs/actions/windows-setup-tls-env@main
```

## Reusable workflows

The composite actions above cannot hold job-level settings: the runner, the
matrix, `fail-fast`, the nightly `continue-on-error`, or which job of the
security audit may open issues. The reusable workflows in
`.github/workflows/` hold them, so a crate's workflow file only keeps its
triggers and calls one job:

```yaml
jobs:
  lint:
    uses: amqp-rs/actions/.github/workflows/reusable-lint.yml@main
```

| Workflow | Jobs | Inputs |
|---|---|---|
| `reusable-actionlint.yml` | `actionlint` | none |
| `reusable-lint.yml` | `lint` | none |
| `reusable-semver.yml` | `semver` | none |
| `reusable-security.yml` | `audit` on push and pull request, `scheduled-audit` on schedule | none |
| `reusable-build.yml` | `build`, over the standard matrix | see below |

`reusable-build.yml` runs the `build` action on stable for Linux, Windows and
macOS, and on nightly, beta and the MSRV for Linux. Nightly failures do not
fail the run, and one failing entry does not cancel the others.

| Input | Default | Notes |
|---|---|---|
| `setup` | none | Setup action to run first: `aws-lc-sys-deps`, `openssl-vcpkg` or `windows-setup-tls-env` |
| `check`, `test` | `true` | As for the `build` action |
| `test-features`, `test-runs`, `test-args` | none | As for the `build` action, on every matrix entry |
| `linux-stable-test-features`, `linux-stable-test-runs` | none | Added on Linux stable only, for tests that depend on neither the OS nor the toolchain |
| `rustflags` | none | The job's `RUSTFLAGS`, to which the `build` action appends `-D warnings` |
| `timeout-minutes` | `60` | Job timeout, so that a hung run fails long before GitHub's 360 minutes |

The composite actions stay available. Use them directly in a job that needs
a service, another target or steps of its own: lapin's RabbitMQ `test` job,
rustls-connector's `android` job and amq-protocol's lint job, which checks
its generated code after the `lint` action. The workflow's timeout does not
cover such a job: it keeps GitHub's 360 minutes unless it sets
`timeout-minutes` itself.

Constraints of called workflows:

- Triggers stay in the caller: a called workflow cannot set `on:`. It sees
  the caller's `github.event_name`, which is how the security workflow picks
  its job.
- A called workflow can only narrow the token its calling job grants, and
  the caller has to grant every scope that a job of the called workflow
  declares: GitHub refuses to start a run whose nested job asks for more.
  The read-only workflows need `contents: read`; the calling job of the
  security workflow grants `contents: read`, `checks: write` and
  `issues: write`, and each job of the called workflow keeps what it needs.
- A caller's workflow-level `env` does not reach a called workflow, and a
  job that calls one cannot have an `env` of its own: only inputs get
  through. `reusable-build.yml` takes `rustflags` for that reason; any
  other variable needs a new input, or a job that uses the `build` action
  directly.
- Check runs are named `<calling job> / <called job>`, such as `lint / lint`.
  Rename them in a repository's required status checks when it moves to a
  reusable workflow.
- A called workflow resolves `./` in the caller's checkout, so these
  workflows reference the actions as `amqp-rs/actions/<name>@main`, also
  when this repository's self-test calls them.

## Versioning: reference `@main`, do not pin

Consumers reference these actions as `amqp-rs/actions/<name>@main`, and the reusable workflows as `amqp-rs/actions/.github/workflows/<file>@main`, not by commit SHA or tag. This is on purpose. The amqp-rs maintainers own this repository, and it exists to synchronize action bumps across all amqp-rs repositories. A change merged here, such as a new major of `actions/checkout`, reaches every crate's CI at once. Pinning consumers would mean the same bump in every repository again.

Inside this repository, third-party actions are referenced by major tag (e.g. `actions/checkout@v7`) and kept current by this repository's Dependabot config. Two kinds of dependency are outside that loop:

- `dtolnay/rust-toolchain` picks the toolchain from the ref, so it is referenced by branch (`@master` with an explicit toolchain, `@stable` otherwise), as its README recommends, rather than by version tag. Dependabot never updates branch refs, so upstream changes reach CI without a pull request.
- Tools installed through an action input are invisible to Dependabot. `actionlint` is pinned to an exact version and bumped by hand, because a new release can add checks. `cargo-hack` is requested as `0.6`, which `taiki-e/install-action` resolves to the latest 0.6.x; moving to a new minor is done by hand.

Consumer repositories therefore only need Dependabot for `cargo`.

## Workflow token permissions

The composite actions use the calling job's `GITHUB_TOKEN` and cannot set its
permissions themselves. The reusable workflows declare them per job, within
what their caller grants. Declare the scopes in the caller workflow or job.
When any `permissions` are declared, GitHub sets every unlisted scope to `none`.

| Job | Required `permissions` |
|---|---|
| Checkout, actionlint, build, lint, semver, TLS setup | `contents: read` |
| Security on push or pull request | `contents: read`, `checks: write` |
| Security on schedule | `contents: read`, `checks: write`, `issues: write` |

The security action runs `rustsec/audit-check`, which publishes a check run and
can create issues during a scheduled audit. Keep `issues: write`
limited to the scheduled job. GitHub may still give forked pull requests a
read-only token, regardless of the requested scopes.

For example, give the read-only workflows a top-level block:

```yaml
permissions:
  contents: read
```

For the security workflow, call `reusable-security.yml`, which has one job per
row above, from a job that grants all three scopes; the called workflow
narrows the grant for each job. A grant that leaves out a scope one of its
jobs declares does not narrow that job: GitHub refuses to start the run.

```yaml
jobs:
  security:
    permissions:
      contents: read
      checks: write
      issues: write
    uses: amqp-rs/actions/.github/workflows/reusable-security.yml@main
```

## Typical workflow patterns

### Triggers

```yaml
on:
  push:
    branches:
      - main
  pull_request:

permissions:
  contents: read
```

Do not add a `tags:` push trigger: a release tag points at a commit that the push to its branch already built, so it only runs every workflow a second time. Do not add a `concurrency` block either: the runs of a branch would wait for each other, and GitHub cancels a waiting run when a newer one arrives, so a push to `main` quickly followed by another would end without a result. The build and security workflows also run on a weekly `schedule`.

### Standard crate

```yaml
jobs:
  build_and_test:
    uses: amqp-rs/actions/.github/workflows/reusable-build.yml@main
```

### Crate with a TLS environment

`aws-lc-sys-deps` for the rustls / aws-lc-rs backend (rustls-connector),
`openssl-vcpkg` for OpenSSL (async-openssl), `windows-setup-tls-env` for all
of them (amq-protocol, tcp-stream, lapin):

```yaml
jobs:
  build_and_test:
    uses: amqp-rs/actions/.github/workflows/reusable-build.yml@main
    with:
      setup: windows-setup-tls-env
      # Extra feature sets, and a run that only Linux stable needs
      test-features: |
        native-tls-futures,tokio
        openssl-futures,smol
      linux-stable-test-runs: -p amq-protocol-tcp --no-default-features
```

### Crate requiring a service for tests (e.g. lapin + RabbitMQ)

Split into two jobs: `check` calls the reusable workflow and runs only the
tests that need no broker, selected through `test-args`, and `test` runs
Linux-only with the service, using the `build` action directly:

```yaml
jobs:
  check:
    uses: amqp-rs/actions/.github/workflows/reusable-build.yml@main
    with:
      setup: windows-setup-tls-env
      # Only the test job has the broker: run the unit tests and the test
      # files named *_mock, which need none
      test-args: |
        --lib
        --test *_mock

  test:
    runs-on: ubuntu-latest
    # The reusable workflow's timeout does not cover this job
    timeout-minutes: 60
    continue-on-error: ${{ matrix.rust == 'nightly' }}
    services:
      rabbitmq:
        image: rabbitmq:latest
        ports:
          - 5672:5672
    strategy:
      fail-fast: false
      matrix:
        rust: [nightly, beta, stable, msrv]
        include:
          # A configuration that needs no broker and does not depend on the toolchain
          - rust: stable
            test-runs: --no-default-features
    steps:
      - uses: amqp-rs/actions/checkout@main
      - uses: amqp-rs/actions/build@main
        with:
          rust: ${{ matrix.rust }}
          check: 'false'
          test-runs: ${{ matrix.test-runs }}
```
