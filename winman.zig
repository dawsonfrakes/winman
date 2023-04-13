const std = @import("std");
const w = std.os.windows;

fn callback(hwnd: w.HWND, _: w.LPARAM) callconv(w.WINAPI) bool {
    if ((w.user32.GetWindowLongA(hwnd, w.user32.GWL_EXSTYLE) & w.user32.WS_EX_TOOLWINDOW) > 0)
        return true;
    if (blk: {
        var ti: TITLEBARINFO = undefined;
        ti.cbSize = @sizeOf(TITLEBARINFO);
        _ = GetTitleBarInfo(hwnd, &ti);
        const STATE_SYSTEM_INVISIBLE = 0x00008000;
        break :blk (ti.rgstate[0] & STATE_SYSTEM_INVISIBLE) > 0;
    })
        return true;
    if (blk: {
        var hwndTry = GetAncestor(hwnd, 3);
        var hwndWalk: ?w.HWND = null;
        while (hwndTry != hwndWalk) {
            hwndWalk = hwndTry;
            hwndTry = GetLastActivePopup(hwndWalk.?);
            if (IsWindowVisible(hwndTry.?))
                break;
        }
        break :blk hwndWalk != hwnd;
    })
        return true;
    if (!IsWindowVisible(hwnd))
        return true;
    if (IsIconic(hwnd))
        return true;
    if (MonitorFromWindow(hwnd, 1) != monitor)
        return true;
    const DWMWA_CLOAKED = 14;
    if (blk: {
        var out: w.INT = w.FALSE;
        const res = DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, &out, @sizeOf(@TypeOf(out)));
        break :blk res >= 0 and out == w.TRUE;
    })
        return true;

    var title: [1024]u8 = undefined;
    var title_slice: []u8 = &title;
    title_slice.len = @intCast(usize, GetWindowTextA(hwnd, &title, title.len));

    var class: [1024]u8 = undefined;
    var class_slice: []u8 = &class;
    class_slice.len = @intCast(usize, GetClassNameA(hwnd, &class, class.len));

    if (std.mem.eql(u8, class_slice, "ApplicationFrameWindow"))
        return true;

    //std.debug.print("{s}\n", .{class_slice});
    // std.debug.print("{s}\n", .{title_slice});
    hwnds.appendAssumeCapacity(hwnd);
    return true;
}

const TITLEBARINFO = extern struct {
    cbSize: w.DWORD,
    rcTitleBar: w.RECT,
    rgstate: [6]w.DWORD,
};
const MONITORINFO = extern struct {
    cbSize: w.DWORD,
    rcMonitor: w.RECT,
    rcWork: w.RECT,
    dwFlags: w.DWORD,
};

extern "user32" fn GetWindowRect(hwnd: w.HWND, lpRect: *w.RECT) callconv(w.WINAPI) bool;
extern "user32" fn SetWindowPos(hwnd: w.HWND, hwndInsertAfter: ?w.HWND, x: c_int, y: c_int, cx: c_int, cy: c_int, uFlags: w.UINT) callconv(w.WINAPI) bool;
extern "user32" fn GetMonitorInfoA(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(w.WINAPI) bool;
extern "user32" fn GetLastActivePopup(hwnd: w.HWND) callconv(w.WINAPI) w.HWND;
extern "user32" fn GetTitleBarInfo(hwnd: w.HWND, pti: *TITLEBARINFO) callconv(w.WINAPI) bool;
extern "user32" fn GetAncestor(hwnd: w.HWND, gaFlags: w.UINT) callconv(w.WINAPI) ?w.HWND;
extern "dwmapi" fn DwmGetWindowAttribute(hwnd: w.HWND, dwAttribute: w.DWORD, pvAttribute: w.PVOID, cbAttribute: w.DWORD) callconv(w.WINAPI) w.HRESULT;
extern "user32" fn MonitorFromWindow(hwnd: w.HWND, dwFlags: w.DWORD) callconv(w.WINAPI) HMONITOR;
extern "user32" fn MonitorFromPoint(pt: w.POINT, dwFlags: w.DWORD) callconv(w.WINAPI) HMONITOR;
extern "user32" fn GetCursorPos(lpPoint: *w.POINT) callconv(w.WINAPI) bool;
extern "user32" fn IsWindowVisible(hwnd: w.HWND) callconv(w.WINAPI) bool;
extern "user32" fn IsIconic(hwnd: w.HWND) callconv(w.WINAPI) bool;
extern "user32" fn GetClassNameA(hwnd: w.HWND, lpClassName: [*]u8, nMaxCount: c_int) callconv(w.WINAPI) c_int;
extern "user32" fn GetWindowTextA(hwnd: w.HWND, lpString: [*]u8, nMaxCount: c_int) callconv(w.WINAPI) c_int;
extern "user32" fn EnumWindows(lpEnumFunc: *const fn (hwnd: w.HWND, lp: w.LPARAM) callconv(w.WINAPI) bool, lp: w.LPARAM) callconv(w.WINAPI) bool;

const HMONITOR = *opaque {};
var monitor: HMONITOR = undefined;
var hwnds = std.BoundedArray(w.HWND, 1024){};

// TODO
// use WM_GETMINMAXINFO to deal with windows that have minimum sizes (Discord REEE)
// (theoretical) Don't let popup windows be moved
pub fn main() void {
    const pt = blk: {
        var out: w.POINT = undefined;
        _ = GetCursorPos(&out);
        break :blk out;
    };
    monitor = MonitorFromPoint(pt, 1);
    _ = EnumWindows(callback, 0);

    var mi: MONITORINFO = undefined;
    mi.cbSize = @sizeOf(MONITORINFO);
    _ = GetMonitorInfoA(monitor, &mi);

    const mon_width = mi.rcWork.right - mi.rcWork.left;
    const mon_height = mi.rcWork.bottom - mi.rcWork.top;

    const master_factor = 0.55;
    const master_width = @floatToInt(i32, @intToFloat(f32, mon_width) * master_factor);
    const slave_width = @floatToInt(i32, @intToFloat(f32, mon_width) * (1.0 - master_factor));

    const num_slaves = @intCast(i32, hwnds.len - 1);
    const slave_height = @divFloor(mon_height, num_slaves);

    for (hwnds.constSlice(), 0..) |hwnd, i| {
        var window_rect: w.RECT = undefined;
        _ = GetWindowRect(hwnd, &window_rect);

        var frame_rect: w.RECT = undefined;
        const DWMWA_EXTENDED_FRAME_BOUNDS = 9;
        _ = DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, &frame_rect, @sizeOf(w.RECT));

        const win_frame_padding_left = frame_rect.left - window_rect.left;
        const win_frame_padding_right = window_rect.right - frame_rect.right;
        const win_frame_padding_top = frame_rect.top - window_rect.top;
        const win_frame_padding_bottom = window_rect.bottom - frame_rect.bottom;

        const win_x = mi.rcWork.left - win_frame_padding_left + (if (i != 0) master_width else 0);
        const win_y = mi.rcWork.top - win_frame_padding_top + (if (i != 0) @intCast(i32, i - 1) * slave_height else 0);
        const win_width = (if (i != 0) slave_width else master_width) + win_frame_padding_left + win_frame_padding_right;
        const win_height = (if (i != 0) slave_height else mon_height) + win_frame_padding_top + win_frame_padding_bottom;

        const SWP_ASYNCWINDOWPOS = 0x4000;
        _ = SetWindowPos(hwnd, null, win_x, win_y, win_width, win_height, SWP_ASYNCWINDOWPOS);
    }
}
