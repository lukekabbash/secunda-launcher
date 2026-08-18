#include <windows.h>

enum
{
    OBSERVED_ENTRY = 0x10040000
};

static volatile LONG watched_value;
static volatile LONG handler_count;

static void report_stage(const char *stage)
{
    DWORD length = 0, written;

    while (stage[length]) ++length;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), stage, length, &written, NULL);
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), "\r\n", 2, &written, NULL);
}

static int (*build_observed_entry(void))(void)
{
    static const BYTE code[] = {
        0xb8, 0x2a, 0x00, 0x00, 0x00, /* move 42 into the return register */
        0xc3
    };
    DWORD old_protection;
    BYTE *entry;
    entry = VirtualAlloc(
        (void *)OBSERVED_ENTRY, 0x4000,
        MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE
    );
    if (entry != (BYTE *)OBSERVED_ENTRY) return NULL;
    CopyMemory(entry, code, sizeof(code));
    if (!VirtualProtect(entry, 0x4000, PAGE_EXECUTE_READ, &old_protection))
        return NULL;
    if (!FlushInstructionCache(GetCurrentProcess(), entry, sizeof(code)))
        return NULL;
    return (int (*)(void))entry;
}

static LONG WINAPI watch_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;

    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP)
        return EXCEPTION_CONTINUE_SEARCH;
    InterlockedIncrement(&handler_count);
    context->Dr6 = 0;
    context->Dr7 = 0;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI execute_worker(void *parameter)
{
    int (*observed)(void) = parameter;

    watched_value = 1;
    if (handler_count != 1) return 24;
    report_stage("EXECUTE_ENTRY_SMOKE stage=calling");
    if (observed() != 42) return 23;
    report_stage("EXECUTE_ENTRY_SMOKE stage=returned");
    return 42;
}

int main(void)
{
    CONTEXT context = {0};
    DWORD thread_id, status;
    HANDLE thread;
    int (*observed)(void);

    observed = build_observed_entry();
    if (!observed) return 10;
    if (!AddVectoredExceptionHandler(1, watch_handler)) return 11;
    thread = CreateThread(
        NULL, 0, execute_worker, observed, CREATE_SUSPENDED, &thread_id
    );
    if (!thread) return 10;
    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    if (!GetThreadContext(thread, &context)) return 11;
    context.Dr0 = (DWORD_PTR)&watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(thread, &context)) return 12;
    if (ResumeThread(thread) == (DWORD)-1) return 13;
    if (WaitForSingleObject(thread, INFINITE) != WAIT_OBJECT_0) return 14;
    if (!GetExitCodeThread(thread, &status)) return 15;
    CloseHandle(thread);
    return status == 42 ? 0 : 16;
}
