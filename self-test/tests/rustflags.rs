//! Run by the self-test workflow, which passes `--cfg fixture_rustflags`
//! through the `RUSTFLAGS` of its build jobs.

#[test]
#[ignore = "needs RUSTFLAGS=\"--cfg fixture_rustflags\""]
fn rustflags_reach_rustc() {
    #[cfg(not(fixture_rustflags))]
    panic!("built without --cfg fixture_rustflags");
}
