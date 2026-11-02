#include <stdint.h>
#include <stddef.h>
#include <string.h>
uint32_t fy_read32(void *p, size_t o) {
    __sync_synchronize();
    uint32_t v = *(volatile uint32_t *)((uint8_t *)p + o);
    __sync_synchronize(); return v;
}
void fy_write32(void *p, size_t o, uint32_t v) {
    __sync_synchronize(); *(volatile uint32_t *)((uint8_t *)p + o) = v;
    __sync_synchronize();
}
void fy_copy(void *dst, const void *src, size_t n) {
    __sync_synchronize(); memcpy(dst, src, n); __sync_synchronize();
}
