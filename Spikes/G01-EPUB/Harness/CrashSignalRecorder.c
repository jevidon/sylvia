// Records which fatal signal ends the harness app, and whether it was a stack overflow (review R2-03).
//
// Used only by DeepNestingUITests, which launch the app with SYLVIA_CRASH_SIGNAL_FILE set; without that variable this
// file does nothing. The UI tests decide that the app crashed from its process (kill(pid, 0) fails); macOS does not
// always write a crash report for the expected crash, so without this record the kind of crash would be unverified.
//
// A stack overflow faults in the guard page below the thread's stack, and a signal handler can only run then on an
// alternate signal stack, which is per thread. So, before main, this installs:
//   - an alternate signal stack on the main thread and, through libpthread's introspection hook, on every thread
//     started later (Swift concurrency's cooperative threads, where Readium's content iterator runs, included), freed
//     when the thread terminates;
//   - a handler for SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT and SIGFPE that appends one line to the file (signal,
//     code, fault address, stack pointer, the thread's stack bounds and name, and kind=stack-overflow when the fault
//     address is in the 1 MiB below the thread's stack or the stack pointer is within 16 KiB of its limit), then
//     restores the default action and returns, so the faulting instruction faults again and the process ends exactly
//     as it would have (the crash report, when macOS writes one, shows the original fault).
// Only async-signal-safe calls are made in the handler (write, signal, raise, pthread_self and reads of the thread's
// own stack bounds and name). A process killed by SIGKILL (for example by jetsam) leaves no line.
//
// Stage 0 harness only; never shipped.

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <pthread/introspection.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ucontext.h>
#include <unistd.h>

static int sylvia_crash_fd = -1;
static pthread_introspection_hook_t sylvia_previous_hook = NULL;
static const size_t sylvia_altstack_size = 64 * 1024;

static void sylvia_install_altstack(void) {
    stack_t current;
    if (sigaltstack(NULL, &current) == 0 && !(current.ss_flags & SS_DISABLE) && current.ss_sp != NULL) return;
    void *memory = mmap(NULL, sylvia_altstack_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (memory == MAP_FAILED) return;
    stack_t stack = {.ss_sp = memory, .ss_size = sylvia_altstack_size, .ss_flags = 0};
    if (sigaltstack(&stack, NULL) != 0) munmap(memory, sylvia_altstack_size);
}

static void sylvia_remove_altstack(void) {
    stack_t current;
    if (sigaltstack(NULL, &current) != 0 || (current.ss_flags & SS_DISABLE) || (current.ss_flags & SS_ONSTACK)) return;
    stack_t disable = {.ss_sp = NULL, .ss_size = 0, .ss_flags = SS_DISABLE};
    if (sigaltstack(&disable, NULL) == 0 && current.ss_sp != NULL) munmap(current.ss_sp, current.ss_size);
}

static void sylvia_thread_hook(unsigned int event, pthread_t thread, void *addr, size_t size) {
    if (thread == pthread_self()) {
        if (event == PTHREAD_INTROSPECTION_THREAD_START) sylvia_install_altstack();
        if (event == PTHREAD_INTROSPECTION_THREAD_TERMINATE) sylvia_remove_altstack();
    }
    if (sylvia_previous_hook != NULL) sylvia_previous_hook(event, thread, addr, size);
}

// Formatting without allocation.
static size_t sylvia_put(char *buf, size_t n, size_t cap, const char *s) {
    while (*s && n + 1 < cap) buf[n++] = *s++;
    return n;
}

static size_t sylvia_put_hex(char *buf, size_t n, size_t cap, uintptr_t v) {
    char digits[2 + 2 * sizeof(uintptr_t) + 1];
    size_t i = sizeof(digits) - 1;
    digits[i] = 0;
    do {
        digits[--i] = "0123456789abcdef"[v & 0xf];
        v >>= 4;
    } while (v != 0 && i > 2);
    digits[--i] = 'x';
    digits[--i] = '0';
    return sylvia_put(buf, n, cap, digits + i);
}

static size_t sylvia_put_dec(char *buf, size_t n, size_t cap, long v) {
    char digits[24];
    size_t i = sizeof(digits) - 1;
    int negative = v < 0;
    unsigned long u = negative ? (unsigned long)(-v) : (unsigned long)v;
    digits[i] = 0;
    do {
        digits[--i] = (char)('0' + (u % 10));
        u /= 10;
    } while (u != 0 && i > 1);
    if (negative) digits[--i] = '-';
    return sylvia_put(buf, n, cap, digits + i);
}

static const char *sylvia_signal_name(int sig) {
    switch (sig) {
    case SIGSEGV: return "SIGSEGV";
    case SIGBUS: return "SIGBUS";
    case SIGILL: return "SIGILL";
    case SIGTRAP: return "SIGTRAP";
    case SIGABRT: return "SIGABRT";
    case SIGFPE: return "SIGFPE";
    default: return "other";
    }
}

static void sylvia_crash_handler(int sig, siginfo_t *info, void *context) {
    int saved_errno = errno;
    pthread_t self = pthread_self();
    uintptr_t top = (uintptr_t)pthread_get_stackaddr_np(self);
    uintptr_t size = (uintptr_t)pthread_get_stacksize_np(self);
    uintptr_t bottom = top - size;
    uintptr_t fault = info ? (uintptr_t)info->si_addr : 0;
    uintptr_t sp = 0;
    if (context != NULL) {
        ucontext_t *uc = (ucontext_t *)context;
#if defined(__arm64__)
        sp = (uintptr_t)__darwin_arm_thread_state64_get_sp(uc->uc_mcontext->__ss);
#elif defined(__x86_64__)
        sp = (uintptr_t)uc->uc_mcontext->__ss.__rsp;
#endif
    }
    int memory_fault = sig == SIGSEGV || sig == SIGBUS;
    int fault_below_stack = fault < bottom && bottom - fault <= (uintptr_t)(1 << 20);
    int sp_at_limit = sp != 0 && sp < bottom + 16 * 1024;
    int overflow = memory_fault && (fault_below_stack || sp_at_limit);

    char name[64];
    name[0] = 0;
    if (pthread_getname_np(self, name, sizeof(name)) != 0) name[0] = 0;
    for (size_t i = 0; name[i]; i++) if (name[i] == ' ' || name[i] == '\n') name[i] = '_';

    char line[512];
    size_t n = 0, cap = sizeof(line);
    n = sylvia_put(line, n, cap, "signal=");
    n = sylvia_put(line, n, cap, sylvia_signal_name(sig));
    n = sylvia_put(line, n, cap, " code=");
    n = sylvia_put_dec(line, n, cap, info ? info->si_code : 0);
    n = sylvia_put(line, n, cap, " fault_address=");
    n = sylvia_put_hex(line, n, cap, fault);
    n = sylvia_put(line, n, cap, " sp=");
    n = sylvia_put_hex(line, n, cap, sp);
    n = sylvia_put(line, n, cap, " stack_limit=");
    n = sylvia_put_hex(line, n, cap, bottom);
    n = sylvia_put(line, n, cap, " stack_top=");
    n = sylvia_put_hex(line, n, cap, top);
    n = sylvia_put(line, n, cap, " thread=");
    n = sylvia_put(line, n, cap, name[0] ? name : "unnamed");
    n = sylvia_put(line, n, cap, overflow ? " kind=stack-overflow\n" : " kind=other\n");
    if (sylvia_crash_fd >= 0) (void)write(sylvia_crash_fd, line, n);

    signal(sig, SIG_DFL);
    // A signal sent by kill() or abort() would not recur on return; send it again with the default action.
    if (info == NULL || info->si_code == SI_USER || sig == SIGABRT) raise(sig);
    errno = saved_errno;
}

__attribute__((constructor)) static void sylvia_crash_recorder_install(void) {
    const char *path = getenv("SYLVIA_CRASH_SIGNAL_FILE");
    if (path == NULL || path[0] == 0) return;
    sylvia_crash_fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (sylvia_crash_fd < 0) return;
    sylvia_install_altstack();
    sylvia_previous_hook = pthread_introspection_hook_install(sylvia_thread_hook);
    const int signals[] = {SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGABRT, SIGFPE};
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++) {
        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_sigaction = sylvia_crash_handler;
        action.sa_flags = SA_SIGINFO | SA_ONSTACK;
        sigemptyset(&action.sa_mask);
        sigaction(signals[i], &action, NULL);
    }
    char line[96];
    size_t n = sylvia_put(line, 0, sizeof(line), "recorder=installed process=");
    n = sylvia_put_dec(line, n, sizeof(line), (long)getpid());
    n = sylvia_put(line, n, sizeof(line), "\n");
    (void)write(sylvia_crash_fd, line, n);
}
