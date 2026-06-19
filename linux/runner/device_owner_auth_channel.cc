#include "device_owner_auth_channel.h"

#include <polkit/polkit.h>
#include <unistd.h>

namespace {

constexpr char kChannelName[] = "com.zcash.wallet/device_owner_auth";
constexpr char kVerifyMethod[] = "verify";
constexpr char kResetWalletActionId[] = APPLICATION_ID ".reset-wallet";

struct DeviceOwnerAuthRequest {
  FlMethodCall* method_call = nullptr;
  PolkitAuthority* authority = nullptr;
  PolkitSubject* subject = nullptr;
};

void device_owner_auth_request_free(DeviceOwnerAuthRequest* request) {
  if (request == nullptr) {
    return;
  }

  g_clear_object(&request->method_call);
  g_clear_object(&request->authority);
  g_clear_object(&request->subject);
  g_free(request);
}

void respond_error(DeviceOwnerAuthRequest* request,
                   const gchar* code,
                   const gchar* message) {
  fl_method_call_respond_error(request->method_call, code, message, nullptr,
                               nullptr);
  device_owner_auth_request_free(request);
}

void respond_success(DeviceOwnerAuthRequest* request, bool value) {
  fl_method_call_respond_success(request->method_call, fl_value_new_bool(value),
                                 nullptr);
  device_owner_auth_request_free(request);
}

void check_authorization_cb(GObject* source_object,
                            GAsyncResult* result,
                            gpointer user_data) {
  auto* request = static_cast<DeviceOwnerAuthRequest*>(user_data);

  g_autoptr(GError) error = nullptr;
  g_autoptr(PolkitAuthorizationResult) authorization =
      polkit_authority_check_authorization_finish(
          POLKIT_AUTHORITY(source_object), result, &error);

  if (error != nullptr) {
    if (g_error_matches(error, POLKIT_ERROR, POLKIT_ERROR_CANCELLED) ||
        g_error_matches(error, POLKIT_ERROR, POLKIT_ERROR_NOT_AUTHORIZED)) {
      respond_error(request, "cancelled", error->message);
      return;
    }

    respond_error(request, "failed", error->message);
    return;
  }

  respond_success(
      request,
      authorization != nullptr &&
          polkit_authorization_result_get_is_authorized(authorization));
}

void authority_get_cb(GObject* source_object,
                      GAsyncResult* result,
                      gpointer user_data) {
  auto* request = static_cast<DeviceOwnerAuthRequest*>(user_data);

  g_autoptr(GError) error = nullptr;
  request->authority = polkit_authority_get_finish(result, &error);
  if (error != nullptr || request->authority == nullptr) {
    respond_error(request, "unavailable",
                  error != nullptr ? error->message
                                   : "Polkit authority is unavailable.");
    return;
  }

  request->subject =
      polkit_unix_process_new_for_owner(getpid(), 0, getuid());
  polkit_authority_check_authorization(
      request->authority, request->subject, kResetWalletActionId, nullptr,
      POLKIT_CHECK_AUTHORIZATION_FLAGS_ALLOW_USER_INTERACTION, nullptr,
      check_authorization_cb, request);
}

void method_call_cb(FlMethodChannel* channel,
                    FlMethodCall* method_call,
                    gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, kVerifyMethod) != 0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }

  auto* request = g_new0(DeviceOwnerAuthRequest, 1);
  request->method_call = FL_METHOD_CALL(g_object_ref(method_call));

  polkit_authority_get_async(nullptr, authority_get_cb, request);
}

}  // namespace

void device_owner_auth_channel_register(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry,
                                                  "DeviceOwnerAuthChannel");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), kChannelName,
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, method_call_cb, nullptr,
                                            nullptr);
}
