#include <windows.h>

#define EXIT_IMPORT_ADDRESS ((volatile ULONG_PTR *)(ULONG_PTR)0x10002284)

static void report_stage(const char *stage)
{
    DWORD length = 0, written;

    while (stage[length]) ++length;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), stage, length, &written, NULL);
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), "\r\n", 2, &written, NULL);
}

static DWORD WINAPI exit_worker(void *unused)
{
    HMODULE kernel32;
    FARPROC exit_process;
    DWORD old_protection, ignored;

    (void)unused;
    report_stage("EXIT_TRACE_SMOKE stage=worker");
    kernel32 = GetModuleHandleA("kernel32.dll");
    exit_process = kernel32 ? GetProcAddress(kernel32, "ExitProcess") : NULL;
    if (!exit_process) return 20;
    if (!VirtualProtect((void *)EXIT_IMPORT_ADDRESS, sizeof(*EXIT_IMPORT_ADDRESS),
                        PAGE_READWRITE, &old_protection)) return 21;
    *EXIT_IMPORT_ADDRESS = (ULONG_PTR)exit_process;
    if (!VirtualProtect((void *)EXIT_IMPORT_ADDRESS, sizeof(*EXIT_IMPORT_ADDRESS),
                        old_protection, &ignored)) return 22;
    report_stage("EXIT_TRACE_SMOKE stage=import-rewritten");
    ExitProcess(37);
    return 0;
}

int main(void)
{
    CONTEXT context = {0};
    DWORD thread_id;
    HANDLE thread;

    report_stage("EXIT_TRACE_SMOKE stage=main");
    thread = CreateThread(NULL, 0, exit_worker, NULL, CREATE_SUSPENDED, &thread_id);
    if (!thread) return 10;
    report_stage("EXIT_TRACE_SMOKE stage=created");

    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
    if (!GetThreadContext(thread, &context)) return 11;
    report_stage("EXIT_TRACE_SMOKE stage=context-read");
    /* Keep one harmless guest breakpoint armed so the relay owns this thread,
     * matching the protected startup path that the private observer extends. */
    context.Dr0 = (DWORD_PTR)main;
    context.Dr1 = 0;
    context.Dr2 = 0;
    context.Dr3 = 0;
    context.Dr6 = 0;
    context.Dr7 = 1;
    if (!SetThreadContext(thread, &context)) return 12;
    report_stage("EXIT_TRACE_SMOKE stage=context-written");
    if (ResumeThread(thread) == (DWORD)-1) return 13;
    report_stage("EXIT_TRACE_SMOKE stage=resumed");

    WaitForSingleObject(thread, INFINITE);
    return 14;
}
