#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>

enum
{
    SOURCE_ADDRESS = 0x38124000,
    SOURCE_SIZE = 0x1000,
    INITIAL_COPY_DWORDS = 15,
    BLOCK_COPY_DWORDS = 16,
    INITIAL_COPY_ADDRESS = 0x10010000,
    BLOCK_COPY_ADDRESS = 0x10020000,
    TAIL_COPY_ADDRESS = 0x10030000
};

static void report_state(const char *event, DWORD address, int exit_code)
{
    char line[192];
    DWORD written;
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_PROTECTED_HASH_COPY event=%s address=%08lx exit=%d\r\n",
        event, address, exit_code
    );

    if (length <= 0) return;
    if (length >= (int)sizeof(line)) length = sizeof(line) - 1;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, length, &written, NULL);
}

static void report_allocation_failure(const char *event, DWORD address)
{
    char line[224];
    DWORD written;
    DWORD error = GetLastError();
    int length = snprintf(
        line,
        sizeof(line),
        "SECUNDA_PROTECTED_HASH_COPY event=%s address=%08lx winerr=%lu exit=10\r\n",
        event, address, error
    );

    if (length <= 0) return;
    if (length >= (int)sizeof(line)) length = sizeof(line) - 1;
    WriteFile(GetStdHandle(STD_ERROR_HANDLE), line, length, &written, NULL);
}

static BYTE *build_copy_stub(DWORD address)
{
    DWORD allocation_base = address & ~0xffffUL;
    SIZE_T allocation_size = address - allocation_base + 3;
    BYTE *page = VirtualAlloc(
        (void *)allocation_base, allocation_size,
        MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE
    );
    BYTE *stub;

    if (!page) return NULL;
    stub = (BYTE *)address;
    stub[0] = 0xf3; /* repeat move doubleword */
    stub[1] = 0xa5;
    stub[2] = 0xc3;
    if (!FlushInstructionCache(GetCurrentProcess(), stub, 3)) return NULL;
    return stub;
}

static BYTE *build_tail_stub(DWORD address)
{
    static const BYTE code[] = {
        0x8b, 0x44, 0x8e, 0xfc,
        0x89, 0x44, 0x8f, 0xfc,
        0xc3
    };
    DWORD allocation_base = address & ~0xffffUL;
    SIZE_T allocation_size = address - allocation_base + sizeof(code);
    BYTE *page = VirtualAlloc(
        (void *)allocation_base, allocation_size,
        MEM_RESERVE | MEM_COMMIT, PAGE_EXECUTE_READWRITE
    );

    if (!page) return NULL;
    memcpy((void *)address, code, sizeof(code));
    if (!FlushInstructionCache(GetCurrentProcess(), (void *)address,
                               sizeof(code)))
        return NULL;
    return (BYTE *)address;
}

static void call_copy_stub(BYTE *stub, const DWORD *source, DWORD *destination,
                           DWORD count)
{
    DWORD source_address = (DWORD)(DWORD_PTR)source;
    DWORD destination_address = (DWORD)(DWORD_PTR)destination;
    DWORD stub_address = (DWORD)(DWORD_PTR)stub;
    __asm__ volatile(
        "pushl %%esi\n\t"
        "pushl %%edi\n\t"
        "movl %0, %%esi\n\t"
        "movl %1, %%edi\n\t"
        "movl %2, %%ecx\n\t"
        "movl %3, %%eax\n\t"
        "call *%%eax\n\t"
        "popl %%edi\n\t"
        "popl %%esi\n\t"
        :
        : "m"(source_address), "m"(destination_address),
          "m"(count), "m"(stub_address)
        : "eax", "ecx", "edx", "memory", "cc"
    );
}

static int run_copy(BYTE *stub, const DWORD *source, DWORD address, DWORD count)
{
    DWORD destination[BLOCK_COPY_DWORDS] = {0};
    SIZE_T copy_bytes = count * sizeof(DWORD);
    DWORD old_protection;
    MEMORY_BASIC_INFORMATION info;

    report_state("start", address, 0);
    call_copy_stub(stub, source, destination, count);
    if (VirtualQuery(source, &info, sizeof(info)) != sizeof(info) ||
        info.Protect != PAGE_NOACCESS)
    {
        report_state("protection-not-restored", address, 21);
        return 21;
    }
    if (!VirtualProtect((void *)source, SOURCE_SIZE, PAGE_READWRITE,
                        &old_protection))
    {
        report_state("comparison-unprotect-failed", address, 22);
        return 22;
    }
    if (memcmp(source, destination, copy_bytes))
    {
        report_state("copy-mismatch", address, 20);
        return 20;
    }
    if (!VirtualProtect((void *)source, SOURCE_SIZE, PAGE_NOACCESS,
                        &old_protection))
    {
        report_state("comparison-reprotect-failed", address, 23);
        return 23;
    }
    report_state("complete", address, 0);
    return 0;
}

static int run_tail(BYTE *stub, const DWORD *source, DWORD address)
{
    DWORD destination = 0;
    DWORD old_protection;
    MEMORY_BASIC_INFORMATION info;

    report_state("start", address, 0);
    call_copy_stub(stub, source, &destination, 1);
    if (VirtualQuery(source, &info, sizeof(info)) != sizeof(info) ||
        info.Protect != PAGE_NOACCESS)
    {
        report_state("protection-not-restored", address, 31);
        return 31;
    }
    if (!VirtualProtect((void *)source, SOURCE_SIZE, PAGE_READWRITE,
                        &old_protection))
    {
        report_state("comparison-unprotect-failed", address, 32);
        return 32;
    }
    if (destination != source[0])
    {
        report_state("copy-mismatch", address, 30);
        return 30;
    }
    report_state("complete", address, 0);
    return 0;
}

int main(void)
{
    DWORD *source;
    BYTE *initial_stub;
    BYTE *block_stub;
    BYTE *tail_stub;
    DWORD old_protection;
    int i, status;

    source = VirtualAlloc((void *)SOURCE_ADDRESS, SOURCE_SIZE,
                          MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
    if (!source)
    {
        report_allocation_failure("source-allocation-failed", SOURCE_ADDRESS);
        return 10;
    }
    initial_stub = build_copy_stub(INITIAL_COPY_ADDRESS);
    if (!initial_stub)
    {
        report_allocation_failure("initial-allocation-failed",
                                  INITIAL_COPY_ADDRESS);
        return 10;
    }
    block_stub = build_copy_stub(BLOCK_COPY_ADDRESS);
    if (!block_stub)
    {
        report_allocation_failure("block-allocation-failed",
                                  BLOCK_COPY_ADDRESS);
        return 10;
    }
    tail_stub = build_tail_stub(TAIL_COPY_ADDRESS);
    if (!tail_stub)
    {
        report_allocation_failure("tail-allocation-failed", TAIL_COPY_ADDRESS);
        return 10;
    }

    for (i = 0; i < BLOCK_COPY_DWORDS; ++i)
        source[i] = 0x51000000u + i * 0x10101u;
    if (!VirtualProtect(source, SOURCE_SIZE, PAGE_NOACCESS, &old_protection))
    {
        report_state("protect-failed", 0, 11);
        return 11;
    }

    status = run_copy(initial_stub, source,
                      INITIAL_COPY_ADDRESS, INITIAL_COPY_DWORDS);
    if (status) return status;
    status = run_copy(block_stub, source,
                      BLOCK_COPY_ADDRESS, BLOCK_COPY_DWORDS);
    if (status) return status;
    status = run_tail(tail_stub, source, TAIL_COPY_ADDRESS);
    if (status) return status;

    return 0;
}
