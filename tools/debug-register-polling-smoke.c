#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

#define EXPECTED_DR6 0xffff0ff1UL
#ifndef POLL_ROUNDS
#define POLL_ROUNDS 4096
#endif

typedef void (*target_function)(void);

static volatile LONG watched_value;
static volatile LONG owner_armed;
static volatile LONG owner_ready;
static volatile LONG start_owner;
static volatile LONG owner_completed;
static volatile LONG poller_entered;
static volatile LONG poller_succeeded;
static volatile LONG poller_timed_out;
static volatile LONG handler_count;
static volatile LONG failure_code;
static volatile DWORD_PTR expected_write_ip;
static volatile DWORD owner_thread_id;
static target_function execute_target;
static target_function polling_target;
static target_function completion_target;

static void report_state(const char *event, LONG exit_code)
{
    char line[256];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_DEBUG_POLLING event=%s armed=%ld ready=%ld started=%ld completed=%ld entered=%ld succeeded=%ld timed_out=%ld handlers=%ld failure=%ld exit=%ld\r\n",
        event, owner_armed, owner_ready, start_owner, owner_completed,
        poller_entered, poller_succeeded, poller_timed_out, handler_count,
        failure_code, exit_code
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

static void write_increment_stub(BYTE *target, volatile LONG *counter)
{
    target[0] = 0xf0; /* lock incl absolute-address */
    target[1] = 0xff;
    target[2] = 0x05;
    *(DWORD *)(target + 3) = (DWORD_PTR)counter;
    target[7] = 0xc3;
}

static BOOL build_test_code(void)
{
    BYTE *code = VirtualAlloc(NULL, 2 * 0x4000, MEM_RESERVE | MEM_COMMIT,
                              PAGE_EXECUTE_READWRITE);
    BYTE *poll;

    if (!code) return FALSE;
    execute_target = (target_function)(code + 0x100);
    polling_target = (target_function)(code + 0x800);
    completion_target = (target_function)(code + 0x4100);
    ((BYTE *)execute_target)[0] = 0xc3;
    write_increment_stub((BYTE *)completion_target, &owner_completed);

    poll = (BYTE *)polling_target;
    poll[0] = 0xf0; /* lock incl absolute-address */
    poll[1] = 0xff;
    poll[2] = 0x05;
    *(DWORD *)(poll + 3) = (DWORD_PTR)&poller_entered;
    poll[7] = 0xb9; /* movl $POLL_ROUNDS, %ecx */
    *(DWORD *)(poll + 8) = POLL_ROUNDS;
    poll[12] = 0x83; /* cmpl $0, absolute-address */
    poll[13] = 0x3d;
    *(DWORD *)(poll + 14) = (DWORD_PTR)&owner_completed;
    poll[18] = 0x00;
    poll[19] = 0x75; /* jne success */
    poll[20] = 0x0a;
    poll[21] = 0xe2; /* loop comparison */
    poll[22] = 0xf5;
    poll[23] = 0xf0; /* lock incl absolute-address */
    poll[24] = 0xff;
    poll[25] = 0x05;
    *(DWORD *)(poll + 26) = (DWORD_PTR)&poller_timed_out;
    poll[30] = 0xc3;
    poll[31] = 0xf0; /* success: lock incl absolute-address */
    poll[32] = 0xff;
    poll[33] = 0x05;
    *(DWORD *)(poll + 34) = (DWORD_PTR)&poller_succeeded;
    poll[38] = 0xc3;

    return FlushInstructionCache(GetCurrentProcess(), code, 2 * 0x4000);
}

static void clear_debug_state(CONTEXT *context, LONG code)
{
    InterlockedCompareExchange(&failure_code, code, 0);
    context->Dr6 = 0;
    context->Dr7 = 0;
}

static LONG WINAPI debug_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;

    if (GetCurrentThreadId() != owner_thread_id ||
        exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP)
        return EXCEPTION_CONTINUE_SEARCH;

    InterlockedIncrement(&handler_count);
    if (!owner_armed)
    {
        if (exception->ExceptionRecord->ExceptionAddress != (void *)expected_write_ip ||
            context->Eip != expected_write_ip || context->Dr6 != EXPECTED_DR6 ||
            (context->EFlags & 0x100))
            clear_debug_state(context, 21);
        else
        {
            context->Dr0 = (DWORD_PTR)execute_target;
            context->Dr6 = 0;
            context->Dr7 = 1;
            InterlockedExchange(&owner_armed, 1);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (exception->ExceptionRecord->ExceptionAddress != (void *)execute_target ||
        context->Eip != (DWORD_PTR)execute_target ||
        context->Dr6 != EXPECTED_DR6 || !(context->EFlags & 0x10000))
        clear_debug_state(context, 22);
    else
    {
        context->Eip = (DWORD_PTR)completion_target;
        context->Dr6 = 0;
        context->Dr7 = 0;
    }
    return EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI owner_main(void *unused)
{
    (void)unused;
    expected_write_ip = (DWORD_PTR)&&after_write;
    watched_value = 1;
after_write:
    InterlockedExchange(&owner_ready, 1);
    while (!start_owner) Sleep(0);
    execute_target();
    return 0;
}

static DWORD WINAPI poller_main(void *unused)
{
    (void)unused;
    while (!owner_ready) Sleep(0);
    polling_target();
    return 0;
}

int main(void)
{
    CONTEXT context = {0};
    HANDLE owner;
    HANDLE poller;
    HANDLE threads[2];
    DWORD poller_thread_id;
    DWORD wait_status;
    ULONGLONG deadline;

    report_state("start", 0);
    if (!build_test_code()) return fail("build-code-failed", 10);
    if (!AddVectoredExceptionHandler(1, debug_handler))
        return fail("add-handler-failed", 11);

    owner = CreateThread(NULL, 0, owner_main, NULL, CREATE_SUSPENDED,
                         (DWORD *)&owner_thread_id);
    if (!owner) return fail("create-owner-failed", 12);
    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)&watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(owner, &context))
        return fail("set-owner-context-failed", 13);
    if (ResumeThread(owner) == (DWORD)-1)
        return fail("resume-owner-failed", 14);

    poller = CreateThread(NULL, 0, poller_main, NULL, 0, &poller_thread_id);
    if (!poller) return fail("create-poller-failed", 15);

    deadline = GetTickCount64() + 5000;
    while (!failure_code && !poller_entered && GetTickCount64() < deadline)
        Sleep(0);
    if (failure_code || !poller_entered)
        return fail("poller-entry-timeout", 16);

    InterlockedExchange(&start_owner, 1);
    threads[0] = owner;
    threads[1] = poller;
    wait_status = WaitForMultipleObjects(2, threads, TRUE, 10000);
    CloseHandle(owner);
    CloseHandle(poller);
    if (wait_status != WAIT_OBJECT_0)
        return fail("thread-timeout", 17);
    if (failure_code)
        return fail("handler-validation-failed", failure_code);
    if (!owner_completed || !poller_succeeded || poller_timed_out ||
        handler_count != 2)
        return fail("owner-starved-by-page-poller", 18);

    report_state("complete", 0);
    return 0;
}
