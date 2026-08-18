#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

enum trap_mode
{
    TRAP_MODE_TRACE,
    TRAP_MODE_BREAKPOINT
};

static volatile LONG __attribute__((aligned(64))) watched_value;
static volatile LONG handler_count;
static volatile LONG failure_code;
static volatile DWORD_PTR expected_ip;
static enum trap_mode mode;

static void report_state(const char *event, LONG exit_code)
{
    char line[192];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_DEBUG_TRAP event=%s mode=%s handlers=%ld failure=%ld exit=%ld\r\n",
        event,
        mode == TRAP_MODE_TRACE ? "trace" : "breakpoint",
        handler_count,
        failure_code,
        exit_code
    );

    if (length <= 0) return;
    if (length >= (int)sizeof(line)) length = sizeof(line) - 1;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, length, &written, NULL);
}

static LONG WINAPI trap_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;
    DWORD expected_code = mode == TRAP_MODE_TRACE
        ? EXCEPTION_SINGLE_STEP : EXCEPTION_BREAKPOINT;

    InterlockedIncrement(&handler_count);
    if (exception->ExceptionRecord->ExceptionCode != expected_code)
        InterlockedCompareExchange(&failure_code, 21, 0);
    if (mode == TRAP_MODE_TRACE &&
        (exception->ExceptionRecord->ExceptionAddress != (void *)expected_ip ||
         context->Eip != expected_ip || !(context->Dr6 & (1 << 14))))
        InterlockedCompareExchange(&failure_code, 22, 0);

    context->EFlags &= ~0x100;
    context->Dr6 = 0;
    context->Dr7 = 0;
    return failure_code ? EXCEPTION_CONTINUE_SEARCH : EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI trap_thread(void *unused)
{
    (void)unused;
    if (mode == TRAP_MODE_TRACE)
    {
        expected_ip = (DWORD_PTR)&&after_trace;
        __asm__ volatile(
            "pushfl\n\t"
            "orl $0x100,(%%esp)\n\t"
            "popfl\n\t"
            "nop"
            :
            :
            : "cc", "memory"
        );
after_trace:
        return 0;
    }

    __asm__ volatile("int3");
    return 0;
}

int main(int argc, char **argv)
{
    CONTEXT context = {0};
    HANDLE thread;
    DWORD thread_id, wait_status;

    if (argc != 2 || (strcmp(argv[1], "trace") && strcmp(argv[1], "breakpoint")))
    {
        fprintf(stderr, "usage: debug-register-trap-smoke.exe <trace|breakpoint>\n");
        return 64;
    }
    mode = !strcmp(argv[1], "trace") ? TRAP_MODE_TRACE : TRAP_MODE_BREAKPOINT;
    report_state("start", 0);
    if (!AddVectoredExceptionHandler(1, trap_handler)) return 10;
    thread = CreateThread(NULL, 0, trap_thread, NULL, CREATE_SUSPENDED, &thread_id);
    if (!thread) return 11;

    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)&watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(thread, &context)) return 12;
    if (ResumeThread(thread) == (DWORD)-1) return 13;

    wait_status = WaitForSingleObject(thread, 5000);
    CloseHandle(thread);
    if (wait_status != WAIT_OBJECT_0)
    {
        report_state("thread-timeout", 14);
        return 14;
    }
    if (failure_code || handler_count != 1)
    {
        report_state("validation-failed", failure_code ? failure_code : 23);
        return failure_code ? failure_code : 23;
    }
    report_state("complete", 0);
    return 0;
}
