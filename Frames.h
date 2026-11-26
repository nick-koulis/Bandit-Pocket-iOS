#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#define FRAME_CAPACITY (1024 * 1024)
typedef struct {
    uint8_t bytes[FRAME_CAPACITY];
    size_t expected, used;
    uint16_t sequence;
} FrameBuffer;
static inline unsigned read16(const uint8_t *p) { return (p[0] << 8) | p[1]; }
// A zero return means the frame is incomplete or was dropped.
static inline size_t assemble(FrameBuffer *f, const uint8_t *p, size_t n) {
    if (n < 7 || read16(p) != 0x55aa || read16(p+5) != n-7) return 0;
    unsigned seq = read16(p+3);
    if (p[2] == 0) {
        f->expected = 0;
        if (n < 15) return 0;
        uint32_t size = ((uint32_t)read16(p+7) << 16) | read16(p+9);
        if (size > FRAME_CAPACITY) return 0;
        f->expected = size;
        f->used = 0;
        f->sequence = (uint16_t)(seq+1);
    } else if (p[2] == 1 && f->expected) {
        if (seq != f->sequence || n-7 > f->expected-f->used) {
            f->expected = 0;
            return 0;
        }
        memcpy(f->bytes+f->used,p+7,n-7);
        f->used += n-7;
        f->sequence++;
        if (f->used == f->expected) {
            f->expected = 0;
            return f->used;
        }
    }
    return 0;
}
