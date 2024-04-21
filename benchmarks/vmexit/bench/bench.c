#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/time.h>
#include <linux/types.h>

#include "tsc.h"

#define MODULE_NAME "bench"

#ifdef pr_fmt
#undef pr_fmt
#endif
#define pr_fmt(fmt) KBUILD_MODNAME ": " fmt

#define WARMUP_COUNT 10000ULL
#define BENCH_COUNT 10000000ULL  // 10 million

MODULE_LICENSE("GPL");

static int mode = 0;
module_param(mode, int, 0);

static inline void _cpuid(uint64_t rax, uint64_t rcx) {
    uint64_t rbx, rdx;
    asm volatile("cpuid\n\t"
                 : "=a"(rax), "=b"(rbx), "=c"(rcx), "=d"(rdx)
                 : "a"(rax), "c"(rcx)
                 :);
}

static void measure_cpuid(uint64_t rax, uint64_t rcx) {
    uint64_t N = 0;
    uint64_t i = 0;

    N = WARMUP_COUNT;
    // warmup
    for (i = 0; i < N; i++) {
        _cpuid(rax, rcx);
    }

    N = BENCH_COUNT;
    s64 start_time = ktime_get_ns();
    uint64_t start = __tsc_start();
    for (i = 0; i < N; i++) {
        _cpuid(rax, rcx);
    }
    uint64_t end = __tsc_end();
    s64 end_time = ktime_get_ns();

    uint64_t total_cycles = end - start;
    uint64_t avg_cycles = total_cycles / N;
    s64 total_time = end_time - start_time;
    s64 avg_time = total_time / N;
    pr_info("cpuid (rax=%llu, rcx=%llu) :\n", rax, rcx);
    pr_info("  %llu cycles (avg: %llu)\n", total_cycles, avg_cycles);
    pr_info("  %lld ns (avg: %lld)\n", total_time, avg_time);
}

static void bench_cpuid(void) {
    pr_info("Benchmarking cpuid\n");
    measure_cpuid(0x0, 0);   // vendor
    measure_cpuid(0x1, 0);   // feature   (VMGEXIT in SNP)
    measure_cpuid(0x2, 0);   // cache/tlb (#VE in TDX)
    measure_cpuid(0xb, 0);   // extended topology (#VE in TDX, VMGEXIT in SNP)
    measure_cpuid(0x15, 0);  // TSC freq
    measure_cpuid(0x16, 0);  // TSC freq  (#VE in TDX)
}

static inline void _rdmsr(uint32_t msr, uint64_t *val) {
    uint32_t lo, hi;
    asm volatile("rdmsr\n\t" : "=a"(lo), "=d"(hi) : "c"(msr) :);
    *val = ((uint64_t)hi << 32) | lo;
}

/*
static inline void _wrmsr(uint32_t msr, uint64_t val) {
    uint32_t lo = val & 0xFFFFFFFF;
    uint32_t hi = val >> 32;
    asm volatile("wrmsr\n\t" : : "c"(msr), "a"(lo), "d"(hi) :);
}
*/

static void measure_msr(uint32_t msr) {
    uint64_t N = 0;
    uint64_t i = 0;
    uint64_t val = 0;

    N = WARMUP_COUNT;
    // warmup
    for (i = 0; i < N; i++) {
        _rdmsr(msr, &val);
    }

    N = BENCH_COUNT;
    s64 start_time = ktime_get_ns();
    uint64_t start = __tsc_start();
    for (i = 0; i < N; i++) {
        _rdmsr(msr, &val);
    }
    uint64_t end = __tsc_end();
    s64 end_time = ktime_get_ns();

    uint64_t total_cycles = end - start;
    uint64_t avg_cycles = total_cycles / N;
    s64 total_time = end_time - start_time;
    s64 avg_time = total_time / N;
    pr_info("msr (0x%x) :\n", msr);
    pr_info("  %llu cycles (avg: %llu)\n", total_cycles, avg_cycles);
    pr_info("  %lld ns (avg: %lld)\n", total_time, avg_time);
}

static void bench_msr(void) {
    pr_info("Benchmarking msr\n");
    measure_msr(0x1b);        // IA32_APIC_BASE
    measure_msr(0x198);       // IA32_PERF_STATUS
    measure_msr(0xC0000100);  // IA32_FS_BASE
}

// intel: vmcall
// amd: vmmcall
#define HYPERCALL ALTERNATIVE("vmcall", "vmmcall", X86_FEATURE_VMMCALL)

static inline uint64_t _hypercall(unsigned int nr) {
    uint64_t ret;
    asm volatile(HYPERCALL : "=a"(ret) : "a"(nr) : "memory");
    return ret;
}

static void measure_hypercall(unsigned int nr) {
    uint64_t N = 0;
    uint64_t i = 0;

    N = WARMUP_COUNT;
    // warmup
    for (i = 0; i < N; i++) {
        _hypercall(nr);
    }

    N = BENCH_COUNT;
    s64 start_time = ktime_get_ns();
    uint64_t start = __tsc_start();
    for (i = 0; i < N; i++) {
        _hypercall(nr);
    }
    uint64_t end = __tsc_end();
    s64 end_time = ktime_get_ns();

    uint64_t total_cycles = end - start;
    uint64_t avg_cycles = total_cycles / N;
    s64 total_time = end_time - start_time;
    s64 avg_time = total_time / N;
    pr_info("hypercall (nr=%u) :\n", nr);
    pr_info("  %llu cycles (avg: %llu)\n", total_cycles, avg_cycles);
    pr_info("  %lld ns (avg: %lld)\n", total_time, avg_time);
}

static void bench_hypercall(void) {
    pr_info("Benchmarking hypercall\n");
    // hypercall 2 (KVM_HC_FEATURES) is deprecated, kvm returns -ENOSYS (-1000)
    measure_hypercall(2);
}

static inline void _inb(uint16_t port, uint8_t *val) {
    asm volatile("inb %1, %0" : "=a"(*val) : "d"(port));
}

/*
static inline void _outb(uint16_t port, uint8_t val) {
    asm volatile("outb %0, %1" : : "a"(val), "d"(port));
}
*/

static void measure_pio(uint16_t port) {
    uint64_t N = 0;
    uint64_t i = 0;
    uint8_t val = 0;

    N = WARMUP_COUNT;
    // warmup
    for (i = 0; i < N; i++) {
        _inb(port, &val);
    }

    N = BENCH_COUNT;
    s64 start_time = ktime_get_ns();
    uint64_t start = __tsc_start();
    for (i = 0; i < N; i++) {
        _inb(port, &val);
    }
    uint64_t end = __tsc_end();
    s64 end_time = ktime_get_ns();

    uint64_t total_cycles = end - start;
    uint64_t avg_cycles = total_cycles / N;
    s64 total_time = end_time - start_time;
    s64 avg_time = total_time / N;
    pr_info("pio (port=0x%x) :\n", port);
    pr_info("  %llu cycles (avg: %llu)\n", total_cycles, avg_cycles);
    pr_info("  %lld ns (avg: %lld)\n", total_time, avg_time);
}

static void bench_pio(void) {
    pr_info("Benchmarking pio\n");
    measure_pio(0x40);  // PIT
    measure_pio(0x70);  // CMOS
    measure_pio(0xA0);  // PIC 2
}

static int __init bench_init(void) {
    pr_info("Initializing: mode=%d\n", mode);

    if (!mode || mode == 1) bench_cpuid();
    if (!mode || mode == 2) bench_msr();
    if (!mode || mode == 3) bench_hypercall();
    if (!mode || mode == 4) bench_pio();

    return 0;
}

static void __exit bench_exit(void) { pr_info("Exit\n"); }

module_init(bench_init);
module_exit(bench_exit);
