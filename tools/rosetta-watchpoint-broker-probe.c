#include <errno.h>
#include <mach/mig.h>
#include <mach/mach.h>
#if defined(__arm64__)
# include <mach/arm/thread_status.h>
#endif
#include <servers/bootstrap.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <sys/ucontext.h>
#include <unistd.h>

#define ARM_DEBUG_STATE64_COMPAT 15
#define X86_THREAD_STATE64_COMPAT 4
#define PORT_KIND_TARGET 1
#define PORT_KIND_BROKER 2

typedef struct
{
    uint64_t bvr[16];
    uint64_t bcr[16];
    uint64_t wvr[16];
    uint64_t wcr[16];
    uint64_t mdscr_el1;
} arm_debug_state64_compat_t;

typedef struct
{
    uint64_t rax, rbx, rcx, rdx, rdi, rsi, rbp, rsp;
    uint64_t r8, r9, r10, r11, r12, r13, r14, r15;
    uint64_t rip, rflags, cs, fs, gs;
} x86_thread_state64_compat_t;

typedef struct
{
    mach_msg_header_t header;
    mach_msg_body_t body;
    mach_msg_port_descriptor_t port;
    uint32_t kind;
} port_message_t;

typedef struct
{
    port_message_t message;
    mach_msg_trailer_t trailer;
} received_port_message_t;

static volatile uint32_t watched_value;
static volatile sig_atomic_t exception_seen;
static volatile sig_atomic_t state_signal_seen;
static mach_port_t exception_thread = MACH_PORT_NULL;

extern kern_return_t bootstrap_register2(mach_port_t bootstrap_port,
                                         name_t service_name,
                                         mach_port_t service_port,
                                         uint64_t flags);
extern boolean_t exc_server(mach_msg_header_t *request, mach_msg_header_t *reply);
extern int __pthread_kill(mach_port_t thread, int signal);

#if defined(__arm64__)
static void trace_thread_state(mach_port_t thread)
{
    arm_thread_state64_t arm_state;
    x86_thread_state64_compat_t x86_state;
    mach_msg_type_number_t arm_count = ARM_THREAD_STATE64_COUNT;
    mach_msg_type_number_t x86_count = sizeof(x86_state) / sizeof(uint32_t);
    kern_return_t arm_result, x86_result;

    memset(&arm_state, 0, sizeof(arm_state));
    arm_result = thread_get_state(thread, ARM_THREAD_STATE64,
                                  (thread_state_t)&arm_state, &arm_count);
    memset(&x86_state, 0, sizeof(x86_state));
    x86_result = thread_get_state(thread, X86_THREAD_STATE64_COMPAT,
                                  (thread_state_t)&x86_state, &x86_count);

    fprintf(stderr,
            "THREAD_STATE arm_status=%d arm_pc=%#llx arm_sp=%#llx "
            "x86_status=%d x86_rip=%#llx x86_rsp=%#llx\n",
            arm_result,
            (unsigned long long)arm_thread_state64_get_pc(arm_state),
            (unsigned long long)arm_thread_state64_get_sp(arm_state),
            x86_result, (unsigned long long)x86_state.rip,
            (unsigned long long)x86_state.rsp);
}
#endif

kern_return_t catch_exception_raise(mach_port_t exception_port,
                                    mach_port_t thread,
                                    mach_port_t task,
                                    exception_type_t exception,
                                    exception_data_t code,
                                    mach_msg_type_number_t code_count)
{
    arm_debug_state64_compat_t state;
#if defined(__arm64__)
    arm_exception_state64_t exception_state;
    mach_msg_type_number_t exception_state_count = ARM_EXCEPTION_STATE64_COUNT;
    kern_return_t exception_state_result;
#endif
    (void)exception_port;
    (void)task;
    if (exception != EXC_BREAKPOINT) return KERN_FAILURE;
    fprintf(stderr, "EXCEPTION type=%d count=%u code0=%d code1=%d\n",
            exception, code_count, code_count ? code[0] : 0,
            code_count > 1 ? code[1] : 0);
#if defined(__arm64__)
    trace_thread_state(thread);
    memset(&exception_state, 0, sizeof(exception_state));
    exception_state_result = thread_get_state(
        thread,
        ARM_EXCEPTION_STATE64,
        (thread_state_t)&exception_state,
        &exception_state_count
    );
    fprintf(stderr, "ARM_EXCEPTION status=%d esr=%#x far=%#llx exception=%#x\n",
            exception_state_result, exception_state.__esr,
            (unsigned long long)exception_state.__far,
            exception_state.__exception);
#endif

    memset(&state, 0, sizeof(state));
    if (thread_set_state(thread, ARM_DEBUG_STATE64_COMPAT,
                         (thread_state_t)&state,
                         sizeof(state) / sizeof(uint32_t)) != KERN_SUCCESS)
        return KERN_FAILURE;
    if (__pthread_kill(thread, SIGUSR2)) return KERN_FAILURE;
    exception_thread = thread;
    exception_seen = 1;
    return KERN_SUCCESS;
}

kern_return_t catch_exception_raise_state(mach_port_t exception_port,
                                          exception_type_t exception,
                                          const exception_data_t code,
                                          mach_msg_type_number_t code_count,
                                          int *flavor,
                                          const thread_state_t old_state,
                                          mach_msg_type_number_t old_state_count,
                                          thread_state_t new_state,
                                          mach_msg_type_number_t *new_state_count)
{
    (void)exception_port;
    (void)exception;
    (void)code;
    (void)code_count;
    (void)flavor;
    (void)old_state;
    (void)old_state_count;
    (void)new_state;
    (void)new_state_count;
    return KERN_NOT_SUPPORTED;
}

kern_return_t catch_exception_raise_state_identity(mach_port_t exception_port,
                                                   mach_port_t thread,
                                                   mach_port_t task,
                                                   exception_type_t exception,
                                                   exception_data_t code,
                                                   mach_msg_type_number_t code_count,
                                                   int *flavor,
                                                   thread_state_t old_state,
                                                   mach_msg_type_number_t old_state_count,
                                                   thread_state_t new_state,
                                                   mach_msg_type_number_t *new_state_count)
{
    (void)exception_port;
    (void)thread;
    (void)task;
    (void)exception;
    (void)code;
    (void)code_count;
    (void)flavor;
    (void)old_state;
    (void)old_state_count;
    (void)new_state;
    (void)new_state_count;
    return KERN_NOT_SUPPORTED;
}

static uint64_t watch_control(uintptr_t address, size_t size)
{
    const uintptr_t offset = address & 7;
    const uint64_t byte_mask = ((UINT64_C(1) << size) - 1) << offset;
    return UINT64_C(1) | (UINT64_C(3) << 1) | (UINT64_C(3) << 3) | (byte_mask << 5);
}

static kern_return_t find_service(const char *service_name, mach_port_t *service_port)
{
    mach_port_t bootstrap_port;
    kern_return_t result;

    result = task_get_bootstrap_port(mach_task_self(), &bootstrap_port);
    if (result != KERN_SUCCESS) return result;
    result = bootstrap_look_up(bootstrap_port, service_name, service_port);
    mach_port_deallocate(mach_task_self(), bootstrap_port);
    return result;
}

static kern_return_t send_port(mach_port_t destination, mach_port_t port,
                               mach_msg_type_name_t disposition, uint32_t kind)
{
    port_message_t message;

    memset(&message, 0, sizeof(message));
    message.header.msgh_bits = MACH_MSGH_BITS_COMPLEX |
        MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    message.header.msgh_size = sizeof(message);
    message.header.msgh_remote_port = destination;
    message.body.msgh_descriptor_count = 1;
    message.port.name = port;
    message.port.disposition = disposition;
    message.port.type = MACH_MSG_PORT_DESCRIPTOR;
    message.kind = kind;
    return mach_msg(&message.header, MACH_SEND_MSG, sizeof(message), 0,
                    MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
}

static kern_return_t receive_port(mach_port_t receive_port,
                                  mach_port_t *port, uint32_t *kind)
{
    received_port_message_t message;
    kern_return_t result;

    memset(&message, 0, sizeof(message));
    result = mach_msg(&message.message.header, MACH_RCV_MSG, 0, sizeof(message),
                      receive_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    if (result != KERN_SUCCESS) return result;
    if (message.message.body.msgh_descriptor_count != 1 ||
        message.message.port.type != MACH_MSG_PORT_DESCRIPTOR)
        return KERN_INVALID_ARGUMENT;
    *port = message.message.port.name;
    *kind = message.message.kind;
    return KERN_SUCCESS;
}

static void trap_handler(int signal, siginfo_t *info, void *context)
{
    char message[80];
    int length;
    (void)signal;
#if defined(__x86_64__)
    length = snprintf(message, sizeof(message), "TRAP code=%d trap=%u\n",
                      info->si_code,
                      ((ucontext_t *)context)->uc_mcontext->__es.__trapno);
#else
    (void)context;
    length = snprintf(message, sizeof(message), "TRAP code=%d\n", info->si_code);
#endif
    write(STDOUT_FILENO, message, (size_t)length);
    _exit(0);
}

static void state_handler(int signal, siginfo_t *info, void *context)
{
    char message[160];
    int length;
    (void)signal;
    (void)info;
#if defined(__x86_64__)
    ucontext_t *ucontext = context;

    length = snprintf(message, sizeof(message),
                      "STATE_SIGNAL rip=%#llx rsp=%#llx\n",
                      (unsigned long long)ucontext->uc_mcontext->__ss.__rip,
                      (unsigned long long)ucontext->uc_mcontext->__ss.__rsp);
#else
    (void)context;
    length = snprintf(message, sizeof(message), "STATE_SIGNAL unsupported\n");
#endif
    write(STDOUT_FILENO, message, (size_t)length);
    state_signal_seen = 1;
}

static int target_main(const char *service_name)
{
    struct sigaction action;
    mach_port_t service_port;
    kern_return_t result;
    char command;

    memset(&action, 0, sizeof(action));
    action.sa_sigaction = trap_handler;
    action.sa_flags = SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTRAP, &action, NULL);
    action.sa_sigaction = state_handler;
    sigaction(SIGUSR2, &action, NULL);

    result = find_service(service_name, &service_port);
    if (result == KERN_SUCCESS)
    {
        result = send_port(service_port, mach_task_self(), MACH_MSG_TYPE_COPY_SEND,
                           PORT_KIND_TARGET);
        mach_port_deallocate(mach_task_self(), service_port);
    }
    printf("TARGET %d %p %d\n", getpid(), (const void *)&watched_value, result);
    fflush(stdout);
    if (result != KERN_SUCCESS) return 4;
    if (read(STDIN_FILENO, &command, 1) != 1) return 3;

    watched_value++;
    printf("RESUMED value=%u signal=%d\n", watched_value, state_signal_seen);
    fflush(stdout);
    return state_signal_seen ? 0 : 2;
}

static kern_return_t set_task_watchpoint(task_t task, mach_port_t exception_port,
                                         uintptr_t address,
                                         unsigned int *success_count)
{
    const char *slot_text = getenv("SECUNDA_PROBE_WATCHPOINT_SLOT");
    thread_act_array_t threads = NULL;
    mach_msg_type_number_t thread_count = 0;
    kern_return_t result;
    unsigned long slot = slot_text ? strtoul(slot_text, NULL, 0) : 0;
    unsigned int i;

    *success_count = 0;
    if (slot >= 16) return KERN_INVALID_ARGUMENT;
    result = task_threads(task, &threads, &thread_count);
    if (result != KERN_SUCCESS) return result;

    for (i = 0; i < thread_count; i++)
    {
        arm_debug_state64_compat_t state;
        exception_mask_t masks[EXC_TYPES_COUNT];
        mach_port_t ports[EXC_TYPES_COUNT];
        exception_behavior_t behaviors[EXC_TYPES_COUNT];
        thread_state_flavor_t flavors[EXC_TYPES_COUNT];
        mach_msg_type_number_t port_count = EXC_TYPES_COUNT;
        kern_return_t ports_result;
        memset(&state, 0, sizeof(state));
        ports_result = thread_get_exception_ports(threads[i], EXC_MASK_BREAKPOINT,
                                                  masks, &port_count, ports,
                                                  behaviors, flavors);
        fprintf(stderr, "PORTS result=%d count=%u behavior=%d flavor=%d\n",
                ports_result, port_count, port_count ? behaviors[0] : 0,
                port_count ? flavors[0] : 0);
        while (port_count) mach_port_deallocate(mach_task_self(), ports[--port_count]);
        state.wvr[slot] = address & ~(uintptr_t)7;
        state.wcr[slot] = watch_control(address, sizeof(watched_value));
        if (thread_set_exception_ports(threads[i], EXC_MASK_BREAKPOINT,
                                       exception_port, EXCEPTION_DEFAULT,
                                       THREAD_STATE_NONE) == KERN_SUCCESS &&
            thread_set_state(threads[i], ARM_DEBUG_STATE64_COMPAT,
                             (thread_state_t)&state,
                             sizeof(state) / sizeof(uint32_t)) == KERN_SUCCESS)
            (*success_count)++;
        mach_port_deallocate(mach_task_self(), threads[i]);
    }
    vm_deallocate(mach_task_self(), (vm_address_t)threads,
                  thread_count * sizeof(*threads));
    return KERN_SUCCESS;
}

static int broker_main(const char *service_name, const char *address_text)
{
    const char *slot_text = getenv("SECUNDA_PROBE_WATCHPOINT_SLOT");
    mach_port_t service_port, receive_right, exception_port, target_task;
    uint32_t kind;
    uintptr_t address = (uintptr_t)strtoull(address_text, NULL, 16);
    unsigned int success_count = 0;
    kern_return_t result, watch_result;

    result = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &receive_right);
    if (result != KERN_SUCCESS) return 20;
    result = mach_port_insert_right(mach_task_self(), receive_right, receive_right,
                                    MACH_MSG_TYPE_MAKE_SEND);
    if (result != KERN_SUCCESS) return 21;
    result = find_service(service_name, &service_port);
    if (result == KERN_SUCCESS)
    {
        result = send_port(service_port, receive_right, MACH_MSG_TYPE_COPY_SEND,
                           PORT_KIND_BROKER);
        mach_port_deallocate(mach_task_self(), service_port);
    }
    if (result != KERN_SUCCESS) return 22;

    result = receive_port(receive_right, &target_task, &kind);
    if (result != KERN_SUCCESS || kind != PORT_KIND_TARGET) return 23;
    result = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
                                &exception_port);
    if (result != KERN_SUCCESS) return 24;
    result = mach_port_insert_right(mach_task_self(), exception_port, exception_port,
                                    MACH_MSG_TYPE_MAKE_SEND);
    if (result != KERN_SUCCESS) return 25;
    watch_result = set_task_watchpoint(target_task, exception_port,
                                       address, &success_count);
    printf("BROKER receive=0 watch=%d threads=%u slot=%s\n", watch_result,
           success_count, slot_text ? slot_text : "0");
    fflush(stdout);
    if (watch_result == KERN_SUCCESS && success_count)
        result = mach_msg_server_once(exc_server, 8192, exception_port, 0);
    if (exception_thread != MACH_PORT_NULL)
        mach_port_deallocate(mach_task_self(), exception_thread);
    mach_port_deallocate(mach_task_self(), exception_port);
    mach_port_deallocate(mach_task_self(), target_task);
    return result == KERN_SUCCESS && exception_seen ? 0 : 26;
}

static pid_t spawn_role(const char *path, const char *role, const char *service_name,
                        const char *extra, int input_fd, int output_fd)
{
    pid_t child = fork();
    if (child != 0) return child;
    if (input_fd != -1) dup2(input_fd, STDIN_FILENO);
    if (output_fd != -1) dup2(output_fd, STDOUT_FILENO);
    if (extra) execl(path, path, role, service_name, extra, NULL);
    else execl(path, path, role, service_name, NULL);
    _exit(127);
}

static int coordinator_main(const char *target_path, const char *broker_path)
{
    int commands[2], target_reports[2], broker_reports[2];
    int target_status, broker_status;
    char service_name[BOOTSTRAP_MAX_NAME_LEN], target_line[128], broker_line[128];
    char address_text[32];
    uintptr_t address;
    FILE *target_file, *broker_file;
    mach_port_t bootstrap_port, coordinator_port;
    mach_port_t target_task = MACH_PORT_NULL, broker_port = MACH_PORT_NULL;
    kern_return_t register_result, receive_result = KERN_SUCCESS;
    pid_t target, broker;
    unsigned int received = 0;

    if (pipe(commands) == -1 || pipe(target_reports) == -1 ||
        pipe(broker_reports) == -1) return 30;
    if (task_get_bootstrap_port(mach_task_self(), &bootstrap_port) != KERN_SUCCESS) return 31;
    if (mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE,
                           &coordinator_port) != KERN_SUCCESS) return 32;
    if (mach_port_insert_right(mach_task_self(), coordinator_port, coordinator_port,
                               MACH_MSG_TYPE_MAKE_SEND) != KERN_SUCCESS) return 33;
    snprintf(service_name, sizeof(service_name), "com.secunda.watchpoint.%d", getpid());
    register_result = bootstrap_register2(bootstrap_port, service_name, coordinator_port, 0);
    mach_port_deallocate(mach_task_self(), bootstrap_port);
    if (register_result != KERN_SUCCESS)
    {
        fprintf(stderr, "bootstrap_register2 failed: %d\n", register_result);
        return 34;
    }

    target = spawn_role(target_path, "--target", service_name, NULL,
                        commands[0], target_reports[1]);
    close(commands[0]);
    close(target_reports[1]);
    target_file = fdopen(target_reports[0], "r");
    if (!target_file || !fgets(target_line, sizeof(target_line), target_file) ||
        sscanf(target_line, "TARGET %*d %lx", &address) != 1) return 35;
    snprintf(address_text, sizeof(address_text), "%lx", address);

    broker = spawn_role(broker_path, "--broker", service_name, address_text,
                        -1, broker_reports[1]);
    close(broker_reports[1]);
    broker_file = fdopen(broker_reports[0], "r");

    while (received < 2 && receive_result == KERN_SUCCESS)
    {
        mach_port_t port;
        uint32_t kind;
        receive_result = receive_port(coordinator_port, &port, &kind);
        if (receive_result != KERN_SUCCESS) break;
        if (kind == PORT_KIND_TARGET) target_task = port;
        else if (kind == PORT_KIND_BROKER) broker_port = port;
        else mach_port_deallocate(mach_task_self(), port);
        received++;
    }
    if (receive_result == KERN_SUCCESS && target_task != MACH_PORT_NULL &&
        broker_port != MACH_PORT_NULL)
        receive_result = send_port(broker_port, target_task, MACH_MSG_TYPE_COPY_SEND,
                                   PORT_KIND_TARGET);
    if (target_task != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), target_task);
    if (broker_port != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), broker_port);
    mach_port_deallocate(mach_task_self(), coordinator_port);

    broker_line[0] = '\0';
    if (broker_file) fgets(broker_line, sizeof(broker_line), broker_file);
    write(commands[1], "G", 1);
    close(commands[1]);
    if (fgets(target_line, sizeof(target_line), target_file) == NULL)
        target_line[0] = '\0';
    fclose(target_file);
    if (broker_file) fclose(broker_file);
    waitpid(target, &target_status, 0);
    waitpid(broker, &broker_status, 0);

    printf("register=%d transfer=%d target_status=%d broker_status=%d %s%s",
           register_result, receive_result,
           WIFEXITED(target_status) ? WEXITSTATUS(target_status) : 128 + WTERMSIG(target_status),
           WIFEXITED(broker_status) ? WEXITSTATUS(broker_status) : 128 + WTERMSIG(broker_status),
           broker_line, target_line);
    return receive_result == KERN_SUCCESS && WIFEXITED(target_status) &&
        WEXITSTATUS(target_status) == 0 && WIFEXITED(broker_status) &&
        WEXITSTATUS(broker_status) == 0 ? 0 : 1;
}

int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--target")) return target_main(argv[2]);
    if (argc == 4 && !strcmp(argv[1], "--broker")) return broker_main(argv[2], argv[3]);
    if (argc == 3) return coordinator_main(argv[1], argv[2]);
    fprintf(stderr, "usage: %s <translated-target> <native-broker>\n", argv[0]);
    return 64;
}
