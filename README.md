# actions

Shared [composite GitHub Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) for the [amqp-rs](https://github.com/amqp-rs) ecosystem.

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
    test-args: ''  # optional: extra cargo test arguments, e.g. --lib
```

| Input | Default | Description |
|---|---|---|
| `rust` | `stable` | Toolchain to install (`stable`, `nightly`, `beta`, `msrv`, or an explicit version such as `1.88.0`); `msrv` reads `rust-version` with `cargo metadata` and fails unless the workspace declares exactly one |
| `check` | `true` | Run `cargo hack check --each-feature --workspace --all-targets`; on `stable`, also again with `--no-dev-deps` to catch features that only dev-dependencies enable; on `beta` and `nightly`, only `cargo check` with `--all-features` and with `--no-default-features` |
| `test` | `true` | Run `cargo test` |
| `test-features` | empty | Extra feature sets to test, one per line; each runs `cargo test --no-default-features --features <set>` after the default-features run |
| `test-args` | empty | Extra arguments for every `cargo test` run, e.g. `--lib` to run only unit tests where integration tests need a service, or `-p <package>` in a virtual workspace |

Build caches are saved for every toolchain except `nightly`: a new nightly ships every day and the cache key includes it, so a saved nightly cache could only ever serve reruns.

For the rest of the job, the action exports `RUSTUP_TOOLCHAIN` (so a `rust-toolchain.toml` cannot silently swap the matrix toolchain) and appends `-D warnings` to `RUSTFLAGS`. On toolchains older than stable it also appends `-A unknown_lints`, so an `allow` for a lint newer than the MSRV does not fail the build. Pass extra rustflags through a job-level `RUSTFLAGS`: they are kept, whereas `.cargo/config.toml` rustflags are ignored by cargo once `RUSTFLAGS` is set.

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

## Versioning: reference `@main`, do not pin

Consumers reference these actions as `amqp-rs/actions/<name>@main`, not by commit SHA or tag. This is on purpose. The amqp-rs maintainers own this repository, and it exists to synchronize action bumps across all amqp-rs repositories. A change merged here, such as a new major of `actions/checkout`, reaches every crate's CI at once. Pinning consumers would mean the same bump in every repository again.

Inside this repository, third-party actions are referenced by major tag (e.g. `actions/checkout@v7`). They are kept current by this repository's Dependabot config, so the consumer repositories configure Dependabot for `cargo` only.

## Workflow token permissions

These are composite actions: they use the calling job's `GITHUB_TOKEN` and cannot
set its permissions themselves. Declare the scopes in the caller workflow or job.
When any `permissions` are declared, GitHub sets every unlisted scope to `none`.

| Calling workflow | Required `permissions` |
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

For the security workflow, use separate jobs with the event filters and
permissions shown in the [crate workflows](https://github.com/amqp-rs/async-openssl/blob/main/.github/workflows/security.yaml).

## Typical workflow patterns

### Standard crate (rustls / aws-lc-rs backend)

```yaml
steps:
  - uses: amqp-rs/actions/checkout@main
  - uses: amqp-rs/actions/aws-lc-sys-deps@main
  - uses: amqp-rs/actions/build@main
    with:
      rust: ${{ matrix.rust }}
```

### Crate with full TLS environment (amq-protocol, tcp-stream, lapin)

```yaml
steps:
  - uses: amqp-rs/actions/checkout@main
  - uses: amqp-rs/actions/windows-setup-tls-env@main
  - uses: amqp-rs/actions/build@main
    with:
      rust: ${{ matrix.rust }}
```

### OpenSSL crate

```yaml
steps:
  - uses: amqp-rs/actions/checkout@main
  - uses: amqp-rs/actions/openssl-vcpkg@main
  - uses: amqp-rs/actions/build@main
    with:
      rust: ${{ matrix.rust }}
```

### Crate requiring a service for tests (e.g. lapin + RabbitMQ)

Split into two jobs — `check` runs cross-platform, `test` runs Linux-only with the service:

```yaml
jobs:
  check:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        rust: [stable]
        include:
          - { os: ubuntu-latest, rust: nightly }
          - { os: ubuntu-latest, rust: beta }
          - { os: ubuntu-latest, rust: msrv }
    steps:
      - uses: amqp-rs/actions/checkout@main
      - uses: amqp-rs/actions/build@main
        with:
          rust: ${{ matrix.rust }}
          test: 'false'

  test:
    runs-on: ubuntu-latest
    services:
      rabbitmq:
        image: rabbitmq:latest
        ports:
          - 5672:5672
    strategy:
      matrix:
        rust: [nightly, beta, stable, msrv]
    steps:
      - uses: amqp-rs/actions/checkout@main
      - uses: amqp-rs/actions/build@main
        with:
          rust: ${{ matrix.rust }}
          check: 'false'
```
