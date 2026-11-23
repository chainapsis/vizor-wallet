// Export the public fixture account for importing into the Vizor test wallet.
#include "librust_c.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const uint8_t fixture_seed[] = {
    // BIP39 seed of the public Speculos default mnemonic.
    0xb1, 0x19, 0x97, 0xfa, 0xff, 0x42, 0x0a, 0x33,
    0x1b, 0xb4, 0xa4, 0xff, 0xdc, 0x8b, 0xdc, 0x8b,
    0xa7, 0xc0, 0x17, 0x32, 0xa9, 0x9a, 0x30, 0xd8,
    0x3d, 0xbb, 0xeb, 0xd4, 0x69, 0x66, 0x6c, 0x84,
    0xb4, 0x7d, 0x09, 0xd3, 0xf5, 0xf4, 0x72, 0xb3,
    0xb9, 0x38, 0x4a, 0xc6, 0x34, 0xbe, 0xba, 0x2a,
    0x44, 0x0b, 0xa3, 0x6e, 0xc7, 0x66, 0x11, 0x44,
    0x13, 0x2f, 0x35, 0xe2, 0x06, 0x87, 0x35, 0x64,
};

int32_t GenerateTRNGRandomness(uint8_t *output, uint8_t length) {
    arc4random_buf(output, length);
    return 0;
}

static void check_result(uint32_t code, const char *message) {
    if (code) {
        fprintf(stderr, "Firmware rejected request (%u): %s\n", code, message ? message : "");
        exit(1);
    }
}

static void print_frames(UREncodeResult *ur) {
    check_result(ur->error_code, ur->error_message);
    puts(ur->data);
    if (!ur->is_multi_part) return;

    // The first fountain cycle carries each source fragment once.
    const char *sequence = strchr(ur->data, '/');
    unsigned count;
    if (!sequence || sscanf(sequence, "/1-%u/", &count) != 1 || !count) {
        fprintf(stderr, "Invalid firmware UR sequence\n");
        exit(1);
    }
    for (unsigned i = 1; i < count; ++i) {
        UREncodeMultiResult *next = get_next_part(ur->encoder);
        check_result(next->error_code, next->error_message);
        puts(next->data);
        free_ur_encode_muilt_result(next);
    }
}

int main(void) {
    uint8_t seed[sizeof fixture_seed];
    // Firmware consumes and clears its seed argument on each call.
    memcpy(seed, fixture_seed, sizeof seed);
    SimpleResponse_u8 *fp = calculate_zcash_seed_fingerprint(seed, sizeof seed);
    check_result(fp->error_code, fp->error_message);
    memcpy(seed, fixture_seed, sizeof seed);
#ifdef KEYSTONE_ZEBRA_REGTEST
    char account_path[] = "M/32'/1'/0'";
#else
    char account_path[] = "M/32'/133'/0'";
#endif
    SimpleResponse_c_char *ufvk = derive_zcash_ufvk(seed, sizeof seed, account_path);
    check_result(ufvk->error_code, ufvk->error_message);
    ZcashKey key = {.key_text = ufvk->data, .key_name = "Keystone fixture", .index = 0};
    CSliceFFI_ZcashKey keys = {.data = &key, .size = 1};
    print_frames(get_connect_zcash_wallet_ur(fp->data, 32, &keys, "3.2.2"));
    return 0;
}
