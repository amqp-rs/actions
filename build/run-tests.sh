#!/usr/bin/env bash
# The build action's cargo test runs, configured through TEST_ARGS, TEST_FEATURES
# and TEST_RUNS (see the test-args, test-features and test-runs inputs).
set -eo pipefail

# test-args go before each run's own arguments, except the test harness
# arguments after a -- on each of its lines, which go after them: a
# test-runs line can then pass harness arguments too.
cargo_args=()
harness_args=()
while read -ra line; do
  harness=
  for arg in "${line[@]}"; do
    if [ -n "$harness" ]; then
      harness_args+=("$arg")
    elif [ "$arg" = -- ]; then
      harness=1
    else
      cargo_args+=("$arg")
    fi
  done
done <<< "$TEST_ARGS"
output=$(mktemp)
trap 'rm -f "$output"' EXIT
failed=()
run_tests() {
  # cargo refuses a flag given twice, and only one -- separates its
  # arguments from the harness's
  no_fail_fast=(--no-fail-fast)
  separator=(--)
  for arg in "${cargo_args[@]}" "$@"; do
    case $arg in
      --no-fail-fast) no_fail_fast=() ;;
      --) separator=(); break ;;
    esac
  done
  cmd=(cargo test --locked "${no_fail_fast[@]}" "${cargo_args[@]}" "$@")
  [ "${#harness_args[@]}" -eq 0 ] || cmd+=("${separator[@]}" "${harness_args[@]}")
  echo "::group::${cmd[*]}"
  if "${cmd[@]}" < /dev/null 2>&1 | tee "$output"; then
    echo "::endgroup::"
  else
    echo "::endgroup::"
    # Log groups are collapsed: a failed run's output is repeated after its own
    cat "$output"
    failed+=("${cmd[*]}")
  fi
}
run_tests
while read -r features; do
  [ -z "$features" ] || run_tests --no-default-features --features "$features"
done <<< "$TEST_FEATURES"
while read -ra run_args; do
  [ "${#run_args[@]}" -eq 0 ] || run_tests "${run_args[@]}"
done <<< "$TEST_RUNS"
for run in "${failed[@]}"; do
  echo "::error::$run failed"
done
[ "${#failed[@]}" -eq 0 ]
