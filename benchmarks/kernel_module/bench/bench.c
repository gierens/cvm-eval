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

static int __init bench_init(void) {
    pr_info("Initializing: mode=%d\n", mode);

    if (!mode || mode == 1) bench_cpuid();

    return 0;
}

static void __exit bench_exit(void) { pr_info("Exit\n"); }

module_init(bench_init);
module_exit(bench_exit);
