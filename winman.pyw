from ctypes import Structure, WinDLL, byref, c_int, sizeof, windll, wintypes
import win32api, win32con, win32gui

class TITLEBARINFO(Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("rcTitleBar", wintypes.RECT),
                ("rgstate", wintypes.DWORD * 6)]

windows_on_monitor = []
def get_windows_on_monitor(hwnd, monitor):
    global windows_on_monitor
    if not win32gui.IsWindowVisible(hwnd):
        return
    root = windll.user32.GetAncestor(hwnd, win32con.GA_ROOTOWNER)
    walk = None
    while root != walk:
        walk = root
        root = windll.user32.GetLastActivePopup(walk)
        if win32gui.IsWindowVisible(root):
            break
    if root != hwnd:
        return
    tb = TITLEBARINFO()
    tb.cbSize = sizeof(tb)
    windll.user32.GetTitleBarInfo(hwnd, byref(tb))
    if tb.rgstate[0] & win32con.STATE_SYSTEM_INVISIBLE:
        return
    if win32gui.GetWindowLong(hwnd, win32con.GWL_EXSTYLE) & win32con.WS_EX_TOOLWINDOW:
        return
    if not win32gui.GetWindowLong(hwnd, win32con.GWL_STYLE) & win32con.WS_THICKFRAME:
        return
    cloaked = c_int(0)
    WinDLL("dwmapi").DwmGetWindowAttribute(hwnd, 14, byref(cloaked), sizeof(cloaked))
    if cloaked.value != 0:
        return
    (t,l,_b,_r) = win32gui.GetWindowRect(hwnd)
    window_monitor_handle = win32api.MonitorFromPoint((l, t), win32con.MONITOR_DEFAULTTONEAREST)
    if window_monitor_handle == monitor:
        windows_on_monitor += [hwnd]

def tile(hwnds, monitor):
    monrect = win32api.GetMonitorInfo(monitor)["Work"]
    bx = monrect[0]
    by = monrect[1]
    w = monrect[2]
    h = monrect[3]
    wipl = win32gui.GetWindowPlacement(hwnds[0])
    win32gui.SetWindowPlacement(hwnds[0], (0, win32con.SW_SHOWNORMAL, wipl[2], wipl[3], (bx, by, bx+(w//2 if len(hwnds) != 1 else w), by+h)))
    if len(hwnds) == 1: return
    secondaries = hwnds[1:]
    ssize = len(secondaries)
    sh = h // ssize
    for i, hwnd in enumerate(secondaries):
        wipl = win32gui.GetWindowPlacement(hwnd)
        win32gui.SetWindowPlacement(hwnd, (0, win32con.SW_SHOWNORMAL, wipl[2], wipl[3], (bx+w//2, by+sh*i, bx+w, by+sh+sh*i)))

monitor = win32api.MonitorFromPoint(win32api.GetCursorPos(), 0)
win32gui.EnumWindows(get_windows_on_monitor, monitor)
tile(windows_on_monitor, monitor)
