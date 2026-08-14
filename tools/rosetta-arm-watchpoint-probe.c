#include <mach/mach.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/sysctl.h>

#define ARM_DEBUG_STATE64_COMPAT 15

typedef struct
{
    uint64_t bvr[16];
    uint64_t bcr[16];
    uint64_t wvr[16];
    uint64_t wcr[16];
    uint64_t mdscr_el1;
} arm_debug_state64_compat_t;

static volatile uint32_t watched_value;
static volatile sig_atomic_t trap_count;
static thread_act_t watched_thread;

static void trap_handler(int signal)
{
    arm_debug_state64_compat_t clear_state;

    (void)signal;
    trap_count++;
    memset(&clear_state, 0, sizeof(clear_state));
    thread_set_state(watched_thread, ARM_DEBUG_STATE64_COMPAT,
                     (thread_state_t)&clear_state,
                     sizeof(clear_state) / sizeof(uint32_t));
}

static int translated_process(void)
{
    int translated = 0;
    size_t size = sizeof(translated);
    if (sysctlbyname("sysctl.proc_translated", &translated, &size, NULL, 0) == -1)
        return 0;
    return translated;
}

static uint64_t watch_control(uintptr_t address, size_t size)
{
    const uintptr_t offset = address & 7;
    const uint64_t byte_mask = ((UINT64_C(1) << size) - 1) << offset;

    /* Enable, user access, load/store, and the exact watched bytes. */
    return UINT64_C(1) | (UINT64_C(3) << 1) | (UINT64_C(3) << 3) | (byte_mask << 5);
}

int main(void)
{
    arm_debug_state64_compat_t state;
    struct sigaction action;
    mach_msg_type_number_t count = sizeof(state) / sizeof(uint32_t);
    uintptr_t address = (uintptr_t)&watched_value;
    kern_return_t set_result, get_result, clear_result;

    memset(&action, 0, sizeof(action));
    action.sa_handler = trap_handler;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTRAP, &action, NULL);
    watched_thread = mach_thread_self();

    memset(&state, 0, sizeof(state));
    state.wvr[0] = address & ~(uintptr_t)7;
    state.wcr[0] = watch_control(address, sizeof(watched_value));

    set_result = thread_set_state(watched_thread, ARM_DEBUG_STATE64_COMPAT,
                                  (thread_state_t)&state, count);
    memset(&state, 0, sizeof(state));
    count = sizeof(state) / sizeof(uint32_t);
    get_result = thread_get_state(watched_thread, ARM_DEBUG_STATE64_COMPAT,
                                  (thread_state_t)&state, &count);

    if (set_result == KERN_SUCCESS && get_result == KERN_SUCCESS)
        watched_value++;

    memset(&state, 0, sizeof(state));
    clear_result = thread_set_state(watched_thread, ARM_DEBUG_STATE64_COMPAT,
                                    (thread_state_t)&state,
                                    sizeof(state) / sizeof(uint32_t));
    mach_port_deallocate(mach_task_self(), watched_thread);

    printf("translated=%d set=%d get=%d clear=%d traps=%d value=%u\n",
           translated_process(), set_result, get_result, clear_result,
           trap_count, watched_value);
    return set_result == KERN_SUCCESS && get_result == KERN_SUCCESS && trap_count > 0 ? 0 : 1;
}
