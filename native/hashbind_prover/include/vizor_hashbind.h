// C ABI of libvizor_hashbind_prover — reference for the Dart FFI bindings in
// lib/src/features/swap/integrations/zwap/zwap_hashbind_native.dart.
// Status codes are provekit-ffi PKStatus values (0 success, 1 invalid input,
// 2 scheme read error, 3 witness error, 4 proof error, 5 serialization
// error) plus VIZOR_HASHBIND_NOT_INITIALIZED (100).

#ifndef VIZOR_HASHBIND_H
#define VIZOR_HASHBIND_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define VIZOR_HASHBIND_NOT_INITIALIZED 100

// Layout matches provekit-ffi's PKBuf. Free every returned buffer with
// vizor_hashbind_free_buf.
typedef struct {
  uint8_t *ptr;
  size_t len;
  size_t cap;
} VizorHashbindBuf;

// Load the ProveKit prover scheme from pallas.pkp bytes. Idempotent.
int32_t vizor_hashbind_init(const uint8_t *pkp_ptr, size_t pkp_len);

// 1 after a successful init in this process, else 0.
int32_t vizor_hashbind_ready(void);

// Prove knowledge of the 32-byte big-endian scalar k_a. On success fills
// out_proof with provekit `.np` (postcard) proof bytes.
int32_t vizor_hashbind_prove(const uint8_t *k_be_ptr, size_t k_be_len,
                             VizorHashbindBuf *out_proof);

// Verify a proof against pallas.pkv bytes (test/self-check path).
int32_t vizor_hashbind_verify(const uint8_t *pkv_ptr, size_t pkv_len,
                              const uint8_t *proof_ptr, size_t proof_len);

// Copy the last error message (UTF-8, never key/proof material) into out.
int32_t vizor_hashbind_last_error(VizorHashbindBuf *out);

void vizor_hashbind_free_buf(VizorHashbindBuf buf);

#ifdef __cplusplus
}
#endif

#endif  // VIZOR_HASHBIND_H
