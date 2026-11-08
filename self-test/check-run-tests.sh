#!/usr/bin/env bash
# Checks the cargo invocations of build/run-tests.sh, and what it prints,
# against a stub cargo, which records its arguments, prints a line on each
# stream and fails when one of the arguments is FAILME.
set -euo pipefail
cd "$(dirname "$0")/.."
stub=$(mktemp -d)
trap 'rm -rf "$stub"' EXIT
cat > "$stub/cargo" <<'STUB'
#!/usr/bin/env bash
printf '[%s]' "$@" >> "$STUB_LOG"
echo >> "$STUB_LOG"
echo "out: $*"
echo "err: $*" >&2
for arg in "$@"; do [ "$arg" != FAILME ] || exit 101; done
STUB
chmod +x "$stub/cargo"
export STUB_LOG=$stub/log

run() {
  : > "$STUB_LOG"
  PATH="$stub:$PATH" TEST_ARGS=$1 TEST_FEATURES=$2 TEST_RUNS=$3 bash build/run-tests.sh > "$stub/output" 2>&1
}
# The differences are quoted, so that the runner does not take a line of
# them for a workflow command.
same() {
  diff -u "$1" "$2" | sed 's/^/| /'
}
expect() {
  same <(printf '%s\n' "$@") "$STUB_LOG"
}

# test-args' harness arguments go after each run's own, behind a single --
run '--lib -- --test-threads=1' 'a b' $'-p y -- --ignored\n\n-p z'
expect \
  '[test][--locked][--no-fail-fast][--lib][--][--test-threads=1]' \
  '[test][--locked][--no-fail-fast][--lib][--no-default-features][--features][a b][--][--test-threads=1]' \
  '[test][--locked][--no-fail-fast][--lib][-p][y][--][--ignored][--test-threads=1]' \
  '[test][--locked][--no-fail-fast][--lib][-p][z][--][--test-threads=1]'

# test-args may span several lines, each with its own harness arguments
run $'-- --test-threads=1\n--lib' '' ''
expect '[test][--locked][--no-fail-fast][--lib][--][--test-threads=1]'

# Only an argument that is -- separates the harness arguments: a feature set
# is a single argument
run '-- --test-threads=1' 'a -- b' ''
expect \
  '[test][--locked][--no-fail-fast][--][--test-threads=1]' \
  '[test][--locked][--no-fail-fast][--no-default-features][--features][a -- b][--][--test-threads=1]'

# --no-fail-fast is not repeated when test-args or a run has it among its
# cargo arguments
run '--no-fail-fast --lib' 'a' ''
expect \
  '[test][--locked][--no-fail-fast][--lib]' \
  '[test][--locked][--no-fail-fast][--lib][--no-default-features][--features][a]'
run '' '' $'-p y --no-fail-fast\n-p z -- --no-fail-fast'
expect \
  '[test][--locked][--no-fail-fast]' \
  '[test][--locked][-p][y][--no-fail-fast]' \
  '[test][--locked][--no-fail-fast][-p][z][--][--no-fail-fast]'

# A failed run fails the script, after the later runs, and its output is
# repeated after its log group
if run '' '' $'FAILME\n-p z'; then
  echo "::error::run-tests.sh passed although a run failed"
  exit 1
fi
expect \
  '[test][--locked][--no-fail-fast]' \
  '[test][--locked][--no-fail-fast][FAILME]' \
  '[test][--locked][--no-fail-fast][-p][z]'
same - "$stub/output" <<'OUTPUT'
::group::cargo test --locked --no-fail-fast
out: test --locked --no-fail-fast
err: test --locked --no-fail-fast
::endgroup::
::group::cargo test --locked --no-fail-fast FAILME
out: test --locked --no-fail-fast FAILME
err: test --locked --no-fail-fast FAILME
::endgroup::
out: test --locked --no-fail-fast FAILME
err: test --locked --no-fail-fast FAILME
::group::cargo test --locked --no-fail-fast -p z
out: test --locked --no-fail-fast -p z
err: test --locked --no-fail-fast -p z
::endgroup::
::error::cargo test --locked --no-fail-fast FAILME failed
OUTPUT
echo "run-tests.sh: ok with bash $(bash -c 'echo "$BASH_VERSION"')"
