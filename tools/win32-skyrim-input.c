#include <stdarg.h>
#include <string.h>
#include <windef.h>
#include <winbase.h>
#include <winnt.h>
#include <winuser.h>
#include <ntuser.h>

enum {
    RESULT_OK = 0,
    RESULT_USAGE = 1,
    RESULT_GAME_NOT_FOUND = 2,
    RESULT_GAME_WINDOW_NOT_UNIQUE = 3,
    RESULT_GAME_WINDOW_UNAVAILABLE = 4,
    RESULT_FOCUS_FAILED = 5,
    RESULT_INPUT_FAILED = 6
};

typedef struct {
    HWND window;
    unsigned int count;
} game_window_state;

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

static const WCHAR *path_basename(const WCHAR *path)
{
    const WCHAR *name = path;

    while (*path) {
        if (*path == '\\' || *path == '/') name = path + 1;
        path++;
    }
    return name;
}

static BOOL is_game_process(DWORD process_id)
{
    static const WCHAR expected_name[] = L"SkyrimSE.exe";
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

static BOOL CALLBACK find_game_window(HWND window, LPARAM context)
{
    DWORD process_id = 0;
    game_window_state *state = (game_window_state *)context;

    GetWindowThreadProcessId(window, &process_id);
    if (!process_id || !is_game_process(process_id) || !IsWindowVisible(window)) return TRUE;

    state->count++;
    if (!state->window) state->window = window;
    return TRUE;
}

static BOOL focus_game_window(HWND window)
{
    DWORD target_thread = GetWindowThreadProcessId(window, NULL);
    DWORD current_thread = GetCurrentThreadId();
    BOOL attached = FALSE;

    if (GetForegroundWindow() == window) return TRUE;
    if (target_thread && target_thread != current_thread) {
        attached = AttachThreadInput(current_thread, target_thread, TRUE);
    }
    BringWindowToTop(window);
    SetForegroundWindow(window);
    SetFocus(window);
    if (attached) AttachThreadInput(current_thread, target_thread, FALSE);
    Sleep(100);
    return GetForegroundWindow() == window;
}

static BOOL send_key(HWND window, WORD key, DWORD hold_milliseconds)
{
    INPUT input = {0};
    UINT scan;

    input.type = INPUT_KEYBOARD;
    input.ki.wVk = key;
    scan = MapVirtualKeyW(key, MAPVK_VK_TO_VSC_EX);
    input.ki.wScan = scan & 0xff;
    if (scan & 0xff00) input.ki.dwFlags = KEYEVENTF_EXTENDEDKEY;
    if (NtUserSendHardwareInput(window, 0, &input, 0) != 0) return FALSE;
    if (hold_milliseconds) Sleep(hold_milliseconds);
    input.ki.dwFlags |= KEYEVENTF_KEYUP;
    return NtUserSendHardwareInput(window, 0, &input, 0) == 0;
}

static BOOL send_mouse_move(HWND window, LONG horizontal_delta)
{
    INPUT input = {0};

    input.type = INPUT_MOUSE;
    input.mi.dx = horizontal_delta;
    input.mi.dwFlags = MOUSEEVENTF_MOVE;
    return NtUserSendHardwareInput(window, 0, &input, 0) == 0;
}

static BOOL send_window_message(HWND window, UINT message, WPARAM value, LPARAM coordinates)
{
    DWORD_PTR result = 0;

    return SendMessageTimeoutW(window, message, value, coordinates,
                               SMTO_ABORTIFHUNG | SMTO_BLOCK, 3000, &result) != 0;
}

static BOOL click_continue(HWND window)
{
    RECT client;
    POINT target;
    POINT original;
    INPUT inputs[2] = {{0}};
    BOOL have_original;
    BOOL delivered;
    BOOL sent;
    LPARAM coordinates;

    if (!GetClientRect(window, &client)) return FALSE;
    if (client.right - client.left < 1000 || client.bottom - client.top < 600) return FALSE;

    target.x = client.left + ((client.right - client.left) * 92 / 100);
    target.y = client.top + ((client.bottom - client.top) * 72 / 100);
    coordinates = MAKELPARAM(target.x, target.y);
    delivered = send_window_message(window, WM_MOUSEMOVE, 0, coordinates)
        && send_window_message(window, WM_LBUTTONDOWN, MK_LBUTTON, coordinates)
        && send_window_message(window, WM_LBUTTONUP, 0, coordinates);
    if (!ClientToScreen(window, &target)) return FALSE;

    have_original = GetCursorPos(&original);
    if (!SetCursorPos(target.x, target.y)) return FALSE;
    Sleep(100);

    inputs[0].type = INPUT_MOUSE;
    inputs[0].mi.dx = target.x;
    inputs[0].mi.dy = target.y;
    inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTDOWN;
    inputs[1] = inputs[0];
    inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTUP;
    sent = NtUserSendHardwareInput(window, 0, &inputs[0], 0) == 0
        && NtUserSendHardwareInput(window, 0, &inputs[1], 0) == 0;
    Sleep(100);
    if (have_original) SetCursorPos(original.x, original.y);
    return delivered && sent;
}

int main(int argc, char **argv)
{
    game_window_state state = {0};
    BOOL sent = FALSE;

    if (argc != 2) return RESULT_USAGE;
    EnumWindows(find_game_window, (LPARAM)&state);
    if (!state.count) return RESULT_GAME_NOT_FOUND;
    if (state.count != 1 || !state.window) return RESULT_GAME_WINDOW_NOT_UNIQUE;
    if (!IsWindowEnabled(state.window)) return RESULT_GAME_WINDOW_UNAVAILABLE;
    if (!focus_game_window(state.window)) return RESULT_FOCUS_FAILED;

    if (!strcmp(argv[1], "return")) sent = send_key(state.window, VK_RETURN, 50);
    else if (!strcmp(argv[1], "up")) sent = send_key(state.window, VK_UP, 50);
    else if (!strcmp(argv[1], "escape")) sent = send_key(state.window, VK_ESCAPE, 50);
    else if (!strcmp(argv[1], "f5")) sent = send_key(state.window, VK_F5, 50);
    else if (!strcmp(argv[1], "w")) sent = send_key(state.window, 'W', 450);
    else if (!strcmp(argv[1], "mouse")) sent = send_mouse_move(state.window, 120);
    else if (!strcmp(argv[1], "continue")) sent = click_continue(state.window);
    else if (!strcmp(argv[1], "close")) sent = PostMessageW(state.window, WM_CLOSE, 0, 0);
    else return RESULT_USAGE;

    return sent ? RESULT_OK : RESULT_INPUT_FAILED;
}
