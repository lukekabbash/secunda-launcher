#include <stdarg.h>
#include <windef.h>
#include <winbase.h>
#include <winnt.h>
#include <winuser.h>

/*
 * Activates one exact launcher control without synthesizing global input.
 * Exit codes describe the boundary while keeping window and account text private.
 */

enum {
    RESULT_OK = 0,
    RESULT_LAUNCHER_NOT_FOUND = 2,
    RESULT_CONTROL_NOT_FOUND = 3,
    RESULT_CONTROL_UNAVAILABLE = 4,
    RESULT_CLICK_TIMED_OUT = 5,
    RESULT_MULTIPLE_CONTROLS = 6,
    RESULT_LAUNCHER_WINDOW_NOT_UNIQUE = 7
};

typedef struct {
    HWND control;
    HWND visible_launcher_window;
    unsigned int control_count;
    unsigned int launcher_window_count;
    unsigned int visible_launcher_window_count;
} click_state;

static WCHAR fold_ascii(WCHAR value)
{
    if (value >= 'A' && value <= 'Z') return value + ('a' - 'A');
    return value;
}

static BOOL equals_ascii_case_insensitive(const WCHAR *actual, const WCHAR *expected)
{
    while (*actual && *expected) {
        if (fold_ascii(*actual) != fold_ascii(*expected)) return FALSE;
        actual++;
        expected++;
    }
    return *actual == 0 && *expected == 0;
}

static BOOL equals_play_label(const WCHAR *actual)
{
    static const WCHAR expected[] = L"play";
    unsigned int expected_index = 0;

    while (*actual) {
        WCHAR value = fold_ascii(*actual++);
        if (value < 'a' || value > 'z') continue;
        if (!expected[expected_index] || value != expected[expected_index]) return FALSE;
        expected_index++;
    }
    return expected[expected_index] == 0;
}

static const WCHAR *path_basename(const WCHAR *path)
{
    const WCHAR *name = path;

    while (*path) {
        if (*path == '\\' || *path == '/') name = path + 1;
        path++;
    }
    return name;
}

static BOOL is_launcher_process(DWORD process_id)
{
    static const WCHAR expected_name[] = L"SkyrimSELauncher.exe";
    WCHAR image_path[1024];
    DWORD image_path_length = sizeof(image_path) / sizeof(image_path[0]);
    HANDLE process;
    BOOL matches = FALSE;

    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
    if (!process) return FALSE;

    if (QueryFullProcessImageNameW(process, 0, image_path, &image_path_length) &&
        image_path_length < sizeof(image_path) / sizeof(image_path[0])) {
        image_path[image_path_length] = 0;
        matches = equals_ascii_case_insensitive(path_basename(image_path), expected_name);
    }

    CloseHandle(process);
    return matches;
}

static BOOL CALLBACK find_play_control(HWND control, LPARAM context)
{
    static const WCHAR expected_class[] = L"Button";
    WCHAR class_name[32];
    WCHAR label[64];
    click_state *state = (click_state *)context;

    if (!GetClassNameW(control, class_name, sizeof(class_name) / sizeof(class_name[0]))) {
        return TRUE;
    }
    if (!GetWindowTextW(control, label, sizeof(label) / sizeof(label[0]))) {
        return TRUE;
    }
    if (!equals_ascii_case_insensitive(class_name, expected_class) ||
        !equals_play_label(label)) {
        return TRUE;
    }

    state->control_count++;
    if (!state->control) state->control = control;
    return TRUE;
}

static BOOL CALLBACK find_launcher_window(HWND window, LPARAM context)
{
    DWORD process_id = 0;
    click_state *state = (click_state *)context;

    GetWindowThreadProcessId(window, &process_id);
    if (!process_id || !is_launcher_process(process_id)) return TRUE;

    state->launcher_window_count++;
    if (IsWindowVisible(window)) {
        state->visible_launcher_window_count++;
        if (!state->visible_launcher_window) state->visible_launcher_window = window;
    }
    EnumChildWindows(window, find_play_control, context);
    return TRUE;
}

static BOOL send_bounded_message(HWND window, UINT message, WPARAM value, LPARAM flags)
{
    DWORD_PTR message_result = 0;

    return SendMessageTimeoutW(window, message, value, flags,
                               SMTO_ABORTIFHUNG | SMTO_BLOCK, 3000,
                               &message_result) != 0;
}

static unsigned int activate_play_control(void)
{
    click_state state = {0};

    EnumWindows(find_launcher_window, (LPARAM)&state);
    if (!state.launcher_window_count) return RESULT_LAUNCHER_NOT_FOUND;
    if (state.control_count > 1) return RESULT_MULTIPLE_CONTROLS;

    if (state.control) {
        if (!IsWindowVisible(state.control) || !IsWindowEnabled(state.control)) {
            return RESULT_CONTROL_UNAVAILABLE;
        }
        if (!send_bounded_message(state.control, BM_CLICK, 0, 0)) {
            return RESULT_CLICK_TIMED_OUT;
        }
        return RESULT_OK;
    }

    /* Some launchers draw their buttons rather than exposing child controls. */
    if (state.visible_launcher_window_count != 1 || !state.visible_launcher_window) {
        return RESULT_LAUNCHER_WINDOW_NOT_UNIQUE;
    }
    if (!IsWindowEnabled(state.visible_launcher_window)) return RESULT_CONTROL_UNAVAILABLE;
    if (!send_bounded_message(state.visible_launcher_window, WM_KEYDOWN, VK_RETURN, 0x001c0001) ||
        !send_bounded_message(state.visible_launcher_window, WM_CHAR, '\r', 0x001c0001) ||
        !send_bounded_message(state.visible_launcher_window, WM_KEYUP, VK_RETURN, 0xc01c0001)) {
        return RESULT_CLICK_TIMED_OUT;
    }

    return RESULT_OK;
}

void mainCRTStartup(void)
{
    ExitProcess(activate_play_control());
}
