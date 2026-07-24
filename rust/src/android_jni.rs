//! JNI adapter for Android Ironwood migration preparation.
//!
//! This module performs JNI conversion only. Operation ownership, sync
//! exclusion, cancellation, and preparation state interpretation remain in
//! `crate::migration_preparation`.

use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{Arc, Mutex};

use jni::objects::{JByteArray, JObject, JString, JValue};
use jni::sys::{jboolean, jobject, JNI_FALSE, JNI_TRUE};
use jni::{JNIEnv, JavaVM};
use zeroize::Zeroizing;

use crate::migration_preparation::{self, MigrationPreparationError, MigrationPreparationProgress};
use crate::wallet::network::WalletNetwork;

const RESULT_CLASS: &str = "com/keplr/vizor/IronwoodMigrationNativeCallResult";
const RESULT_SIGNATURE: &str = "(ILjava/lang/String;[J)V";
const SYNC_CALLBACK_METHOD: &str = "onProgress";
const SYNC_CALLBACK_SIGNATURE: &str = "(JJDDJZZZ)V";

const RESULT_SUCCESS: i32 = 0;
const RESULT_NO_ACTIVE_OPERATION: i32 = 1;
const RESULT_SYNC_ALREADY_RUNNING: i32 = 2;
const RESULT_INVALID_CREDENTIAL: i32 = 3;
const RESULT_EXECUTION: i32 = 4;
const RESULT_CALLBACK: i32 = 5;
const RESULT_PANIC: i32 = 6;
const RESULT_INVALID_ARGUMENT: i32 = 7;

struct NativeOutcome {
    code: i32,
    message: Option<String>,
    progress: Option<MigrationPreparationProgress>,
}

impl NativeOutcome {
    fn success() -> Self {
        Self {
            code: RESULT_SUCCESS,
            message: None,
            progress: None,
        }
    }

    fn progress(progress: MigrationPreparationProgress) -> Self {
        Self {
            code: RESULT_SUCCESS,
            message: None,
            progress: Some(progress),
        }
    }

    fn invalid_argument(message: impl Into<String>) -> Self {
        Self {
            code: RESULT_INVALID_ARGUMENT,
            message: Some(message.into()),
            progress: None,
        }
    }

    fn callback(message: impl Into<String>) -> Self {
        Self {
            code: RESULT_CALLBACK,
            message: Some(message.into()),
            progress: None,
        }
    }

    fn panic(context: &str, panic: Box<dyn std::any::Any + Send>) -> Self {
        let detail = if let Some(message) = panic.downcast_ref::<&str>() {
            (*message).to_string()
        } else if let Some(message) = panic.downcast_ref::<String>() {
            message.clone()
        } else {
            "Unknown panic".to_string()
        };
        log::error!("android_jni: panic during {context}: {detail}");
        Self {
            code: RESULT_PANIC,
            message: Some(format!("{context}: {detail}")),
            progress: None,
        }
    }
}

impl From<MigrationPreparationError> for NativeOutcome {
    fn from(error: MigrationPreparationError) -> Self {
        let code = match error {
            MigrationPreparationError::NoActiveOperation => RESULT_NO_ACTIVE_OPERATION,
            MigrationPreparationError::SyncAlreadyRunning => RESULT_SYNC_ALREADY_RUNNING,
            MigrationPreparationError::InvalidCredential => RESULT_INVALID_CREDENTIAL,
            MigrationPreparationError::Execution(_) => RESULT_EXECUTION,
        };
        Self {
            code,
            message: Some(error.to_string()),
            progress: None,
        }
    }
}

fn parse_string(
    env: &mut JNIEnv<'_>,
    value: JString<'_>,
    name: &str,
) -> Result<String, NativeOutcome> {
    let value: String = env
        .get_string(&value)
        .map_err(|error| NativeOutcome::invalid_argument(format!("Read {name}: {error}")))?
        .into();
    if value.is_empty() {
        return Err(NativeOutcome::invalid_argument(format!("{name} is empty")));
    }
    Ok(value)
}

fn parse_network(value: &str) -> Result<WalletNetwork, NativeOutcome> {
    WalletNetwork::from_str(value)
        .ok_or_else(|| NativeOutcome::invalid_argument("Unsupported wallet network"))
}

fn encode_outcome(env: &mut JNIEnv<'_>, outcome: NativeOutcome) -> jobject {
    let message = match outcome.message {
        Some(message) => match env.new_string(message) {
            Ok(message) => JObject::from(message),
            Err(error) => return throw_encoding_error(env, error),
        },
        None => JObject::null(),
    };
    let progress = match outcome.progress {
        Some(progress) => {
            let values = [
                progress.state as u8 as i64,
                i64::from(progress.confirmation_count),
                i64::from(progress.confirmation_target),
                i64::from(progress.completed_stage_count),
                i64::from(progress.total_stage_count),
            ];
            let array = match env.new_long_array(values.len() as i32) {
                Ok(array) => array,
                Err(error) => return throw_encoding_error(env, error),
            };
            if let Err(error) = env.set_long_array_region(&array, 0, &values) {
                return throw_encoding_error(env, error);
            }
            JObject::from(array)
        }
        None => JObject::null(),
    };
    match env.new_object(
        RESULT_CLASS,
        RESULT_SIGNATURE,
        &[
            JValue::Int(outcome.code),
            JValue::Object(&message),
            JValue::Object(&progress),
        ],
    ) {
        Ok(result) => result.into_raw(),
        Err(error) => throw_encoding_error(env, error),
    }
}

fn throw_encoding_error(env: &mut JNIEnv<'_>, error: jni::errors::Error) -> jobject {
    let _ = env.throw_new(
        "java/lang/IllegalStateException",
        format!("Encode Ironwood JNI result: {error}"),
    );
    JObject::null().into_raw()
}

fn run_outcome(
    env: &mut JNIEnv<'_>,
    context: &str,
    action: impl FnOnce(&mut JNIEnv<'_>) -> NativeOutcome,
) -> jobject {
    let outcome = match catch_unwind(AssertUnwindSafe(|| action(env))) {
        Ok(outcome) => outcome,
        Err(panic) => NativeOutcome::panic(context, panic),
    };
    encode_outcome(env, outcome)
}

fn report_sync_progress(
    java_vm: &JavaVM,
    callback: &jni::objects::GlobalRef,
    progress: crate::wallet::sync_engine::SyncProgressEvent,
) -> Result<(), String> {
    let mut env = java_vm
        .attach_current_thread()
        .map_err(|error| format!("Attach sync callback thread: {error}"))?;
    let result = env.call_method(
        callback.as_obj(),
        SYNC_CALLBACK_METHOD,
        SYNC_CALLBACK_SIGNATURE,
        &[
            JValue::Long(progress.scanned_height as i64),
            JValue::Long(progress.chain_tip_height as i64),
            JValue::Double(progress.percentage),
            JValue::Double(progress.display_target_percentage),
            JValue::Long(progress.display_target_blocks as i64),
            JValue::Bool(if progress.is_syncing {
                JNI_TRUE
            } else {
                JNI_FALSE
            }),
            JValue::Bool(if progress.is_complete {
                JNI_TRUE
            } else {
                JNI_FALSE
            }),
            JValue::Bool(if progress.has_new_tx {
                JNI_TRUE
            } else {
                JNI_FALSE
            }),
        ],
    );
    match result {
        Ok(_) => Ok(()),
        Err(error) => {
            if env.exception_check().unwrap_or(false) {
                let _ = env.exception_clear();
            }
            Err(format!("Deliver sync progress: {error}"))
        }
    }
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeBeginOperation(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jboolean {
    match catch_unwind(migration_preparation::begin_operation) {
        Ok(true) => JNI_TRUE,
        Ok(false) | Err(_) => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeEndOperation(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) {
    if let Err(panic) = catch_unwind(migration_preparation::end_operation) {
        let _ = NativeOutcome::panic("end operation", panic);
    }
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeCancelOperation(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jboolean {
    match catch_unwind(migration_preparation::cancel_operation) {
        Ok(true) => JNI_TRUE,
        Ok(false) | Err(_) => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeIsSyncRunning(
    _env: JNIEnv<'_>,
    _this: JObject<'_>,
) -> jboolean {
    match catch_unwind(migration_preparation::is_sync_running) {
        Ok(true) => JNI_TRUE,
        Ok(false) | Err(_) => JNI_FALSE,
    }
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeInspect(
    mut env: JNIEnv<'_>,
    _this: JObject<'_>,
    db_path: JString<'_>,
    network: JString<'_>,
    account_uuid: JString<'_>,
    expected_run_id: JString<'_>,
) -> jobject {
    run_outcome(&mut env, "inspect preparation", |env| {
        let db_path = match parse_string(env, db_path, "dbPath") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let network =
            match parse_string(env, network, "network").and_then(|value| parse_network(&value)) {
                Ok(value) => value,
                Err(error) => return error,
            };
        let account_uuid = match parse_string(env, account_uuid, "accountUuid") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let expected_run_id = match parse_string(env, expected_run_id, "expectedRunId") {
            Ok(value) => value,
            Err(error) => return error,
        };
        match migration_preparation::inspect(&db_path, network, &account_uuid, &expected_run_id) {
            Ok(progress) => NativeOutcome::progress(progress),
            Err(error) => error.into(),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeAdvance(
    mut env: JNIEnv<'_>,
    _this: JObject<'_>,
    db_path: JString<'_>,
    lightwalletd_url: JString<'_>,
    network: JString<'_>,
    account_uuid: JString<'_>,
    expected_run_id: JString<'_>,
    credential: JByteArray<'_>,
    salt_base64: JString<'_>,
) -> jobject {
    run_outcome(&mut env, "advance preparation", |env| {
        let db_path = match parse_string(env, db_path, "dbPath") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let lightwalletd_url = match parse_string(env, lightwalletd_url, "lightwalletdUrl") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let network =
            match parse_string(env, network, "network").and_then(|value| parse_network(&value)) {
                Ok(value) => value,
                Err(error) => return error,
            };
        let account_uuid = match parse_string(env, account_uuid, "accountUuid") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let expected_run_id = match parse_string(env, expected_run_id, "expectedRunId") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let credential = match env.convert_byte_array(&credential) {
            Ok(value) if !value.is_empty() => Zeroizing::new(value),
            Ok(_) => return NativeOutcome::invalid_argument("credential is empty"),
            Err(error) => {
                return NativeOutcome::invalid_argument(format!("Read credential: {error}"));
            }
        };
        let salt_base64 = match parse_string(env, salt_base64, "saltBase64") {
            Ok(value) => value,
            Err(error) => return error,
        };
        match migration_preparation::advance(
            &db_path,
            &lightwalletd_url,
            network,
            &account_uuid,
            &expected_run_id,
            credential,
            &salt_base64,
        ) {
            Ok(progress) => NativeOutcome::progress(progress),
            Err(error) => error.into(),
        }
    })
}

#[no_mangle]
pub extern "system" fn Java_com_keplr_vizor_IronwoodMigrationJniBindings_nativeRunSync(
    mut env: JNIEnv<'_>,
    _this: JObject<'_>,
    db_path: JString<'_>,
    lightwalletd_url: JString<'_>,
    network: JString<'_>,
    callback: JObject<'_>,
) -> jobject {
    run_outcome(&mut env, "run preparation sync", |env| {
        let db_path = match parse_string(env, db_path, "dbPath") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let lightwalletd_url = match parse_string(env, lightwalletd_url, "lightwalletdUrl") {
            Ok(value) => value,
            Err(error) => return error,
        };
        let network =
            match parse_string(env, network, "network").and_then(|value| parse_network(&value)) {
                Ok(value) => value,
                Err(error) => return error,
            };
        if callback.is_null() {
            return NativeOutcome::invalid_argument("progress callback is null");
        }
        let java_vm = match env.get_java_vm() {
            Ok(value) => Arc::new(value),
            Err(error) => {
                return NativeOutcome::callback(format!("Get Java VM: {error}"));
            }
        };
        let callback = match env.new_global_ref(callback) {
            Ok(value) => value,
            Err(error) => {
                return NativeOutcome::callback(format!("Retain progress callback: {error}"));
            }
        };
        let callback_error = Arc::new(Mutex::new(None::<String>));
        let callback_error_for_sync = callback_error.clone();
        let sync_result = migration_preparation::run_sync(
            &db_path,
            &lightwalletd_url,
            network,
            move |progress| {
                if callback_error_for_sync
                    .lock()
                    .unwrap_or_else(|poisoned| poisoned.into_inner())
                    .is_some()
                {
                    return;
                }
                if let Err(error) = report_sync_progress(&java_vm, &callback, progress) {
                    *callback_error_for_sync
                        .lock()
                        .unwrap_or_else(|poisoned| poisoned.into_inner()) = Some(error);
                    migration_preparation::cancel_operation();
                }
            },
        );
        let callback_error = callback_error
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take();
        if let Some(error) = callback_error {
            return NativeOutcome::callback(error);
        }
        match sync_result {
            Ok(()) => NativeOutcome::success(),
            Err(error) => error.into(),
        }
    })
}
