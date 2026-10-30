use super::*;

fn switch(selection: &SelectedServer, base: Option<&str>) -> Option<u64> {
    selection
        .begin_switch(base)
        .unwrap()
        .map(|pending| selection.finish_switch(pending))
}

#[test]
fn selection_lifecycle_bumps_the_generation_only_on_change() {
    let selection = SelectedServer::new();
    assert_eq!(selection.base(), None);

    assert_eq!(switch(&selection, Some("https://a.example/")), Some(1));
    assert_eq!(selection.base().as_deref(), Some("https://a.example"));
    assert_eq!(
        switch(&selection, Some("HTTPS://A.EXAMPLE")),
        None,
        "re-applying the same base keeps sessions"
    );

    assert!(selection.begin_switch(Some("http://b.example")).is_err());
    assert_eq!(selection.base().as_deref(), Some("https://a.example"));
    assert!(
        !selection.cleanup_pending(),
        "an invalid base changes nothing"
    );
    assert_eq!(switch(&selection, Some("https://b.example")), Some(3));

    assert_eq!(switch(&selection, None), Some(4));
    assert_eq!(selection.base(), None);
    assert_eq!(switch(&selection, None), None);
}

#[test]
fn an_unfinished_switch_leaves_no_server_and_is_retried() {
    let selection = SelectedServer::new();
    assert!(switch(&selection, Some("https://a.example")).is_some());

    // Cleanup for B fails: the switch is never finished.
    let abandoned = selection.begin_switch(Some("https://b.example")).unwrap();
    assert!(abandoned.is_some());
    drop(abandoned);
    assert_eq!(selection.base(), None, "neither the old nor the new server");
    assert!(selection.cleanup_pending());

    // The same base again is a new switch, not a no-op.
    let retry = selection.begin_switch(Some("https://b.example")).unwrap();
    let retry = retry.expect("a retry after a failed cleanup runs it again");
    selection.finish_switch(retry);
    assert_eq!(selection.base().as_deref(), Some("https://b.example"));
    assert!(!selection.cleanup_pending());
    assert_eq!(switch(&selection, Some("https://b.example")), None);
}
