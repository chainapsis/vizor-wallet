#ifndef RUNNER_PASSWORD_INPUT_SOURCE_H_
#define RUNNER_PASSWORD_INPUT_SOURCE_H_
#include <flutter/method_channel.h>
#include <flutter/binary_messenger.h>
#include <windows.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreatePasswordInputSourceChannel(flutter::BinaryMessenger* messenger, HWND view);
#endif
