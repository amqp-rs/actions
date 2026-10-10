//! Fixture crate for the amqp-rs/actions self-test workflow.
//!
//! The workflow copies it to the workspace root, so that the `build` and
//! `lint` actions run on it exactly as they do on a consumer crate.

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
