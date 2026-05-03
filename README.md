# actions

Shared [composite GitHub Actions](https://docs.github.com/en/actions/sharing-automations/creating-actions/creating-a-composite-action) for the [amqp-rs](https://github.com/amqp-rs) ecosystem.

## Available actions

### `actionlint`

Lints GitHub Actions workflow files with [`actionlint`](https://github.com/rhysd/actionlint).

```yaml
- uses: actions/checkout@v6
- uses: amqp-rs/actions/actionlint@main
```

### `lint`

Runs clippy, rustfmt, and doc checks on stable Rust.

```yaml
- uses: actions/checkout@v6
- uses: amqp-rs/actions/lint@main
```

### `security`

Runs `cargo audit` via the [RustSec advisory database](https://rustsec.org/).

```yaml
- uses: actions/checkout@v6
- uses: amqp-rs/actions/security@main
```

### `semver`

Checks semver compliance with [`cargo-semver-checks`](https://github.com/obi1kenobi/cargo-semver-checks).

```yaml
- uses: actions/checkout@v6
- uses: amqp-rs/actions/semver@main
```

### `build`

Installs a Rust toolchain, sets up build caching, and runs `cargo check` and `cargo test` with `RUSTFLAGS=-D warnings`.

```yaml
- uses: actions/checkout@v6
- uses: amqp-rs/actions/build@main
  with:
    rust: stable   # any rustup toolchain string; default: stable
    check: 'true'  # set to 'false' to skip cargo check steps
    test: 'true'   # set to 'false' to skip cargo test
```

| Input | Default | Description |
|---|---|---|
| `rust` | `stable` | Toolchain to install (`stable`, `nightly`, `beta`, or an MSRV such as `1.88.0`) |
| `check` | `true` | Run `cargo check --all --bins --examples --tests --all-features` (and the nightly `-Z features=dev_dep` variant) |
| `test` | `true` | Run `cargo test` |

### `aws-lc-sys-deps`

Installs NASM and ninja-build on Windows, required by `aws-lc-rs` and `aws-lc-fips-sys`. No-op on Linux and macOS.

```yaml
- uses: amqp-rs/actions/aws-lc-sys-deps@main
```

### `openssl-no-vendor`

Sets `OPENSSL_NO_VENDOR=1` to prevent `openssl-sys` from building a bundled OpenSSL.

```yaml
- uses: amqp-rs/actions/openssl-no-vendor@main
```

### `openssl-vcpkg`

Sets `VCPKG_ROOT` and installs `openssl:x64-windows-static-md` via vcpkg on Windows. No-op on Linux and macOS.

```yaml
- uses: amqp-rs/actions/openssl-vcpkg@main
```

## Typical workflow patterns

### Standard crate (rustls / aws-lc-rs backend)

```yaml
steps:
  - uses: actions/checkout@v6
  - uses: amqp-rs/actions/aws-lc-sys-deps@main
  - uses: amqp-rs/actions/build@main
    with:
      rust: ${{ matrix.rust }}
```

### OpenSSL crate

```yaml
steps:
  - uses: actions/checkout@v6
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
          - { os: ubuntu-latest, rust: 1.88.0 }
    steps:
      - uses: actions/checkout@v6
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
        rust: [nightly, beta, stable, 1.88.0]
    steps:
      - uses: actions/checkout@v6
      - uses: amqp-rs/actions/build@main
        with:
          rust: ${{ matrix.rust }}
          check: 'false'
```
