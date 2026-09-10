// A FlBinaryMessenger for tests: hands encoded messages straight to the
// registered channel handlers and records what the handlers send back.
#ifndef VIZOR_TEST_BINARY_MESSENGER_H_
#define VIZOR_TEST_BINARY_MESSENGER_H_

#include <flutter_linux/flutter_linux.h>

#include <functional>
#include <memory>
#include <string>
#include <vector>

G_BEGIN_DECLS
G_DECLARE_FINAL_TYPE(TestMessenger, test_messenger, VIZOR, TEST_MESSENGER, GObject)
G_END_DECLS

namespace ledger_test {

// One reply slot per delivered message; filled when the handler responds.
struct Reply {
  bool done = false;
  GBytes* bytes = nullptr;  // owned
  ~Reply() { if (bytes) g_bytes_unref(bytes); }
};

struct Sent {
  std::string channel;
  GBytes* bytes;  // owned
};

TestMessenger* test_messenger_new();
// Delivers `message` to the handler registered for `channel`. The returned
// slot is completed when the handler replies, possibly after main-loop turns.
std::shared_ptr<Reply> test_messenger_deliver(TestMessenger* messenger, const std::string& channel, GBytes* message);
// Messages the handlers pushed to Dart (event channel sends), oldest first.
std::vector<Sent>& test_messenger_sent(TestMessenger* messenger);

}  // namespace ledger_test

#endif  // VIZOR_TEST_BINARY_MESSENGER_H_
