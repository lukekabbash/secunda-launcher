#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static volatile LONG target_calls;
static volatile LONG breakpoint_hits;
static BYTE original_opcode;
static void *target_address;

static __attribute__((noinline)) void breakpoint_target(void)
{
    InterlockedIncrement(&target_calls);
}

static LONG WINAPI breakpoint_handler(EXCEPTION_POINTERS *exception)
{
    CONTEXT *context = exception->ContextRecord;
    DWORD old_protect;

    if (exception->ExceptionRecord->ExceptionCode != EXCEPTION_BREAKPOINT ||
        exception->ExceptionRecord->ExceptionAddress != target_address)
        return EXCEPTION_CONTINUE_SEARCH;

    if (!VirtualProtect(target_address, 1, PAGE_EXECUTE_READWRITE, &old_protect))
        return EXCEPTION_CONTINUE_SEARCH;
    *(volatile BYTE *)target_address = original_opcode;
    FlushInstructionCache(GetCurrentProcess(), target_address, 1);
    VirtualProtect(target_address, 1, old_protect, &old_protect);

    context->Eip = (DWORD_PTR)target_address;
    InterlockedIncrement(&breakpoint_hits);
    return EXCEPTION_CONTINUE_EXECUTION;
}

static int arm_breakpoint(void *address)
{
    DWORD old_protect;

    target_address = address;
    if (!VirtualProtect(target_address, 1, PAGE_EXECUTE_READWRITE, &old_protect)) return 0;
    original_opcode = *(BYTE *)target_address;
    *(volatile BYTE *)target_address = 0xcc;
    FlushInstructionCache(GetCurrentProcess(), target_address, 1);
    return VirtualProtect(target_address, 1, old_protect, &old_protect);
}

static void *find_return_instruction(void)
{
    BYTE *code = (BYTE *)breakpoint_target;
    unsigned int index;

    for (index = 1; index < 128; ++index)
        if (code[index] == 0xc3) return code + index;
    return NULL;
}

int main(void)
{
    void *return_address;

    breakpoint_target();
    if (!AddVectoredExceptionHandler(1, breakpoint_handler)) return 10;
    if (!arm_breakpoint((void *)breakpoint_target)) return 11;
    breakpoint_target();

    return_address = find_return_instruction();
    if (!return_address) return 12;
    if (!arm_breakpoint(return_address)) return 13;
    breakpoint_target();

    return target_calls == 3 && breakpoint_hits == 2 ? 0 : 14;
}
