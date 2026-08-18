#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

enum transition_stage
{
    STAGE_DATA_TO_EXECUTE,
    STAGE_FIRST_EXECUTE,
    STAGE_SECOND_EXECUTE,
    STAGE_RESTORED_DATA,
    STAGE_COMPLETE
};

static volatile LONG watched_value;
static volatile LONG first_target_calls;
static volatile LONG second_target_calls;
static volatile LONG redirect_calls;
static volatile LONG completion_calls;
static volatile LONG transition_stage;
static volatile LONG failure_code;
static volatile LONG handler_count;
static volatile DWORD_PTR expected_first_write_ip;
static volatile DWORD_PTR expected_second_write_ip;
static DWORD_PTR first_execute_target;
static DWORD_PTR redirect_target;
static DWORD_PTR second_execute_target;
static DWORD_PTR completion_target;

static void report_state(const char *event, LONG exit_code)
{
    char line[224];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_CEG_TRANSITION event=%s stage=%ld failure=%ld handlers=%ld exit=%ld\r\n",
        event, transition_stage, failure_code, handler_count, exit_code
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

static void write_increment_stub(BYTE *target, volatile LONG *counter)
{
    target[0] = 0xf0; /* lock incl absolute-address */
    target[1] = 0xff;
    target[2] = 0x05;
    *(DWORD *)(target + 3) = (DWORD_PTR)counter;
    target[7] = 0xc3; /* ret */
}

static BOOL build_transition_code(void)
{
    BYTE *code = VirtualAlloc(NULL, 3 * 0x4000, MEM_RESERVE | MEM_COMMIT,
                              PAGE_EXECUTE_READWRITE);
    BYTE *redirect;

    if (!code) return FALSE;
    first_execute_target = (DWORD_PTR)(code + 0x100);
    redirect_target = (DWORD_PTR)(code + 0x200);
    second_execute_target = (DWORD_PTR)(code + 0x4100);
    completion_target = (DWORD_PTR)(code + 0x8100);

    write_increment_stub((BYTE *)first_execute_target, &first_target_calls);
    write_increment_stub((BYTE *)second_execute_target, &second_target_calls);
    write_increment_stub((BYTE *)completion_target, &completion_calls);

    redirect = (BYTE *)redirect_target;
    write_increment_stub(redirect, &redirect_calls);
    redirect[7] = 0xe8; /* call relative-address */
    *(LONG *)(redirect + 8) = second_execute_target - (redirect_target + 12);
    redirect[12] = 0xc3;
    return FlushInstructionCache(GetCurrentProcess(), code, 3 * 0x4000);
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

static int valid_execute_step(EXCEPTION_POINTERS *exception,
                              DWORD_PTR expected_ip, DWORD hit_mask)
{
    return valid_single_step(exception, expected_ip, hit_mask) &&
           (exception->ContextRecord->EFlags & 0x10000);
}

static LONG WINAPI transition_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;
    LONG stage = transition_stage;

    InterlockedIncrement(&handler_count);
    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP)
    {
        InterlockedCompareExchange(&failure_code, 30, 0);
        return EXCEPTION_CONTINUE_SEARCH;
    }

    if (stage == STAGE_DATA_TO_EXECUTE)
    {
        if (!valid_single_step(exception, expected_first_write_ip, 1))
            fail_context(context, 21);
        else if (watched_value != 7)
            fail_context(context, 22);
        else
        {
            context->Dr0 = first_execute_target;
            context->Dr1 = redirect_target;
            context->Dr2 = second_execute_target;
            context->Dr3 = completion_target;
            context->Dr6 = 0;
            context->Dr7 = (1 << 0) | (1 << 4);
            InterlockedExchange(&transition_stage, STAGE_FIRST_EXECUTE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_FIRST_EXECUTE)
    {
        if (!valid_execute_step(exception, first_execute_target, 1))
            fail_context(context, 23);
        else if (first_target_calls != 0)
            fail_context(context, 24);
        else
        {
            context->Eip = context->Dr1;
            context->Dr7 = 1 << 4;
            InterlockedExchange(&transition_stage, STAGE_SECOND_EXECUTE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_SECOND_EXECUTE)
    {
        if (!valid_execute_step(exception, second_execute_target, 1 << 2))
            fail_context(context, 25);
        else if (second_target_calls != 0)
            fail_context(context, 26);
        else
        {
            context->Eip = context->Dr3;
            context->Dr0 = (DWORD_PTR)&watched_value;
            context->Dr1 = 0;
            context->Dr2 = 0;
            context->Dr3 = 0;
            context->Dr7 = 1 | (1 << 16) | (3 << 18);
            InterlockedExchange(&transition_stage, STAGE_RESTORED_DATA);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (stage == STAGE_RESTORED_DATA)
    {
        if (!valid_single_step(exception, expected_second_write_ip, 1))
            fail_context(context, 27);
        else if (watched_value != 11)
            fail_context(context, 28);
        else
        {
            context->Dr6 = 0;
            context->Dr7 = 0;
            InterlockedExchange(&transition_stage, STAGE_COMPLETE);
        }
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    fail_context(context, 29);
    return EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI transition_thread(void *unused)
{
    (void)unused;
    expected_first_write_ip = (DWORD_PTR)&&after_first_write;
    expected_second_write_ip = (DWORD_PTR)&&after_second_write;

    watched_value = 7;
after_first_write:
    ((void (*)(void))first_execute_target)();
    watched_value = 11;
after_second_write:
    return 0;
}

int main(void)
{
    CONTEXT context = {0};
    HANDLE thread;
    DWORD thread_id;
    DWORD wait_status;

    report_state("start", 0);
    if (!build_transition_code())
        return fail_startup("build-code-failed", 10);
    if (!AddVectoredExceptionHandler(1, transition_handler))
        return fail_startup("add-handler-failed", 11);

    thread = CreateThread(NULL, 0, transition_thread, NULL, CREATE_SUSPENDED, &thread_id);
    if (!thread) return fail_startup("create-thread-failed", 12);

    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)&watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(thread, &context))
        return fail_startup("set-context-failed", 13);
    if (ResumeThread(thread) == (DWORD)-1)
        return fail_startup("resume-thread-failed", 14);

    wait_status = WaitForSingleObject(thread, 5000);
    CloseHandle(thread);
    if (wait_status != WAIT_OBJECT_0)
        return fail_startup("thread-timeout", 15);
    if (failure_code)
        return fail_startup("handler-validation-failed", failure_code);
    if (transition_stage != STAGE_COMPLETE || watched_value != 11 ||
        first_target_calls != 0 || second_target_calls != 0 ||
        redirect_calls != 1 || completion_calls != 1 || handler_count != 4)
        return fail_startup("final-state-failed", 31);

    report_state("complete", 0);
    return 0;
}
