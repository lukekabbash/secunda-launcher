#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>

#define WORKER_COUNT 2
#define STRESS_ROUNDS 32
#define EXPECTED_DR6 0xffff0ff1UL

struct worker_state
{
    HANDLE thread;
    DWORD thread_id;
    volatile LONG watched_value;
    volatile LONG transitioned;
    volatile LONG breakpoint_hits;
};

typedef void (*target_function)(void);

static struct worker_state workers[WORKER_COUNT];
static volatile LONG ready_count;
static volatile LONG start_workers;
static volatile LONG foreign_worker_entered;
static volatile LONG foreign_worker_release;
static volatile LONG foreign_worker_completed;
static volatile LONG foreign_watched_value;
static volatile LONG foreign_breakpoint_hits;
static volatile DWORD foreign_thread_id;
static volatile LONG owner_worker_release;
static volatile LONG executed_count;
static volatile LONG failure_code;
static volatile LONG completed_rounds;
static target_function execute_target;
static target_function foreign_target;
static target_function completion_target;

static void report_state(const char *event, LONG exit_code)
{
    char line[320];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_DEBUG_CONCURRENCY event=%s rounds=%ld ready=%ld transitions=%ld,%ld hits=%ld,%ld foreign_entered=%ld foreign_complete=%ld executed=%ld failure=%ld exit=%ld\r\n",
        event,
        completed_rounds,
        ready_count,
        workers[0].transitioned,
        workers[1].transitioned,
        workers[0].breakpoint_hits,
        workers[1].breakpoint_hits,
        foreign_worker_entered,
        foreign_worker_completed,
        executed_count,
        failure_code,
        exit_code
    );

    if (length <= 0) return;
    if (length >= (int)sizeof(line)) length = sizeof(line) - 1;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, length, &written, NULL);
}

static struct worker_state *current_worker(void)
{
    DWORD thread_id = GetCurrentThreadId();
    unsigned int index;

    for (index = 0; index < WORKER_COUNT; ++index)
        if (workers[index].thread_id == thread_id) return &workers[index];
    return NULL;
}

static BOOL allocate_execute_targets(void)
{
    BYTE *code = VirtualAlloc(NULL, 65536, MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    BYTE *foreign_code;

    if (!code) return FALSE;

    /* Keep the foreign path on the same host page as the watched entry. Its
     * first instruction announces entry, then an in-page wait loop holds the
     * temporary execute window open until both owner threads have attempted
     * their watched entry. A correct relay must keep the owners from slipping
     * through that process-wide window. */
    execute_target = (target_function)(code + 0x100);
    foreign_target = (target_function)(code + 0x800);
    completion_target = (target_function)(code + 0x4100);
    ((BYTE *)execute_target)[0] = 0xc3;
    ((BYTE *)completion_target)[0] = 0xc3;

    foreign_code = (BYTE *)foreign_target;
    foreign_code[0] = 0xf0; /* lock incl absolute-address */
    foreign_code[1] = 0xff;
    foreign_code[2] = 0x05;
    *(DWORD *)(foreign_code + 3) = (DWORD_PTR)&foreign_worker_entered;
    foreign_code[7] = 0xf0; /* lock incl watched absolute-address */
    foreign_code[8] = 0xff;
    foreign_code[9] = 0x05;
    *(DWORD *)(foreign_code + 10) = (DWORD_PTR)&foreign_watched_value;
    foreign_code[14] = 0x83; /* cmpl $0, absolute-address */
    foreign_code[15] = 0x3d;
    *(DWORD *)(foreign_code + 16) = (DWORD_PTR)&foreign_worker_release;
    foreign_code[20] = 0x00;
    foreign_code[21] = 0x74; /* je back to the comparison */
    foreign_code[22] = 0xf7;
    foreign_code[23] = 0xc3;

    return FlushInstructionCache(GetCurrentProcess(), code, 0x4200);
}

static LONG WINAPI debug_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;
    struct worker_state *worker = current_worker();

    if (GetCurrentThreadId() == foreign_thread_id)
    {
        if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP ||
            context->Dr0 != (DWORD_PTR)&foreign_watched_value ||
            context->Dr6 != EXPECTED_DR6 ||
            (context->Dr7 & 0x000f0001) != 0x000d0001 ||
            foreign_watched_value != 1 || foreign_breakpoint_hits)
        {
            InterlockedCompareExchange(&failure_code, 23, 0);
            return EXCEPTION_CONTINUE_SEARCH;
        }

        InterlockedIncrement(&foreign_breakpoint_hits);
        context->Dr6 = 0;
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (!worker || exception->ExceptionRecord->ExceptionCode != EXCEPTION_SINGLE_STEP)
    {
        InterlockedCompareExchange(&failure_code, 21, 0);
        return EXCEPTION_CONTINUE_SEARCH;
    }

    if (!worker->transitioned)
    {
        if (context->Dr0 != (DWORD_PTR)&worker->watched_value ||
            context->Dr6 != EXPECTED_DR6 ||
            (context->Dr7 & 0x000f0001) != 0x000d0001)
        {
            InterlockedCompareExchange(&failure_code, 22, 0);
            return EXCEPTION_CONTINUE_SEARCH;
        }

        InterlockedExchange(&worker->transitioned, 1);
        context->Dr0 = (DWORD_PTR)execute_target;
        context->Dr1 = 0;
        context->Dr2 = 0;
        context->Dr3 = 0;
        context->Dr6 = 0;
        context->Dr7 = 1;
        return EXCEPTION_CONTINUE_EXECUTION;
    }

    if (exception->ExceptionRecord->ExceptionAddress != (void *)execute_target ||
        context->Eip != (DWORD_PTR)execute_target ||
        context->Dr6 != EXPECTED_DR6 ||
        !(context->EFlags & 0x10000))
    {
        InterlockedCompareExchange(&failure_code, 21, 0);
        return EXCEPTION_CONTINUE_SEARCH;
    }

    InterlockedIncrement(&worker->breakpoint_hits);
    context->Eip = (DWORD_PTR)completion_target;
    context->Dr6 = 0;
    return EXCEPTION_CONTINUE_EXECUTION;
}

static DWORD WINAPI worker_main(void *unused)
{
    struct worker_state *worker = unused;

    worker->watched_value = 1;
    InterlockedIncrement(&ready_count);
    while (!start_workers) Sleep(0);
    while (!foreign_worker_entered) Sleep(0);
    execute_target();
    InterlockedIncrement(&executed_count);
    while (!owner_worker_release) Sleep(0);
    return 0;
}

static DWORD WINAPI foreign_worker_main(void *unused)
{
    (void)unused;

    while (!start_workers) Sleep(0);
    foreign_target();
    InterlockedExchange(&foreign_worker_completed, 1);
    return 0;
}

static int configure_foreign_worker(HANDLE *thread_out)
{
    CONTEXT context = {0};
    HANDLE thread;
    DWORD thread_id;

    thread = CreateThread(
        NULL, 0, foreign_worker_main, NULL, CREATE_SUSPENDED,
        &thread_id);
    if (!thread) return 16;
    foreign_thread_id = thread_id;

    /* A foreign thread can carry data watchpoints while it crosses a page
     * guarded for another thread's execute breakpoint. Refreshing those debug
     * registers must not discard the internal step needed to leave the page. */
    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)&foreign_watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(thread, &context))
    {
        CloseHandle(thread);
        return 17;
    }
    if (ResumeThread(thread) == (DWORD)-1)
    {
        CloseHandle(thread);
        return 17;
    }

    *thread_out = thread;
    return 0;
}

static int configure_worker(unsigned int index)
{
    CONTEXT context = {0};

    workers[index].thread = CreateThread(
        NULL,
        0,
        worker_main,
        &workers[index],
        CREATE_SUSPENDED,
        &workers[index].thread_id
    );
    if (!workers[index].thread) return 10 + index;

    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    context.Dr0 = (DWORD_PTR)&workers[index].watched_value;
    context.Dr6 = 0;
    context.Dr7 = 1 | (1 << 16) | (3 << 18);
    if (!SetThreadContext(workers[index].thread, &context)) return 12 + index;
    if (ResumeThread(workers[index].thread) == (DWORD)-1) return 14 + index;
    return 0;
}

static void reset_round_state(void)
{
    ZeroMemory(workers, sizeof(workers));
    ready_count = 0;
    start_workers = 0;
    foreign_worker_entered = 0;
    foreign_worker_release = 0;
    foreign_worker_completed = 0;
    foreign_watched_value = 0;
    foreign_breakpoint_hits = 0;
    foreign_thread_id = 0;
    owner_worker_release = 0;
    executed_count = 0;
    failure_code = 0;
}

static int run_round(void)
{
    HANDLE handles[WORKER_COUNT];
    HANDLE foreign_worker;
    DWORD wait_status;
    ULONGLONG deadline;
    unsigned int index;
    int status;

    reset_round_state();

    for (index = 0; index < WORKER_COUNT; ++index)
    {
        if ((status = configure_worker(index)))
        {
            report_state("configure-worker-failed", status);
            return status;
        }
        handles[index] = workers[index].thread;
    }

    while (ready_count != WORKER_COUNT) Sleep(0);
    if ((status = configure_foreign_worker(&foreign_worker)))
    {
        report_state("configure-foreign-worker-failed", status);
        return status;
    }
    InterlockedExchange(&start_workers, 1);

    /* The foreign thread announces its in-page wait before the owners attempt
     * the watched entry. A correct process-wide page relay keeps the owners
     * suspended until this foreign traversal is released and the page is
     * guarded again. */
    deadline = GetTickCount64() + 10000;
    while (!failure_code && !foreign_worker_entered &&
           GetTickCount64() < deadline)
        Sleep(0);
    if (failure_code || !foreign_worker_entered)
    {
        InterlockedExchange(&foreign_worker_release, 1);
        InterlockedExchange(&owner_worker_release, 1);
        report_state("foreign-worker-entry-timeout", 19);
        return 19;
    }
    InterlockedExchange(&foreign_worker_release, 1);

    deadline = GetTickCount64() + 10000;
    while (!failure_code &&
           (executed_count != WORKER_COUNT ||
            workers[0].breakpoint_hits != 1 ||
            workers[1].breakpoint_hits != 1) &&
           GetTickCount64() < deadline)
        Sleep(0);
    if (failure_code || executed_count != WORKER_COUNT ||
        workers[0].breakpoint_hits != 1 ||
        workers[1].breakpoint_hits != 1)
    {
        InterlockedExchange(&owner_worker_release, 1);
        report_state("owner-breakpoint-timeout", 18);
        return 18;
    }

    if (WaitForSingleObject(foreign_worker, 10000) != WAIT_OBJECT_0)
    {
        InterlockedExchange(&owner_worker_release, 1);
        report_state("foreign-worker-timeout", 19);
        CloseHandle(foreign_worker);
        return 19;
    }
    CloseHandle(foreign_worker);
    InterlockedExchange(&owner_worker_release, 1);
    wait_status = WaitForMultipleObjects(WORKER_COUNT, handles, TRUE, 10000);
    for (index = 0; index < WORKER_COUNT; ++index) CloseHandle(handles[index]);
    if (wait_status != WAIT_OBJECT_0)
    {
        report_state("worker-timeout", 18);
        return 18;
    }
    if (failure_code)
    {
        report_state("handler-validation-failed", failure_code);
        return failure_code;
    }
    if (!foreign_worker_completed || foreign_watched_value != 1 ||
        foreign_breakpoint_hits != 1 || executed_count != WORKER_COUNT ||
        workers[0].breakpoint_hits != 1 ||
        workers[1].breakpoint_hits != 1)
    {
        report_state("breakpoint-missed", 20);
        return 20;
    }

    InterlockedIncrement(&completed_rounds);
    return 0;
}

int main(void)
{
    unsigned int round;
    int status;

    report_state("start", 0);
    if (!allocate_execute_targets())
    {
        report_state("allocate-targets-failed", 8);
        return 8;
    }
    if (!AddVectoredExceptionHandler(1, debug_handler))
    {
        report_state("add-handler-failed", 9);
        return 9;
    }

    for (round = 0; round < STRESS_ROUNDS; ++round)
        if ((status = run_round())) return status;

    VirtualFree((BYTE *)execute_target - 0x100, 0, MEM_RELEASE);
    report_state("complete", 0);
    return 0;
}
