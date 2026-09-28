cmake_minimum_required(VERSION 3.14)
project(runner_lifecycle_tests LANGUAGES CXX)

# Run after `fvm flutter build windows` has populated flutter/ephemeral.
set(FLUTTER_EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../flutter/ephemeral"
    CACHE PATH "Flutter Windows engine headers and import library")
add_executable(win32_window_lifecycle_test
  win32_window_lifecycle_test.cpp ../win32_window.cpp)
target_compile_features(win32_window_lifecycle_test PRIVATE cxx_std_17)
target_compile_options(win32_window_lifecycle_test PRIVATE /W4 /WX /utf-8)
target_compile_definitions(win32_window_lifecycle_test PRIVATE UNICODE _UNICODE NOMINMAX)
target_include_directories(win32_window_lifecycle_test PRIVATE
  .. "${FLUTTER_EPHEMERAL_DIR}")
target_link_libraries(win32_window_lifecycle_test PRIVATE dwmapi
  "${FLUTTER_EPHEMERAL_DIR}/flutter_windows.dll.lib")
add_custom_command(TARGET win32_window_lifecycle_test POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${FLUTTER_EPHEMERAL_DIR}/flutter_windows.dll"
    "$<TARGET_FILE_DIR:win32_window_lifecycle_test>")
enable_testing()
add_test(NAME win32_window_lifecycle COMMAND win32_window_lifecycle_test)
