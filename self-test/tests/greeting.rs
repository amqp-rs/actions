use std::{env, fs::OpenOptions, io::Write};

#[test]
fn greets() {
    let greeting = amqp_rs_actions_fixture::greeting();
    assert!(greeting.eq_ignore_ascii_case("hello"));
    // The self-test workflow reads this file to see which test runs got here.
    if let Some(path) = env::var_os("FIXTURE_GREETINGS") {
        let mut greetings = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .unwrap();
        writeln!(greetings, "{greeting}").unwrap();
    }
}
