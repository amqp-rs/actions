//! Fixture crate for the amqp-rs/actions self-test workflow.
//!
//! It is the only member of the workspace at the repository root, so that the
//! `build` and `lint` actions, and the reusable workflows, run on it as they
//! do on a consumer crate.

/// Returns the fixture's greeting, which the `shout` feature turns upper case.
#[must_use]
pub fn greeting() -> &'static str {
    if cfg!(feature = "shout") {
        "HELLO"
    } else {
        "hello"
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn greeting_follows_features() {
        let expected = if cfg!(feature = "shout") {
            "HELLO"
        } else {
            "hello"
        };
        assert_eq!(super::greeting(), expected);
    }
}
