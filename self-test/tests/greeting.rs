#[test]
fn greets() {
    assert!(amqp_rs_actions_fixture::greeting().eq_ignore_ascii_case("hello"));
}
