#include "test_binary_messenger.h"

#include <map>

// The engine defines the FlBinaryMessenger interface next to its engine-bound
// implementation, which cannot be built without an engine. Provide the
// interface, its response-handle type and the public wrappers here instead.

G_DEFINE_INTERFACE(FlBinaryMessenger, fl_binary_messenger, G_TYPE_OBJECT)
G_DEFINE_QUARK(fl_binary_messenger_codec_error_quark, fl_binary_messenger_codec_error)

static void fl_binary_messenger_default_init(FlBinaryMessengerInterface*) {}

G_DEFINE_TYPE(FlBinaryMessengerResponseHandle, fl_binary_messenger_response_handle, G_TYPE_OBJECT)

static void fl_binary_messenger_response_handle_class_init(FlBinaryMessengerResponseHandleClass*) {}
static void fl_binary_messenger_response_handle_init(FlBinaryMessengerResponseHandle*) {}

void fl_binary_messenger_set_message_handler_on_channel(
    FlBinaryMessenger* messenger, const gchar* channel, FlBinaryMessengerMessageHandler handler,
    gpointer user_data, GDestroyNotify destroy_notify) {
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->set_message_handler_on_channel(messenger, channel, handler, user_data, destroy_notify);
}

gboolean fl_binary_messenger_send_response(FlBinaryMessenger* messenger,
    FlBinaryMessengerResponseHandle* response_handle, GBytes* response, GError** error) {
  return FL_BINARY_MESSENGER_GET_IFACE(messenger)->send_response(messenger, response_handle, response, error);
}

void fl_binary_messenger_send_on_channel(FlBinaryMessenger* messenger, const gchar* channel,
    GBytes* message, GCancellable* cancellable, GAsyncReadyCallback callback, gpointer user_data) {
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->send_on_channel(messenger, channel, message, cancellable, callback, user_data);
}

GBytes* fl_binary_messenger_send_on_channel_finish(FlBinaryMessenger* messenger, GAsyncResult* result, GError** error) {
  return FL_BINARY_MESSENGER_GET_IFACE(messenger)->send_on_channel_finish(messenger, result, error);
}

void fl_binary_messenger_resize_channel(FlBinaryMessenger* messenger, const gchar* channel, int64_t new_size) {
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->resize_channel(messenger, channel, new_size);
}

void fl_binary_messenger_set_warns_on_channel_overflow(FlBinaryMessenger* messenger, const gchar* channel, bool warns) {
  FL_BINARY_MESSENGER_GET_IFACE(messenger)->set_warns_on_channel_overflow(messenger, channel, warns);
}

// Never reached: the tests build the handler through the test seam.
FlEngine* fl_view_get_engine(FlView*) { return nullptr; }
FlBinaryMessenger* fl_engine_get_binary_messenger(FlEngine*) { return nullptr; }

// ---- response handle carrying a reply slot ----

G_DECLARE_FINAL_TYPE(TestResponseHandle, test_response_handle, VIZOR, TEST_RESPONSE_HANDLE, FlBinaryMessengerResponseHandle)

struct _TestResponseHandle {
  FlBinaryMessengerResponseHandle parent_instance;
  std::shared_ptr<ledger_test::Reply>* reply;
};

G_DEFINE_TYPE(TestResponseHandle, test_response_handle, fl_binary_messenger_response_handle_get_type())

static void test_response_handle_dispose(GObject* object) {
  auto* self = VIZOR_TEST_RESPONSE_HANDLE(object);
  delete self->reply;
  self->reply = nullptr;
  G_OBJECT_CLASS(test_response_handle_parent_class)->dispose(object);
}

static void test_response_handle_class_init(TestResponseHandleClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = test_response_handle_dispose;
}

static void test_response_handle_init(TestResponseHandle*) {}

// ---- the messenger ----

struct ChannelHandler {
  FlBinaryMessengerMessageHandler handler = nullptr;
  gpointer user_data = nullptr;
  GDestroyNotify destroy_notify = nullptr;
};

struct _TestMessenger {
  GObject parent_instance;
  std::map<std::string, ChannelHandler>* handlers;
  std::vector<ledger_test::Sent>* sent;
};

static void test_messenger_iface_init(FlBinaryMessengerInterface* iface);

G_DEFINE_TYPE_WITH_CODE(TestMessenger, test_messenger, G_TYPE_OBJECT,
                        G_IMPLEMENT_INTERFACE(fl_binary_messenger_get_type(), test_messenger_iface_init))

static void test_messenger_dispose(GObject* object) {
  auto* self = VIZOR_TEST_MESSENGER(object);
  if (self->handlers) {
    for (auto& entry : *self->handlers) {
      if (entry.second.destroy_notify) entry.second.destroy_notify(entry.second.user_data);
    }
    delete self->handlers;
    self->handlers = nullptr;
  }
  if (self->sent) {
    for (auto& sent : *self->sent) g_bytes_unref(sent.bytes);
    delete self->sent;
    self->sent = nullptr;
  }
  G_OBJECT_CLASS(test_messenger_parent_class)->dispose(object);
}

static void test_messenger_class_init(TestMessengerClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = test_messenger_dispose;
}

static void test_messenger_init(TestMessenger* self) {
  self->handlers = new std::map<std::string, ChannelHandler>();
  self->sent = new std::vector<ledger_test::Sent>();
}

static void set_message_handler_on_channel(FlBinaryMessenger* messenger, const gchar* channel,
    FlBinaryMessengerMessageHandler handler, gpointer user_data, GDestroyNotify destroy_notify) {
  auto* self = VIZOR_TEST_MESSENGER(messenger);
  auto& slot = (*self->handlers)[channel];
  if (slot.destroy_notify) slot.destroy_notify(slot.user_data);
  slot = {handler, user_data, destroy_notify};
}

static gboolean send_response(FlBinaryMessenger*, FlBinaryMessengerResponseHandle* response_handle,
    GBytes* response, GError** error) {
  auto* handle = VIZOR_TEST_RESPONSE_HANDLE(response_handle);
  auto& reply = **handle->reply;
  if (reply.done) {
    g_set_error(error, FL_BINARY_MESSENGER_ERROR, FL_BINARY_MESSENGER_ERROR_ALREADY_RESPONDED, "already responded");
    return FALSE;
  }
  reply.done = true;
  reply.bytes = response ? g_bytes_ref(response) : nullptr;
  return TRUE;
}

static void send_on_channel(FlBinaryMessenger* messenger, const gchar* channel, GBytes* message,
    GCancellable*, GAsyncReadyCallback callback, gpointer user_data) {
  auto* self = VIZOR_TEST_MESSENGER(messenger);
  self->sent->push_back({channel, message ? g_bytes_ref(message) : g_bytes_new(nullptr, 0)});
  if (callback) callback(G_OBJECT(messenger), nullptr, user_data);
}

static GBytes* send_on_channel_finish(FlBinaryMessenger*, GAsyncResult*, GError**) {
  return g_bytes_new(nullptr, 0);
}

static void resize_channel(FlBinaryMessenger*, const gchar*, int64_t) {}
static void set_warns_on_channel_overflow(FlBinaryMessenger*, const gchar*, bool) {}
static void shutdown(FlBinaryMessenger*) {}

static void test_messenger_iface_init(FlBinaryMessengerInterface* iface) {
  iface->set_message_handler_on_channel = set_message_handler_on_channel;
  iface->send_response = send_response;
  iface->send_on_channel = send_on_channel;
  iface->send_on_channel_finish = send_on_channel_finish;
  iface->resize_channel = resize_channel;
  iface->set_warns_on_channel_overflow = set_warns_on_channel_overflow;
  iface->shutdown = shutdown;
}

namespace ledger_test {

TestMessenger* test_messenger_new() {
  return VIZOR_TEST_MESSENGER(g_object_new(test_messenger_get_type(), nullptr));
}

std::shared_ptr<Reply> test_messenger_deliver(TestMessenger* messenger, const std::string& channel, GBytes* message) {
  auto reply = std::make_shared<Reply>();
  const auto entry = messenger->handlers->find(channel);
  if (entry == messenger->handlers->end() || !entry->second.handler) {
    reply->done = true;  // Flutter drops messages nobody listens to.
    return reply;
  }
  auto* handle = VIZOR_TEST_RESPONSE_HANDLE(g_object_new(test_response_handle_get_type(), nullptr));
  handle->reply = new std::shared_ptr<Reply>(reply);
  entry->second.handler(FL_BINARY_MESSENGER(messenger), channel.c_str(), message,
                        FL_BINARY_MESSENGER_RESPONSE_HANDLE(handle), entry->second.user_data);
  g_object_unref(handle);
  return reply;
}

std::vector<Sent>& test_messenger_sent(TestMessenger* messenger) { return *messenger->sent; }

}  // namespace ledger_test
