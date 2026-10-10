# TODO

## Ship reusable workflows for job-level CI policy

This repository only ships composite actions, which cannot hold job-level
settings: permissions, matrix shape, `fail-fast`, nightly
`continue-on-error`, services, or the push/schedule split of the security
audit. Every consumer therefore copies that policy into its own workflow
files, and copies drift:

- At the time of writing, `actionlint.yml` was byte-identical in 6 of the 7
  amqp-rs repositories and `lint`/`semver`/`security.yaml` in 5 of the 6
  consumers. The outlier, amq-protocol, still lacked the "scope CI workflow
  token permissions" change the others got as six separate commits.
- The README's lapin pattern had drifted from lapin's real workflow
  (missing `windows-setup-tls-env`, nightly `continue-on-error` and
  `fail-fast: false`).

Reusable `on: workflow_call` workflows in `.github/workflows/` would let
consumers call one definition, matching the "bump once here" rationale of
the Versioning section in `README.md`:

- `actionlint`, `lint`, `semver`: one job each, `contents: read`.
- `security`: the push/pull request job (`checks: write`) and the scheduled
  job (`issues: write`), selected on `github.event_name`.
- `build`: the standard matrix (stable on ubuntu/windows/macos, plus
  nightly/beta/msrv on ubuntu, nightly `continue-on-error`,
  `fail-fast: false`) with inputs for the TLS setup action to run, `test`,
  `test-features` and `test-args`. lapin's RabbitMQ `test` job may stay in
  its own workflow, since services cannot be made conditional cleanly.

Constraints to keep in mind:

- Triggers (`on:`) stay in each consumer; a called workflow cannot set them.
- A caller can only downgrade the permissions a called workflow requests.
- Consumers have to be migrated one by one, and the workflows cannot be
  exercised before they are pushed (the self-test workflow could call them
  on the fixture crate once they exist).
