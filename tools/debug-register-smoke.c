#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

enum debug_stage
{
    STAGE_FIRST_WRITE,
    STAGE_SECOND_WRITE,
    STAGE_READ,
    STAGE_FIRST_EXECUTE,
    STAGE_SECOND_EXECUTE,
    STAGE_COMPLETE
};

static volatile LONG watched_value;
static volatile LONG executed_value;
static volatile LONG gap_value;
static volatile LONG debug_stage;
static volatile LONG failure_code;
static volatile LONG handler_count;
static volatile DWORD_PTR expected_write_ip[2];
static volatile DWORD_PTR expected_read_ip;
static volatile DWORD_PTR expected_read_sp;
static volatile LONG read_value;

static void report_state(const char *event, LONG exit_code)
{
    char line[192];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_DEBUG_SMOKE event=%s stage=%ld failure=%ld handlers=%ld exit=%ld\r\n",
        event, debug_stage, failure_code, handler_count, exit_code
    );

    if (length <= 0) return;
    if (length >= (int)sizeof(line)) length = sizeof(line) - 1;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, length, &written, NULL);
}

static int fail_startup(const char *event, int exit_code)
{
    report_state(event, exit_code);
    return exit_code;
}

/* Two 8 KB alignments keep the target beyond a 16 KB host-page boundary. The
 * translated CEG-shaped path changes debug state on one code page, then enters
 * a protected target page later. */
static __attribute__((noinline, used, aligned(8192))) void target_page_gap(void)
{
}

static __attribute__((noinline, aligned(8192))) void execute_target(void)
{
    InterlockedIncrement(&executed_value);
}

static __attribute__((noinline)) void execute_gap(void)
{
    LONG index;

    /* Ensure the translated execute-breakpoint search crosses multiple guest
     * instructions. None of its internal trace events may reach Windows. */
    for (index = 0; index < 32; ++index)
        InterlockedExchangeAdd(&gap_value, index + 1);
}

static void fail_context(CONTEXT *context, LONG code)
{
    InterlockedCompareExchange(&failure_code, code, 0);
    context->Dr6 = 0;
    context->Dr7 = 0;
}

static int valid_single_step(EXCEPTION_POINTERS *exception, DWORD_PTR expected_ip,
                             DWORD hit_mask)
{
    CONTEXT *context = exception->ContextRecord;

    return exception->ExceptionRecord->ExceptionCode == EXCEPTION_SINGLE_STEP &&
           exception->ExceptionRecord->ExceptionAddress == (void *)expected_ip &&
           context->Eip == expected_ip &&
           context->Dr6 == (0xffff0ff0UL | hit_mask) &&
           !(context->Dr6 & (1 << 14)) &&
           !(context->EFlags & 0x100);
}

static int valid_data_read(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;

    return valid_single_step(exception, expected_read_ip, 1 << 1) &&
           context->Esp == expected_read_sp &&
           context->Eax == 11;
}

static int valid_execute_single_step(EXCEPTION_POINTERS *exception,
                                     DWORD_PTR expected_ip)
{
    return valid_single_step(exception, expected_ip, 1 << 2) &&
           (exception->ContextRecord->EFlags & 0x10000);
}

static LONG WINAPI debug_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;
    LONG stage = debug_stage;
    LONG count = InterlockedIncrement(&handler_count);

    if (count <= 16) report_state("handler-enter", 0);

    /* Never consume an unrelated fault. Swallowing it would turn one bad
     * resume into an infinite exception loop and hide the first failure. */
    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP)
    {
        InterlockedCompareExchange(&failure_code, 30, 0);
        return EXCEPTION_CONTINUE_SEARCH;
    }

    if (stage == STAGE_FIRST_WRITE)
    {
        if (!valid_single_step(exception, expected_write_ip[0], 1))
            fail_context(context, 21);
        else if (watched_value != 7)
            fail_context(context, 22);
        else if ((context->Dr7 & 0x000f0001) != 0x000d0001)
            fail_context(context, 23);
        else
        {
            context->Dr6 = 0;
            InterlockedExchange(&debug_stage, STAGE_SECOND_WRITE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_SECOND_WRITE)
    {
        if (!valid_single_step(exception, expected_write_ip[1], 1))
            fail_context(context, 24);
        else if (watched_value != 11)
            fail_context(context, 25);
        else
        {
            context->Dr0 = 0;
            context->Dr1 = (DWORD_PTR)&watched_value;
            context->Dr6 = 0;
            context->Dr7 = (1 << 2) | (3 << 20) | (3 << 22);
            InterlockedExchange(&debug_stage, STAGE_READ);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_READ)
    {
        if (!valid_data_read(exception))
            fail_context(context, 26);
        else
        {
            /* Exercise the protected transition from a four-byte data
             * watchpoint to an execute breakpoint in the same continuation. */
            context->Dr0 = 0;
            context->Dr1 = 0;
            context->Dr2 = (DWORD_PTR)execute_target;
            context->Dr3 = 0;
            context->Dr6 = 0;
            context->Dr7 = 1 << 4;
            InterlockedExchange(&debug_stage, STAGE_FIRST_EXECUTE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_FIRST_EXECUTE)
    {
        if (!valid_execute_single_step(exception, (DWORD_PTR)execute_target))
            fail_context(context, 27);
        else if (executed_value != 0)
            fail_context(context, 28);
        else
        {
            context->Dr6 = 0;
            InterlockedExchange(&debug_stage, STAGE_SECOND_EXECUTE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_SECOND_EXECUTE)
    {
        if (!valid_execute_single_step(exception, (DWORD_PTR)execute_target))
            fail_context(context, 29);
        else if (executed_value != 1)
            fail_context(context, 31);
        else
        {
            context->Dr6 = 0;
            context->Dr7 = 0;
            InterlockedExchange(&debug_stage, STAGE_COMPLETE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    fail_context(context, 32);
    return EXCEPTION_CONTINUE_EXECUTION;
}

static __attribute__((noinline)) void read_watched_value(void)
{
    __asm__ volatile(
        "movl $1f,%0\n\t"
        "movl %%esp,%1\n\t"
        "movl %3,%%eax\n\t"
        "1:\n\t"
        "movl %%eax,%2"
        : "=m" (expected_read_ip), "=m" (expected_read_sp),
          "=m" (read_value)
        : "m" (watched_value)
        : "eax", "memory");
}

static DWORD WINAPI watched_thread(void *unused)
{
    (void)unused;
    report_state("worker-start", 0);
    expected_write_ip[0] = (DWORD_PTR)&&after_first_write;
    expected_write_ip[1] = (DWORD_PTR)&&after_second_write;

    watched_value = 7;
after_first_write:
    watched_value = 11;
after_second_write:
    read_watched_value();
    execute_gap();
    execute_target();
    execute_gap();
    execute_target();
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
        return fail_startup("add-handler-failed", 10);
    report_state("handler-installed", 0);
    thread = CreateThread(NULL, 0, watched_thread, NULL, CREATE_SUSPENDED, &thread_id);
    if (!thread) return fail_startup("create-thread-failed", 11);
    report_state("thread-created", 0);

    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)&watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    report_state("set-context-begin", 0);
    if (!SetThreadContext(thread, &context))
        return fail_startup("set-context-failed", 12);
    report_state("set-context-complete", 0);
    if (ResumeThread(thread) == (DWORD)-1)
        return fail_startup("resume-thread-failed", 13);
    report_state("thread-resumed", 0);

    wait_status = WaitForSingleObject(thread, 5000);
    CloseHandle(thread);
    if (wait_status != WAIT_OBJECT_0)
        return fail_startup("thread-timeout", 14);
    if (failure_code)
        return fail_startup("handler-validation-failed", failure_code);
    if (watched_value != 11 || read_value != 11 || executed_value != 2 ||
        gap_value != 1056 ||
        debug_stage != STAGE_COMPLETE)
        return fail_startup("final-state-failed", 33);
    report_state("complete", 0);
    return 0;
}
