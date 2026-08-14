/*
 * Windowed and exclusive-fullscreen swapchain present smoke.
 *
 * Black Ops II dies with an access-violation pair immediately after DXMT
 * reports "Setting display mode". This reproduces that boundary without
 * Steam or CEG: create a window and swapchain, present windowed frames,
 * enter exclusive fullscreen, resize buffers, and present again.
 *
 * Distinct exit codes identify the failing stage:
 *   0  full pass
 *   1  device/swapchain creation failed
 *   2  windowed present failed
 *   3  SetFullscreenState(TRUE) failed
 *   4  ResizeBuffers after the mode switch failed
 *   5  fullscreen present failed
 *   6  render-target rebuild failed
 *   7  window creation failed
 */
#define COBJMACROS
#include <d3d11.h>

static void write_message(const char *message)
{
    DWORD length = 0;
    DWORD written = 0;
    while (message[length] != '\0') ++length;
    WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message, length, &written, NULL);
}

static LRESULT CALLBACK smoke_window_proc(HWND window, UINT message, WPARAM w, LPARAM l)
{
    return DefWindowProcA(window, message, w, l);
}

static int present_frames(IDXGISwapChain *swapchain, ID3D11DeviceContext *context,
                          ID3D11RenderTargetView *target, int frames)
{
    const float color[4] = {0.05f, 0.20f, 0.35f, 1.0f};
    int index;
    MSG msg;

    for (index = 0; index < frames; ++index)
    {
        while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
        ID3D11DeviceContext_ClearRenderTargetView(context, target, color);
        ID3D11DeviceContext_OMSetRenderTargets(context, 1, &target, NULL);
        if (FAILED(IDXGISwapChain_Present(swapchain, 1, 0))) return 0;
    }
    return 1;
}

static ID3D11RenderTargetView *acquire_target(ID3D11Device *device, IDXGISwapChain *swapchain)
{
    ID3D11Texture2D *backbuffer = NULL;
    ID3D11RenderTargetView *target = NULL;

    if (FAILED(IDXGISwapChain_GetBuffer(swapchain, 0, &IID_ID3D11Texture2D,
                                        (void **)&backbuffer)))
        return NULL;
    if (FAILED(ID3D11Device_CreateRenderTargetView(device, (ID3D11Resource *)backbuffer,
                                                   NULL, &target)))
        target = NULL;
    ID3D11Texture2D_Release(backbuffer);
    return target;
}

void mainCRTStartup(void)
{
    WNDCLASSA window_class = {0};
    HWND window;
    DXGI_SWAP_CHAIN_DESC swap_desc = {0};
    ID3D11Device *device = NULL;
    ID3D11DeviceContext *context = NULL;
    IDXGISwapChain *swapchain = NULL;
    ID3D11RenderTargetView *target = NULL;
    D3D_FEATURE_LEVEL selected_level = 0;
    const D3D_FEATURE_LEVEL requested_levels[] = {
        D3D_FEATURE_LEVEL_11_1,
        D3D_FEATURE_LEVEL_11_0,
    };
    HRESULT result;

    window_class.lpfnWndProc = smoke_window_proc;
    window_class.hInstance = GetModuleHandleA(NULL);
    window_class.lpszClassName = "SecundaPresentSmoke";
    RegisterClassA(&window_class);
    window = CreateWindowExA(0, window_class.lpszClassName, "Secunda Present Smoke",
                             WS_OVERLAPPEDWINDOW | WS_VISIBLE, 64, 64, 1280, 720,
                             NULL, NULL, window_class.hInstance, NULL);
    if (!window)
    {
        write_message("window creation failed\r\n");
        ExitProcess(7);
    }

    swap_desc.BufferDesc.Width = 1280;
    swap_desc.BufferDesc.Height = 720;
    swap_desc.BufferDesc.RefreshRate.Numerator = 60;
    swap_desc.BufferDesc.RefreshRate.Denominator = 1;
    swap_desc.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    swap_desc.SampleDesc.Count = 1;
    swap_desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    swap_desc.BufferCount = 2;
    swap_desc.OutputWindow = window;
    swap_desc.Windowed = TRUE;
    swap_desc.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
    swap_desc.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

    result = D3D11CreateDeviceAndSwapChain(
        NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0,
        requested_levels, sizeof(requested_levels) / sizeof(requested_levels[0]),
        D3D11_SDK_VERSION, &swap_desc, &swapchain, &device, &selected_level, &context);
    if (FAILED(result))
    {
        write_message("device/swapchain creation failed\r\n");
        ExitProcess(1);
    }

    target = acquire_target(device, swapchain);
    if (!target || !present_frames(swapchain, context, target, 30))
    {
        write_message("windowed present failed\r\n");
        ExitProcess(2);
    }
    write_message("windowed present ok\r\n");

    ID3D11RenderTargetView_Release(target);
    target = NULL;
    if (FAILED(IDXGISwapChain_SetFullscreenState(swapchain, TRUE, NULL)))
    {
        write_message("SetFullscreenState failed\r\n");
        ExitProcess(3);
    }
    write_message("entered exclusive fullscreen\r\n");

    if (FAILED(IDXGISwapChain_ResizeBuffers(swapchain, 0, 0, 0, DXGI_FORMAT_UNKNOWN,
                                            DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH)))
    {
        write_message("ResizeBuffers failed\r\n");
        ExitProcess(4);
    }

    target = acquire_target(device, swapchain);
    if (!target)
    {
        write_message("render-target rebuild failed\r\n");
        ExitProcess(6);
    }
    if (!present_frames(swapchain, context, target, 60))
    {
        write_message("fullscreen present failed\r\n");
        ExitProcess(5);
    }
    write_message("fullscreen present ok\r\n");

    IDXGISwapChain_SetFullscreenState(swapchain, FALSE, NULL);
    ID3D11RenderTargetView_Release(target);
    IDXGISwapChain_Release(swapchain);
    ID3D11DeviceContext_Release(context);
    ID3D11Device_Release(device);
    DestroyWindow(window);
    write_message("present smoke complete\r\n");
    ExitProcess(0);
}
