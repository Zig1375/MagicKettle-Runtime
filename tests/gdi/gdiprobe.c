/* The owner must see the pixels a child paints, even when the child belongs to another process.
 * Mode 0 is the same-process control; mode 1 creates a foreign child, mode 2 reparents a popup,
 * and mode 3 resizes the owner and moves/resizes the child while its timer keeps painting. */
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

static HWND host, child;
static int mode, samples, failures;
static PROCESS_INFORMATION worker;

static LRESULT CALLBACK paint_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    static unsigned frame;
    static BOOL awaiting_ack;
    if (msg == WM_CREATE) { SetTimer(hwnd, 1, 400, NULL); return 0; }
    if (msg == WM_APP + 2) { awaiting_ack = FALSE; return 0; }
    if (msg == WM_TIMER) {
        if (awaiting_ack) return 0;
        COLORREF color = (++frame % 2) ? RGB(210, 40, 60) : RGB(30, 190, 90);
        RECT rect; GetClientRect(hwnd, &rect);
        HDC dc = GetDC(hwnd);
        HBRUSH brush = CreateSolidBrush(color);
        FillRect(dc, &rect, brush); DeleteObject(brush);
        COLORREF readback = GetPixel(dc, 40, 40);
        GdiFlush(); ReleaseDC(hwnd, dc);
        printf("PAINTER pid=%lu hwnd=%p frame=%u expected=%08lx read=%08lx\n",
               GetCurrentProcessId(), hwnd, frame, color, readback); fflush(stdout);
        awaiting_ack = TRUE;
        PostMessageW(host, WM_APP + 1, (WPARAM)hwnd, color);
        return 0;
    }
    if (msg == WM_DESTROY) { KillTimer(hwnd, 1); if (mode != 0) PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static LRESULT CALLBACK host_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    if (msg == WM_APP + 1) {
        child = (HWND)wp;
        HDC dc = GetDC(child);
        COLORREF pixel = GetPixel(dc, 40, 40);
        ReleaseDC(child, dc);
        DWORD painter; GetWindowThreadProcessId(child, &painter);
        ++samples;
        if (pixel != (COLORREF)lp) ++failures;
        printf("OWNER pid=%lu child_pid=%lu sample=%d expected=%08lx read=%08lx %s\n",
               GetCurrentProcessId(), painter, samples, (COLORREF)lp, pixel,
               pixel == (COLORREF)lp ? "PASS" : "FAIL"); fflush(stdout);
        if (mode == 3 && samples == 5) SetWindowPos(hwnd, NULL, 100, 100, 640, 420, SWP_NOZORDER);
        if (mode == 3 && samples == 7) SetWindowPos(child, NULL, 60, 50, 200, 130, SWP_NOZORDER);
        if (samples < 10) PostMessageW(child, WM_APP + 2, 0, 0);
        if (samples == 10) DestroyWindow(hwnd);
        return 0;
    }
    if (msg == WM_TIMER) { printf("TIMEOUT\n"); failures++; DestroyWindow(hwnd); return 0; }
    if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

int wmain(int argc, wchar_t **argv)
{
    HINSTANCE instance = GetModuleHandleW(NULL);
    WNDCLASSW painter = { .lpfnWndProc = paint_proc, .hInstance = instance, .lpszClassName = L"MK_GDI_Painter" };
    RegisterClassW(&painter);
    if (argc == 4 && !wcscmp(argv[1], L"worker")) {
        host = (HWND)(UINT_PTR)wcstoull(argv[2], NULL, 16); mode = _wtoi(argv[3]);
        child = CreateWindowW(painter.lpszClassName, L"Painter", mode == 2 ? WS_POPUP : WS_CHILD,
                              20, 20, 240, 160, mode == 2 ? NULL : host, NULL, instance, NULL);
        if (!child) return 3;
        if (mode == 2) {
            SetLastError(0); HWND previous = SetParent(child, host);
            if (!previous && GetLastError()) return 4;
            SetWindowLongPtrW(child, GWL_STYLE, (GetWindowLongPtrW(child, GWL_STYLE) & ~WS_POPUP) | WS_CHILD);
            SetWindowPos(child, NULL, 20, 20, 240, 160, SWP_NOZORDER | SWP_FRAMECHANGED);
        }
        ShowWindow(child, SW_SHOW);
    } else {
        mode = argc > 1 ? _wtoi(argv[1]) : 0;
        WNDCLASSW owner = { .lpfnWndProc = host_proc, .hInstance = instance, .lpszClassName = L"MK_GDI_Owner",
                            .hbrBackground = (HBRUSH)(COLOR_WINDOW + 1) };
        RegisterClassW(&owner);
        wchar_t title[100]; swprintf(title, 100, L"Magic Kettle GDI probe — mode %d", mode);
        host = CreateWindowW(owner.lpszClassName, title, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN,
                             100, 100, 420, 300, NULL, NULL, instance, NULL);
        if (!host) return 5;
        ShowWindow(host, SW_SHOW); UpdateWindow(host); SetTimer(host, 2, 12000, NULL);
        if (!mode) {
            child = CreateWindowW(painter.lpszClassName, L"Painter", WS_CHILD | WS_VISIBLE,
                                  20, 20, 240, 160, host, NULL, instance, NULL);
        } else {
            wchar_t exe[MAX_PATH], command[2048]; GetModuleFileNameW(NULL, exe, MAX_PATH);
            if (argc > 2) wcsncpy(exe, argv[2], MAX_PATH - 1);
            swprintf(command, 2048, L"\"%ls\" worker %llx %d", exe, (unsigned long long)(UINT_PTR)host, mode);
            STARTUPINFOW startup = { .cb = sizeof(startup) };
            if (!CreateProcessW(exe, command, NULL, NULL, TRUE, 0, NULL, NULL, &startup, &worker)) return 6;
        }
    }
    MSG message;
    while (GetMessageW(&message, NULL, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
    if (worker.hProcess) {
        if (child) PostMessageW(child, WM_CLOSE, 0, 0);
        if (WaitForSingleObject(worker.hProcess, 3000) == WAIT_TIMEOUT) TerminateProcess(worker.hProcess, 7);
        CloseHandle(worker.hThread); CloseHandle(worker.hProcess);
    }
    if (argc != 4) printf("RESULT mode=%d samples=%d failures=%d\n", mode, samples, failures);
    return failures || (argc != 4 && samples != 10) ? 1 : 0;
}
