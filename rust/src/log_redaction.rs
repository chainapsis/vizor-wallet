//! The process logger: masks identifier-shaped values in every Rust log record
//! and panic report before they reach the platform log.
//!
//! This is a safety net, not a privacy contract. It recognises values only by
//! their shape: addresses, viewing and spending keys, 32-byte hashes, UUIDs,
//! absolute device paths, URL paths and queries, payment URIs and Keystone URs.
//! Amounts, balances, account names, labels, memos, seed words and other free
//! text pass through unchanged and have to be kept out at the call site.
//!
//! The rules and their order mirror `lib/src/core/logging/log_redaction.dart`,
//! and both test suites run `test/fixtures/log_redaction_vectors.json`.

use std::backtrace::{Backtrace, BacktraceStatus};
use std::borrow::Cow;
use std::io::Write;
use std::sync::{LazyLock, Once};

use log::{Log, Metadata, Record};
use regex::{Captures, Regex, Replacer};

/// Installs the redacting logger and panic hook once per process.
///
/// This replaces `flutter_rust_bridge::setup_default_user_utils`: the logger
/// forwards to the same backend FRB 2.11.1 would have installed (os_log
/// subsystem `frb_user` on Apple platforms, logcat on Android, none on other
/// desktops), and the panic hook keeps FRB's backtrace capture.
pub(crate) fn install() {
    static INSTALL: Once = Once::new();
    INSTALL.call_once(|| {
        if let Some(backend) = platform_backend() {
            // Another logger already installed keeps running; logging setup
            // must never take down the app.
            let _ = log::set_boxed_logger(Box::new(RedactingLogger::new(backend)));
        }
        install_panic_hook();
    });
}

/// Redacts `text` until it stops changing, so the result is idempotent.
/// Text without anything to mask is returned borrowed.
pub(crate) fn redact(text: &str) -> Cow<'_, str> {
    let mut current = Cow::Borrowed(text);
    for _ in 0..MAX_PASSES {
        let next = match redact_once(&current) {
            Cow::Owned(next) => next,
            Cow::Borrowed(_) => break,
        };
        current = Cow::Owned(next);
    }
    current
}

/// A logger that redacts each record's message, then hands the record, with
/// its level, target, module path and location unchanged, to `inner`.
pub(crate) struct RedactingLogger<L> {
    inner: L,
}

impl<L> RedactingLogger<L> {
    pub(crate) fn new(inner: L) -> Self {
        Self { inner }
    }
}

impl<L: Log> Log for RedactingLogger<L> {
    fn enabled(&self, metadata: &Metadata) -> bool {
        self.inner.enabled(metadata)
    }

    fn log(&self, record: &Record) {
        if !self.inner.enabled(record.metadata()) {
            return;
        }
        let message = match record.args().as_str() {
            Some(message) => Cow::Borrowed(message),
            None => Cow::Owned(record.args().to_string()),
        };
        let message = redact(&message);
        self.inner.log(
            &Record::builder()
                .args(format_args!("{message}"))
                .metadata(record.metadata().clone())
                .module_path(record.module_path())
                .file(record.file())
                .line(record.line())
                .build(),
        );
    }

    fn flush(&self) {
        self.inner.flush();
    }
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
fn platform_backend() -> Option<Box<dyn Log>> {
    // `new` only; `level_filter` would also change the global max level.
    Some(Box::new(oslog::OsLogger::new("frb_user")))
}

#[cfg(target_os = "android")]
fn platform_backend() -> Option<Box<dyn Log>> {
    Some(Box::new(android_logger::AndroidLogger::new(
        android_logger::Config::default().with_max_level(log::LevelFilter::Trace),
    )))
}

#[cfg(not(any(target_os = "ios", target_os = "macos", target_os = "android")))]
fn platform_backend() -> Option<Box<dyn Log>> {
    None
}

fn install_panic_hook() {
    // FRB's default utils turn backtraces on unless the host already chose.
    // Apps are never launched with RUST_BACKTRACE, and release builds read no
    // environment switches (see the `enhancement::policy` source guard), so
    // only debug builds keep a host setting.
    let host_chose = cfg!(debug_assertions) && std::env::var_os("RUST_BACKTRACE").is_some();
    if !host_chose {
        std::env::set_var("RUST_BACKTRACE", "1");
    }
    // Replaces the std hook, which writes the same report to stderr verbatim.
    std::panic::set_hook(Box::new(|info| {
        let payload = info.payload();
        let message = payload
            .downcast_ref::<&str>()
            .copied()
            .or_else(|| payload.downcast_ref::<String>().map(String::as_str))
            .unwrap_or("Box<dyn Any>");
        let location = info.location().map(ToString::to_string).unwrap_or_default();
        let backtrace = Backtrace::capture();
        let backtrace =
            (backtrace.status() == BacktraceStatus::Captured).then(|| backtrace.to_string());
        let thread = std::thread::current();
        let report = panic_report(
            thread.name().unwrap_or("<unnamed>"),
            &location,
            message,
            backtrace.as_deref(),
        );
        let _ = std::io::stderr().write_all(report.as_bytes());
    }));
    // FRB wraps the hook above: it records the backtrace for the Dart
    // `PanicException`, then calls it.
    flutter_rust_bridge::PanicBacktrace::setup();
}

fn panic_report(thread: &str, location: &str, message: &str, backtrace: Option<&str>) -> String {
    let mut report = format!("thread '{thread}' panicked at {location}:\n{message}\n");
    if let Some(backtrace) = backtrace {
        report.push_str("stack backtrace:\n");
        report.push_str(backtrace);
        report.push('\n');
    }
    redact(&report).into_owned()
}

// A pass only replaces values with tokens, so a second pass finishes any match
// a token made possible. The bound is a backstop, not an expected depth.
const MAX_PASSES: usize = 4;

// Zakura protocol HRPs (zakura-protocol 3.0.0 constants/{mainnet,testnet,
// regtest}.rs). Ironwood shares the Orchard receiver, so it has no HRP of its
// own. Longer prefixes come first.
const KEY_HRPS: &[&str] = &[
    "secret-extended-key-regtest",
    "secret-extended-key-main",
    "secret-extended-key-test",
    "zxviewregtestsapling",
    "zxviewtestsapling",
    "uviewregtest",
    "uivkregtest",
    "uviewtest",
    "uivktest",
    "zxviews",
    "uview",
    "uivk",
];
const ADDRESS_HRPS: &[&str] = &[
    "zregtestsapling",
    "ztestsapling",
    "texregtest",
    "uregtest",
    "textest",
    "utest",
    "tex",
    "zs",
    "u",
];
const BECH32_CHARSET: &str = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
// The shortest encoding above is a TEX address: 20 bytes, 38 characters.
const BECH32_MIN_DATA: usize = 38;
// Base58Check prefixes 0x1cb8/0x1cbd (mainnet), 0x1d25/0x1cba (test/regtest)
// encode as t1/t3 and tm/t2; every transparent address is 35 characters.
const TRANSPARENT: &str = r"(?:t1|t3|tm|t2)[1-9A-HJ-NP-Za-km-z]{33}";

// Explicit ASCII classes and `(?-u:\b)` keep Rust and Dart matching the same
// characters; the `regex` crate's defaults are Unicode-aware.
const SPACE: &str = r"\t\n\v\f\r ";
const NOT_ALNUM: &str = r"[^0-9A-Za-z]";
const PATH_START: &str = r"(^|file://|[^0-9A-Za-z_.~/\\\-])";
const UNIX_ROOTS: &str =
    "Users|home|root|private|var|tmp|data|storage|sdcard|mnt|media|Volumes|run";

struct Rules {
    url: Regex,
    windows_path: Regex,
    unix_path: Regex,
    uuid: Regex,
    hex: Regex,
    opaque_uri: Regex,
    key: Regex,
    address: Regex,
}

static RULES: LazyLock<Rules> = LazyLock::new(|| {
    let rule = |pattern: String| Regex::new(&pattern).expect("log redaction pattern");
    let path_char = format!(r#"[^{SPACE}'"<>|:;,()\[\]{{}}\\]"#);
    Rules {
        url: rule(format!(
            r#"(?-u:\b)([A-Za-z][A-Za-z0-9+.\-]*://)(?:[^{SPACE}/?#@'"<>]*@)?([^{SPACE}/?#'"<>]+)([/?#][^{SPACE}'"<>]+)?"#
        )),
        windows_path: rule(format!(
            r#"{PATH_START}([A-Za-z]:[\\/][^{SPACE}'"<>|:;,()\[\]{{}}]*)"#
        )),
        unix_path: rule(format!(
            r"{PATH_START}(/(?:{UNIX_ROOTS})/(?:/Application Support|{path_char})*)"
        )),
        uuid: rule(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}".into(),
        ),
        hex: rule("(?:0[xX])?[0-9a-fA-F]{32,}".into()),
        // Match both opaque payloads together so an embedded URI cannot be
        // replaced before its enclosing URI. Group 1 identifies payment URIs.
        opaque_uri: rule(format!(
            r#"(?-u:\b)(?:([zZ][cC][aA][sS][hH]:)|[uU][rR]:[A-Za-z0-9\-]+/)[^{SPACE}'"<>]+"#
        )),
        key: rule(format!("({NOT_ALNUM}|^){}", bech32(KEY_HRPS))),
        address: rule(format!(
            "({NOT_ALNUM}|^)(?:{}|{TRANSPARENT})",
            bech32(ADDRESS_HRPS)
        )),
    }
});

fn bech32(hrps: &[&str]) -> String {
    let lower = hrps.join("|");
    let upper = hrps.join("|").to_ascii_uppercase();
    let upper_charset = BECH32_CHARSET.to_ascii_uppercase();
    format!(
        "(?:(?:{lower})1[{BECH32_CHARSET}]{{{BECH32_MIN_DATA},}}|(?:{upper})1[{upper_charset}]{{{BECH32_MIN_DATA},}})"
    )
}

fn redact_once(text: &str) -> Cow<'_, str> {
    let rules = &*RULES;
    let text = Cow::Borrowed(text);
    // Component replacements introduce '<' tokens that would truncate a URI.
    let text = replace(text, &rules.opaque_uri, |caps: &Captures| {
        if caps.get(1).is_some() {
            "<payment-uri>"
        } else {
            "<ur>"
        }
    });
    let text = replace(text, &rules.url, |caps: &Captures| {
        let path = if caps.get(3).is_some() { "/<path>" } else { "" };
        format!("{}{}{path}", &caps[1], &caps[2])
    });
    // Drive paths first, so `C:/Users/...` is not read as a POSIX path.
    let text = replace(text, &rules.windows_path, "${1}<path>");
    let text = replace(text, &rules.unix_path, "${1}<path>");
    let text = replace(text, &rules.uuid, "<uuid>");
    let text = replace(text, &rules.hex, |caps: &Captures| {
        let value = &caps[0];
        // The pattern only admits an `x` as the second character of `0x`.
        let prefixed = matches!(value.as_bytes()[1], b'x' | b'X');
        let digits = value.len() - if prefixed { 2 } else { 0 };
        if digits == 64 {
            "<txid>"
        } else {
            "<hex>"
        }
    });
    let text = replace(text, &rules.key, "${1}<key>");
    replace(text, &rules.address, "${1}<address>")
}

fn replace<'a>(text: Cow<'a, str>, regex: &Regex, replacement: impl Replacer) -> Cow<'a, str> {
    let replaced = match regex.replace_all(&text, replacement) {
        Cow::Owned(replaced) => Some(replaced),
        Cow::Borrowed(_) => None,
    };
    match replaced {
        Some(replaced) => Cow::Owned(replaced),
        None => text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use log::Level;
    use std::sync::Mutex;

    /// Shared with `test/core/logging/log_redaction_test.dart`.
    const VECTORS: &str = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../test/fixtures/log_redaction_vectors.json"
    );

    #[derive(serde::Deserialize)]
    struct Vectors {
        cases: Vec<Case>,
    }

    #[derive(serde::Deserialize)]
    struct Case {
        name: String,
        input: String,
        expected: String,
    }

    fn cases() -> Vec<Case> {
        let json = std::fs::read_to_string(VECTORS).expect("shared log redaction vectors");
        serde_json::from_str::<Vectors>(&json)
            .expect("vectors parse")
            .cases
    }

    #[test]
    fn shared_vectors_redact_to_expected() {
        let cases = cases();
        assert!(cases.len() > 50, "vectors loaded");
        let failures: Vec<String> = cases
            .iter()
            .filter(|case| redact(&case.input) != case.expected)
            .map(|case| {
                format!(
                    "{}:\n  got      {}\n  expected {}",
                    case.name,
                    redact(&case.input),
                    case.expected
                )
            })
            .collect();
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[test]
    fn redaction_is_idempotent() {
        for case in cases() {
            let once = redact(&case.input).into_owned();
            assert_eq!(redact(&once), once, "{}", case.name);
            assert_eq!(redact(&case.expected), case.expected, "{}", case.name);
        }
    }

    #[test]
    fn text_without_identifiers_is_not_copied() {
        assert!(matches!(
            redact("[3.2s] sync: scanned 3201456..3201500 (44 blocks)"),
            Cow::Borrowed(_)
        ));
    }

    #[derive(Default)]
    struct Capture {
        max: Option<Level>,
        records: Mutex<Vec<(Level, String, Option<String>, Option<u32>, String)>>,
    }

    impl Log for Capture {
        fn enabled(&self, metadata: &Metadata) -> bool {
            self.max.is_none_or(|max| metadata.level() <= max)
        }

        fn log(&self, record: &Record) {
            self.records.lock().unwrap().push((
                record.level(),
                record.target().to_string(),
                record.module_path().map(str::to_string),
                record.line(),
                record.args().to_string(),
            ));
        }

        fn flush(&self) {}
    }

    // Records go straight to `Log::log`: this test binary already owns the
    // global logger (`enhancement::transport` tests install one).
    #[test]
    fn the_logger_redacts_before_it_forwards() {
        let logger = RedactingLogger::new(Capture::default());
        let txid = "9f1c2b3a4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f708192a3b4c5d6e7f8";
        let db = "/var/mobile/Containers/Data/Application/0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D/Library/Application Support/zcash_wallet_main.db";

        logger.log(
            &Record::builder()
                .args(format_args!(
                    "send: broadcast {txid} from {db} at height 3201456"
                ))
                .level(Level::Warn)
                .target("rust_lib_zcash_wallet::wallet::sync::send")
                .module_path(Some("rust_lib_zcash_wallet::wallet::sync::send"))
                .line(Some(6699))
                .build(),
        );

        let records = logger.inner.records.lock().unwrap();
        assert_eq!(
            *records,
            [(
                Level::Warn,
                "rust_lib_zcash_wallet::wallet::sync::send".to_string(),
                Some("rust_lib_zcash_wallet::wallet::sync::send".to_string()),
                Some(6699),
                "send: broadcast <txid> from <path> at height 3201456".to_string(),
            )]
        );
    }

    #[test]
    fn opaque_uri_vectors_are_fully_masked_by_logger_and_panic_report() {
        let logger = RedactingLogger::new(Capture::default());
        for case in cases().into_iter().filter(|case| {
            case.expected.contains("<payment-uri>") || case.expected.contains("<ur>")
        }) {
            logger.log(
                &Record::builder()
                    .args(format_args!("{}", case.input))
                    .level(Level::Warn)
                    .build(),
            );
            let records = logger.inner.records.lock().unwrap();
            assert_eq!(records.last().unwrap().4, case.expected, "{}", case.name);
            assert_eq!(
                panic_report("worker", "src/test.rs:1:1", &case.input, None),
                format!(
                    "thread 'worker' panicked at src/test.rs:1:1:\n{}\n",
                    case.expected
                ),
                "{}",
                case.name
            );
        }
    }

    #[test]
    fn the_logger_skips_records_the_backend_filters_out() {
        let logger = RedactingLogger::new(Capture {
            max: Some(Level::Info),
            ..Capture::default()
        });

        logger.log(
            &Record::builder()
                .args(format_args!("verbose"))
                .level(Level::Debug)
                .build(),
        );

        assert!(logger.inner.records.lock().unwrap().is_empty());
    }

    #[test]
    fn panic_reports_are_redacted() {
        let report = panic_report(
            "tokio-runtime-worker",
            "src/wallet/db.rs:459:5",
            "failed to open /data/user/0/com.keplr.vizor/app_flutter/zcash_wallet_main.db",
            Some("   0: rust_lib_zcash_wallet::wallet::db::open\n             at /Users/runner/work/vizor/rust/src/wallet/db.rs:459:5"),
        );

        assert_eq!(
            report,
            "thread 'tokio-runtime-worker' panicked at src/wallet/db.rs:459:5:\n\
             failed to open <path>\n\
             stack backtrace:\n   0: rust_lib_zcash_wallet::wallet::db::open\n             at <path>:459:5\n"
        );
    }
}
