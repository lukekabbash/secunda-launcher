/*
 * Native debug-register relay for translated Wine processes.
 *
 * Copyright 2026 Secunda Launcher contributors
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 */

#include <mach/mach.h>
#include <mach/arm/exception.h>
#include <mach/mig.h>
#include <servers/bootstrap.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "secunda_debug.h"

#define ARM_DEBUG_STATE64_COMPAT 15

struct arm_debug_state64_compat
{
    uint64_t bvr[16];
    uint64_t bcr[16];
    uint64_t wvr[16];
    uint64_t wcr[16];
    uint64_t mdscr_el1;
};

struct debug_thread
{
    struct debug_thread *next;
    mach_port_t port;
    uint64_t identifier;
    uint32_t thread_id;
    int unix_pid;
    int unix_tid;
    uint16_t machine;
    unsigned int replay_pending;
    unsigned int exit_trace_consumed;
    struct secunda_debug_registers registers;
};

union broker_message
{
    struct secunda_debug_command command;
    uint8_t bytes[8192];
};

static struct debug_thread *debug_threads;
static mach_port_t command_port;
static mach_port_t pending_signal_thread;
static int trace_enabled;
static uint64_t exit_import_address;

#define SECUNDA_ARM_WATCHPOINT_COUNT 4

extern boolean_t exc_server(mach_msg_header_t *request, mach_msg_header_t *reply);
extern int __pthread_kill(mach_port_t thread, int signal);

static void trace_registers(const char *operation, const struct debug_thread *entry)
{
    const uint64_t *dr;

    if (!trace_enabled) return;
    dr = entry->registers.dr;
    if (!(dr[0] | dr[1] | dr[2] | dr[3] | dr[6] | dr[7])) return;
    fprintf(stderr,
            "debug-register relay %s: thread=%u machine=%#x "
            "dr0=%#llx dr1=%#llx dr2=%#llx dr3=%#llx dr6=%#llx dr7=%#llx\n",
            operation, entry->thread_id, entry->machine,
            (unsigned long long)dr[0], (unsigned long long)dr[1],
            (unsigned long long)dr[2], (unsigned long long)dr[3],
            (unsigned long long)dr[6], (unsigned long long)dr[7]);
}

static uint64_t thread_identifier(mach_port_t thread)
{
    thread_identifier_info_data_t info;
    mach_msg_type_number_t count = THREAD_IDENTIFIER_INFO_COUNT;

    if (thread_info(thread, THREAD_IDENTIFIER_INFO, (thread_info_t)&info, &count) != KERN_SUCCESS)
        return 0;
    return info.thread_id;
}

static struct debug_thread *find_debug_thread(mach_port_t port)
{
    struct debug_thread *entry;
    uint64_t identifier = thread_identifier(port);

    for (entry = debug_threads; entry; entry = entry->next)
        if (entry->identifier && entry->identifier == identifier) return entry;
    return NULL;
}

static struct debug_thread *create_debug_thread(const struct secunda_debug_command *command)
{
    struct debug_thread *entry;

    if (!(entry = calloc(1, sizeof(*entry)))) return NULL;
    entry->port = command->thread_port.name;
    entry->identifier = thread_identifier(entry->port);
    entry->thread_id = command->thread_id;
    entry->unix_pid = command->unix_pid;
    entry->unix_tid = command->unix_tid;
    entry->machine = command->machine;
    entry->next = debug_threads;
    debug_threads = entry;
    return entry;
}

static unsigned int x86_watch_length(uint64_t dr7, unsigned int index)
{
    static const unsigned int lengths[] = {1, 2, 8, 4};
    return lengths[(dr7 >> (18 + index * 4)) & 3];
}

static uint64_t arm_watch_control_with_access(uint64_t address, unsigned int length,
                                              unsigned int load_store)
{
    uint64_t byte_mask = ((UINT64_C(1) << length) - 1) << (address & 7);

    return UINT64_C(1) | (UINT64_C(3) << 1) |
           ((uint64_t)load_store << 3) | (byte_mask << 5);
}

static uint64_t arm_watch_control(uint64_t address, unsigned int length,
                                  unsigned int access)
{
    return arm_watch_control_with_access(address, length, access == 1 ? 2 : 3);
}

static int private_exit_watchpoint_slot(const struct debug_thread *entry)
{
    uint64_t dr7 = entry->registers.dr[7];
    int slot;

    if (!exit_import_address || entry->exit_trace_consumed) return -1;
    for (slot = SECUNDA_ARM_WATCHPOINT_COUNT - 1; slot >= 0; --slot)
        if (!(dr7 & (UINT64_C(3) << (slot * 2)))) return slot;
    return -1;
}

static kern_return_t write_debug_state(struct debug_thread *entry,
                                       int include_exit_trace)
{
    struct arm_debug_state64_compat state;
    uint64_t dr7 = entry->registers.dr[7];
    int exit_slot = include_exit_trace ? private_exit_watchpoint_slot(entry) : -1;
    unsigned int i;

    memset(&state, 0, sizeof(state));
    for (i = 0; i < 4; i++)
    {
        uint64_t address = entry->registers.dr[i];
        unsigned int access = (dr7 >> (16 + i * 4)) & 3;

        if (!(dr7 & (UINT64_C(3) << (i * 2)))) continue;
        if (!access)
            continue;  /* Rosetta executes translated code at a different address. */
        else if (access != 2)
        {
            state.wvr[i] = address & ~UINT64_C(7);
            state.wcr[i] = arm_watch_control(address, x86_watch_length(dr7, i), access);
        }
    }
    if (exit_slot >= 0)
    {
        state.wvr[exit_slot] = exit_import_address & ~UINT64_C(7);
        /* Import binding writes this slot before the program can call through
         * it. Observe loads only so that initialization cannot consume the
         * single diagnostic event intended for the eventual exit call. */
        state.wcr[exit_slot] =
            arm_watch_control_with_access(exit_import_address, sizeof(uint32_t), 1);
    }
    return thread_set_state(entry->port, ARM_DEBUG_STATE64_COMPAT,
                            (thread_state_t)&state,
                            sizeof(state) / sizeof(uint32_t));
}

static kern_return_t apply_debug_registers(struct debug_thread *entry)
{
    return write_debug_state(entry, !entry->exit_trace_consumed);
}

static kern_return_t suspend_hardware_debug_events(struct debug_thread *entry)
{
    struct arm_debug_state64_compat state;

    memset(&state, 0, sizeof(state));
    return thread_set_state(entry->port, ARM_DEBUG_STATE64_COMPAT,
                            (thread_state_t)&state,
                            sizeof(state) / sizeof(uint32_t));
}

static kern_return_t configure_exception_port(struct debug_thread *entry)
{
    uint64_t dr7 = entry->registers.dr[7];
    mach_port_t port = MACH_PORT_NULL;
    unsigned int i;

    if (private_exit_watchpoint_slot(entry) >= 0) port = command_port;

    /* Guest execute breakpoints are stepped inside ntdll. Keeping this Mach
     * exception port attached for them would bounce every internal step
     * through the broker even though Rosetta reports translated ARM PCs. */
    for (i = 0; port == MACH_PORT_NULL && i < 4; ++i)
    {
        unsigned int access = (dr7 >> (16 + i * 4)) & 3;

        if ((dr7 & (UINT64_C(3) << (i * 2))) && access && access != 2)
        {
            port = command_port;
            break;
        }
    }

    return thread_set_exception_ports(entry->port, EXC_MASK_BREAKPOINT, port,
                                      EXCEPTION_DEFAULT, THREAD_STATE_NONE);
}

static kern_return_t set_debug_registers(const struct secunda_debug_command *command,
                                         struct secunda_debug_registers *registers)
{
    struct debug_thread *entry = find_debug_thread(command->thread_port.name);
    int existing = entry != NULL;
    kern_return_t result;

    if (!entry && !(entry = create_debug_thread(command))) return KERN_RESOURCE_SHORTAGE;
    if (existing) mach_port_deallocate(mach_task_self(), command->thread_port.name);
    entry->thread_id = command->thread_id;
    entry->unix_pid = command->unix_pid;
    entry->unix_tid = command->unix_tid;
    entry->machine = command->machine;
    entry->replay_pending = 0;
    entry->registers = command->registers;
    entry->registers.dr[6] &= ~SECUNDA_DEBUG_DATA_REPLAY;
    trace_registers("set", entry);

    if ((result = configure_exception_port(entry)) != KERN_SUCCESS) return result;
    if ((result = apply_debug_registers(entry)) != KERN_SUCCESS) return result;
    *registers = entry->registers;
    return KERN_SUCCESS;
}

static kern_return_t get_debug_registers(const struct secunda_debug_command *command,
                                         struct secunda_debug_registers *registers)
{
    struct debug_thread *entry = find_debug_thread(command->thread_port.name);

    if (!entry)
    {
        mach_port_deallocate(mach_task_self(), command->thread_port.name);
        memset(registers, 0, sizeof(*registers));
        return KERN_SUCCESS;
    }
    mach_port_deallocate(mach_task_self(), command->thread_port.name);
    *registers = entry->registers;
    trace_registers("get", entry);
    entry->registers.dr[6] &= ~SECUNDA_DEBUG_DATA_REPLAY;
    return KERN_SUCCESS;
}

static void send_command_reply(const struct secunda_debug_command *command,
                               kern_return_t status,
                               const struct secunda_debug_registers *registers)
{
    struct secunda_debug_reply reply;

    memset(&reply, 0, sizeof(reply));
    reply.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
    reply.header.msgh_size = sizeof(reply);
    reply.header.msgh_remote_port = command->header.msgh_remote_port;
    reply.header.msgh_id = SECUNDA_DEBUG_REPLY_ID;
    reply.magic = SECUNDA_DEBUG_MAGIC;
    reply.status = status;
    if (registers) reply.registers = *registers;
    mach_msg(&reply.header, MACH_SEND_MSG, sizeof(reply), 0,
             MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
}

static void handle_command(const struct secunda_debug_command *command)
{
    struct secunda_debug_registers registers;
    kern_return_t result;

    memset(&registers, 0, sizeof(registers));
    if (command->magic != SECUNDA_DEBUG_MAGIC)
        result = KERN_INVALID_ARGUMENT;
    else if (command->header.msgh_id == SECUNDA_DEBUG_SET_ID)
        result = set_debug_registers(command, &registers);
    else if (command->header.msgh_id == SECUNDA_DEBUG_GET_ID)
        result = get_debug_registers(command, &registers);
    else
        result = KERN_NOT_SUPPORTED;
    send_command_reply(command, result, &registers);
}

static int debug_address_matches(uint64_t watched_address,
                                 uint64_t reported_address,
                                 int data_event)
{
    if (!data_event) return watched_address == reported_address;

    /* ARM reports the start of the translated memory access, which can be
     * outside the selected bytes when a wider access overlaps them. The WVR
     * and BAS fields identify the eight-byte hardware watchpoint granule, so
     * any reported address in that granule belongs to the event already
     * filtered by the processor. */
    return (watched_address & ~UINT64_C(7)) ==
           (reported_address & ~UINT64_C(7));
}

static unsigned int debug_event_hit_mask(const struct debug_thread *entry,
                                         uint64_t address,
                                         int data_event)
{
    uint64_t dr7 = entry->registers.dr[7];
    unsigned int i, mask = 0;

    for (i = 0; i < 4; i++)
    {
        unsigned int access = (dr7 >> (16 + i * 4)) & 3;

        if (!(dr7 & (UINT64_C(3) << (i * 2)))) continue;
        if (!!access != !!data_event) continue;
        if (debug_address_matches(entry->registers.dr[i], address, data_event))
            mask |= 1u << i;
    }
    return mask;
}

kern_return_t catch_exception_raise(mach_port_t exception_port,
                                    mach_port_t thread,
                                    mach_port_t task,
                                    exception_type_t exception,
                                    exception_data_t code,
                                    mach_msg_type_number_t code_count)
{
    struct debug_thread *entry = find_debug_thread(thread);
    kern_return_t result;
    unsigned int hit_mask;
    int data_event;
    int signal;
    (void)exception_port;
    (void)task;

    if (!entry || exception != EXC_BREAKPOINT || code_count < 2) return KERN_FAILURE;

    if (entry->replay_pending)
    {
        result = apply_debug_registers(entry);
        if (result == KERN_SUCCESS)
        {
            entry->replay_pending = 0;
            entry->registers.dr[6] |= SECUNDA_DEBUG_DATA_REPLAY;
        }
        if (trace_enabled)
            fprintf(stderr,
                    "debug-register relay replay complete: thread=%u code=%#x address=%#x status=%d\n",
                    entry->thread_id, (unsigned int)code[0],
                    (unsigned int)code[1], result);
        return KERN_FAILURE;
    }

    data_event = code[0] == EXC_ARM_DA_DEBUG;
    if (data_event && exit_import_address && !entry->exit_trace_consumed &&
        debug_address_matches(exit_import_address, (uint32_t)code[1], 1))
    {
        entry->exit_trace_consumed = 1;
        result = write_debug_state(entry, 0);
        if (result != KERN_SUCCESS)
        {
            entry->exit_trace_consumed = 0;
            return result;
        }
        fprintf(stderr,
                "SECUNDA_EXIT_IMPORT event=read thread=%u address=%#x\n",
                entry->thread_id, (unsigned int)code[1]);
        pending_signal_thread = thread;
        if (!__pthread_kill(thread, SIGUSR2)) return KERN_SUCCESS;

        entry->exit_trace_consumed = 0;
        apply_debug_registers(entry);
        return KERN_FAILURE;
    }
    if (!(hit_mask = debug_event_hit_mask(entry, (uint32_t)code[1], data_event)))
        return KERN_FAILURE;
    entry->registers.dr[6] = SECUNDA_DEBUG_DR6_BASE | hit_mask;
    if (data_event)
    {
        result = suspend_hardware_debug_events(entry);
        if (result != KERN_SUCCESS) return result;
        entry->replay_pending = 1;
    }
    if (trace_enabled)
        fprintf(stderr,
                "debug-register relay hit: thread=%u code=%#x address=%#x mask=%#x replay=%u\n",
                entry->thread_id, (unsigned int)code[0],
                (unsigned int)code[1], hit_mask, data_event);
    signal = data_event ? SIGEMT : SIGTRAP;
    pending_signal_thread = thread;
    if (!__pthread_kill(thread, signal)) return KERN_SUCCESS;

    if (entry->replay_pending)
    {
        result = apply_debug_registers(entry);
        if (result == KERN_SUCCESS) entry->replay_pending = 0;
    }
    return KERN_FAILURE;
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

static kern_return_t send_hello(const char *service_name)
{
    struct secunda_debug_hello hello;
    mach_port_t bootstrap_port, server_port;
    kern_return_t result;

    if ((result = task_get_bootstrap_port(mach_task_self(), &bootstrap_port)) != KERN_SUCCESS)
        return result;
    result = bootstrap_look_up(bootstrap_port, service_name, &server_port);
    mach_port_deallocate(mach_task_self(), bootstrap_port);
    if (result != KERN_SUCCESS) return result;

    memset(&hello, 0, sizeof(hello));
    hello.header.msgh_bits = MACH_MSGH_BITS_COMPLEX |
        MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0);
    hello.header.msgh_size = sizeof(hello);
    hello.header.msgh_remote_port = server_port;
    hello.header.msgh_id = SECUNDA_DEBUG_HELLO_ID;
    hello.body.msgh_descriptor_count = 1;
    hello.command_port.name = command_port;
    hello.command_port.disposition = MACH_MSG_TYPE_COPY_SEND;
    hello.command_port.type = MACH_MSG_PORT_DESCRIPTOR;
    hello.magic = SECUNDA_DEBUG_MAGIC;
    result = mach_msg(&hello.header, MACH_SEND_MSG, sizeof(hello), 0,
                      MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    mach_port_deallocate(mach_task_self(), server_port);
    return result;
}

static void run_broker(void)
{
    union broker_message request, reply;
    kern_return_t result;

    for (;;)
    {
        memset(&request, 0, sizeof(request));
        result = mach_msg(&request.command.header, MACH_RCV_MSG, 0, sizeof(request),
                          command_port, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if (result != KERN_SUCCESS) break;
        if (request.command.header.msgh_id == SECUNDA_DEBUG_SET_ID ||
            request.command.header.msgh_id == SECUNDA_DEBUG_GET_ID)
        {
            handle_command(&request.command);
            continue;
        }

        memset(&reply, 0, sizeof(reply));
        if (!exc_server(&request.command.header, &reply.command.header)) continue;
        mach_msg(&reply.command.header, MACH_SEND_MSG, reply.command.header.msgh_size, 0,
                 MACH_PORT_NULL, MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if (pending_signal_thread != MACH_PORT_NULL)
        {
            mach_port_deallocate(mach_task_self(), pending_signal_thread);
            pending_signal_thread = MACH_PORT_NULL;
        }
    }
}

int main(int argc, char **argv)
{
    const char *exit_import_text;
    char *exit_import_end;
    kern_return_t result;

    if (argc != 2) return 64;
    trace_enabled = getenv("SECUNDA_DEBUG_RELAY_TRACE") != NULL;
    if ((exit_import_text = getenv("SECUNDA_TRACE_EXIT_IAT")))
    {
        exit_import_address = strtoull(exit_import_text, &exit_import_end, 0);
        if (!exit_import_address || *exit_import_end || exit_import_address > UINT32_MAX)
        {
            fprintf(stderr, "SECUNDA_EXIT_IMPORT status=invalid-address value=%s\n",
                    exit_import_text);
            exit_import_address = 0;
        }
    }
    result = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &command_port);
    if (result != KERN_SUCCESS) return 1;
    result = mach_port_insert_right(mach_task_self(), command_port, command_port,
                                    MACH_MSG_TYPE_MAKE_SEND);
    if (result != KERN_SUCCESS) return 1;
    if ((result = send_hello(argv[1])) != KERN_SUCCESS)
    {
        fprintf(stderr, "debug-register relay handshake failed: %d\n", result);
        return 1;
    }
    run_broker();
    return 0;
}
