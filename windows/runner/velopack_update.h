#ifndef RUNNER_VELOPACK_UPDATE_H_
#define RUNNER_VELOPACK_UPDATE_H_

#include <flutter/binary_messenger.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateVelopackUpdateChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_VELOPACK_UPDATE_H_
