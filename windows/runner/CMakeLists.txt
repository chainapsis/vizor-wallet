cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "velopack_uninstall.cpp"
  "velopack_update.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

function(vizor_env_or_default OUTPUT_NAME ENV_NAME DEFAULT_VALUE)
  if(DEFINED ENV{${ENV_NAME}} AND NOT "$ENV{${ENV_NAME}}" STREQUAL "")
    set(VALUE "$ENV{${ENV_NAME}}")
  else()
    set(VALUE "${DEFAULT_VALUE}")
  endif()
  string(REPLACE "\\" "\\\\" VALUE "${VALUE}")
  string(REPLACE "\"" "\\\"" VALUE "${VALUE}")
  set(${OUTPUT_NAME} "${VALUE}" PARENT_SCOPE)
endfunction()

vizor_env_or_default(VIZOR_WINDOWS_COMPANY_NAME VIZOR_WINDOWS_COMPANY_NAME "com.keplr")
vizor_env_or_default(VIZOR_WINDOWS_FILE_DESCRIPTION VIZOR_WINDOWS_FILE_DESCRIPTION "Vizor")
vizor_env_or_default(VIZOR_WINDOWS_INTERNAL_NAME VIZOR_WINDOWS_INTERNAL_NAME "Vizor")
vizor_env_or_default(VIZOR_WINDOWS_LEGAL_COPYRIGHT VIZOR_WINDOWS_LEGAL_COPYRIGHT "Copyright (C) 2026 com.keplr. All rights reserved.")
vizor_env_or_default(VIZOR_WINDOWS_ORIGINAL_FILENAME VIZOR_WINDOWS_ORIGINAL_FILENAME "Vizor.exe")
vizor_env_or_default(VIZOR_WINDOWS_PRODUCT_NAME VIZOR_WINDOWS_PRODUCT_NAME "Vizor")
configure_file(
  "${CMAKE_CURRENT_SOURCE_DIR}/resource_values.h.in"
  "${CMAKE_CURRENT_BINARY_DIR}/resource_values.h"
  @ONLY
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Compile sources as UTF-8 so non-ASCII bytes in source/comments don't raise
# C4819, which apply_standard_settings' /W4 /WX would promote to a hard build
# error on non-UTF-8 codepage hosts (e.g. Korean cp949).
target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")
target_compile_definitions(${BINARY_NAME} PRIVATE "VIZOR_WINDOWS_STORAGE_PREFIX=\"${VIZOR_WINDOWS_STORAGE_PREFIX}\"")

if(DEFINED ENV{VIZOR_UPDATE_FEED_PUBLIC_KEY_B64})
  target_compile_definitions(${BINARY_NAME} PRIVATE "VIZOR_UPDATE_FEED_PUBLIC_KEY_B64=\"$ENV{VIZOR_UPDATE_FEED_PUBLIC_KEY_B64}\"")
else()
  target_compile_definitions(${BINARY_NAME} PRIVATE "VIZOR_UPDATE_FEED_PUBLIC_KEY_B64=\"\"")
endif()
if(DEFINED ENV{VIZOR_UPDATE_GITHUB_REPO_URL})
  target_compile_definitions(${BINARY_NAME} PRIVATE "VIZOR_UPDATE_GITHUB_REPO_URL=\"$ENV{VIZOR_UPDATE_GITHUB_REPO_URL}\"")
endif()
if(DEFINED ENV{VIZOR_UPDATE_RELEASE_BASE_URL})
  target_compile_definitions(${BINARY_NAME} PRIVATE "VIZOR_UPDATE_RELEASE_BASE_URL=\"$ENV{VIZOR_UPDATE_RELEASE_BASE_URL}\"")
endif()

set(VELOPACK_LIBC_VERSION "0.0.1589-ga2c5a97")
set(VELOPACK_LIBC_SHA256 "6c0cf30be1ff8e37d904458c9c00cc61a5276521fc708cfebbe96615777da38c")
set(VELOPACK_LIBC_URL "https://github.com/velopack/velopack/releases/download/${VELOPACK_LIBC_VERSION}/velopack_libc_${VELOPACK_LIBC_VERSION}.zip")
set(VELOPACK_LIBC_ROOT "${CMAKE_BINARY_DIR}/velopack_libc_${VELOPACK_LIBC_VERSION}")
set(VELOPACK_LIBC_ARCHIVE "${CMAKE_BINARY_DIR}/velopack_libc_${VELOPACK_LIBC_VERSION}.zip")

if(NOT EXISTS "${VELOPACK_LIBC_ROOT}/include/Velopack.h")
  file(DOWNLOAD
    "${VELOPACK_LIBC_URL}"
    "${VELOPACK_LIBC_ARCHIVE}"
    EXPECTED_HASH "SHA256=${VELOPACK_LIBC_SHA256}"
  )
  file(MAKE_DIRECTORY "${VELOPACK_LIBC_ROOT}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "${VELOPACK_LIBC_ARCHIVE}"
    WORKING_DIRECTORY "${VELOPACK_LIBC_ROOT}"
    RESULT_VARIABLE VELOPACK_EXTRACT_RESULT
  )
  if(NOT VELOPACK_EXTRACT_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to extract Velopack libc archive.")
  endif()
endif()

set(VELOPACK_LIBC_DLL "${VELOPACK_LIBC_ROOT}/lib/velopack_libc_win_x64_msvc.dll")
set(VELOPACK_LIBC_IMPLIB "${VELOPACK_LIBC_ROOT}/lib/velopack_libc_win_x64_msvc.dll.lib")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "advapi32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "secur32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "bcrypt.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "crypt32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "credui.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "runtimeobject.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "shell32.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "version.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "winhttp.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "${VELOPACK_LIBC_IMPLIB}")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
target_include_directories(${BINARY_NAME} PRIVATE "${VELOPACK_LIBC_ROOT}/include")

add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${VELOPACK_LIBC_DLL}"
    "$<TARGET_FILE_DIR:${BINARY_NAME}>/velopack_libc.dll"
)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
