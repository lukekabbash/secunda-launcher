#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

static volatile unsigned char target_bytes[8] __attribute__((aligned(8)));
static volatile ULONGLONG source_value = 0x8877665544332211ULL;
static volatile DWORD_PTR expected_ip;
static volatile LONG handler_count;
static volatile LONG failure_code;

static void report_state(const char *event, LONG exit_code)
{
    char line[192];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_DEBUG_OVERLAP event=%s handlers=%ld failure=%ld exit=%ld\r\n",
        event, handler_count, failure_code, exit_code
    );

    if (length <= 0) return;
    if (length >= (int)sizeof(line)) length = sizeof(line) - 1;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, length, &written, NULL);
}

static int fail(const char *event, int exit_code)
{
    report_state(event, exit_code);
    return exit_code;
}

static LONG WINAPI debug_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;

    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP)
        return EXCEPTION_CONTINUE_SEARCH;

    InterlockedIncrement(&handler_count);
    if (exception->ExceptionRecord->ExceptionAddress != (void *)expected_ip ||
        context->Eip != expected_ip)
        InterlockedCompareExchange(&failure_code, 21, 0);
    else if (context->Dr6 != 0xffff0ff1UL || (context->EFlags & 0x100))
        InterlockedCompareExchange(&failure_code, 22, 0);
    else if (*(volatile DWORD *)(target_bytes + 4) != 0x88776655UL)
        InterlockedCompareExchange(&failure_code, 23, 0);

    context->Dr6 = 0;
    context->Dr7 = 0;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static __attribute__((noinline)) void write_across_watchpoint(void)
{
    __asm__ volatile(
        "movl $1f,%0\n\t"
        "movq %2,%%mm0\n\t"
        "movq %%mm0,(%1)\n\t"
        "1:\n\t"
        "emms"
        : "=m" (expected_ip)
        : "r" (target_bytes), "m" (source_value)
        : "memory"
    );
}

static DWORD WINAPI watched_thread(void *unused)
{
    (void)unused;
    write_across_watchpoint();
    return 0;
}

int main(void)
{
    CONTEXT context = {0};
    HANDLE thread;
    DWORD thread_id;
    DWORD wait_status;

    report_state("start", 0);
    if (!AddVectoredExceptionHandler(1, debug_handler))
        return fail("add-handler-failed", 10);

    thread = CreateThread(NULL, 0, watched_thread, NULL, CREATE_SUSPENDED, &thread_id);
    if (!thread) return fail("create-thread-failed", 11);

    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)(target_bytes + 4);
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(thread, &context))
        return fail("set-context-failed", 12);
    if (ResumeThread(thread) == (DWORD)-1)
        return fail("resume-thread-failed", 13);

    wait_status = WaitForSingleObject(thread, 5000);
    CloseHandle(thread);
    if (wait_status != WAIT_OBJECT_0)
        return fail("thread-timeout", 14);
    if (failure_code)
        return fail("handler-validation-failed", failure_code);
    if (handler_count != 1)
        return fail("unexpected-handler-count", 24);
    if (*(volatile ULONGLONG *)target_bytes != source_value)
        return fail("final-state-failed", 25);

    report_state("complete", 0);
    return 0;
}
