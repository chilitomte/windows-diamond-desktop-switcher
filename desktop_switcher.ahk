#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.

; Globals
DesktopCount = 2        ; Windows starts with 2 desktops at boot
CurrentDesktop = 1      ; Desktop count is 1-indexed (Microsoft numbers them this way)

; DLL
hVirtualDesktopAccessor := DllCall("LoadLibrary", "Str", A_ScriptDir . "\virtual-desktop-accessor.dll", "Ptr")
global IsWindowOnDesktopNumberProc := DllCall("GetProcAddress", Ptr, hVirtualDesktopAccessor, AStr, "IsWindowOnDesktopNumber", "Ptr")

;
; This function examines the registry to build an accurate list of the current virtual desktops and which one we're currently on.
; Current desktop UUID appears to be in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\1\VirtualDesktops
; List of desktops appears to be in HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops
;
mapDesktopsFromRegistry() 
{
    global CurrentDesktop, DesktopCount

    ; Get the current desktop UUID. Length should be 32 always, but there's no guarantee this couldn't change in a later Windows release so we check.
    IdLength := 32
    SessionId := getSessionId()
    if (SessionId) {
        RegRead, CurrentDesktopId, HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\%SessionId%\VirtualDesktops, CurrentVirtualDesktop
        if (CurrentDesktopId) {
            IdLength := StrLen(CurrentDesktopId)
        }
    }

    ; Get a list of the UUIDs for all virtual desktops on the system
    RegRead, DesktopList, HKEY_CURRENT_USER, SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops, VirtualDesktopIDs
    if (DesktopList) {
        DesktopListLength := StrLen(DesktopList)
        ; Figure out how many virtual desktops there are
        DesktopCount := DesktopListLength / IdLength
    }
    else {
        DesktopCount := 1
    }

    ; Parse the REG_DATA string that stores the array of UUID's for virtual desktops in the registry.
    i := 0
    while (CurrentDesktopId and i < DesktopCount) {
        StartPos := (i * IdLength) + 1
        DesktopIter := SubStr(DesktopList, StartPos, IdLength)
        OutputDebug, The iterator is pointing at %DesktopIter% and count is %i%.

        ; Break out if we find a match in the list. If we didn't find anything, keep the
        ; old guess and pray we're still correct :-D.
        if (DesktopIter = CurrentDesktopId) {
            CurrentDesktop := i + 1
            OutputDebug, Current desktop number is %CurrentDesktop% with an ID of %DesktopIter%.
            break
        }
        i++
    }
}

;
; This functions finds out ID of current session.
;
getSessionId()
{
    ProcessId := DllCall("GetCurrentProcessId", "UInt")
    if ErrorLevel {
        OutputDebug, Error getting current process id: %ErrorLevel%
        return
    }
    OutputDebug, Current Process Id: %ProcessId%

    DllCall("ProcessIdToSessionId", "UInt", ProcessId, "UInt*", SessionId)
    if ErrorLevel {
        OutputDebug, Error getting session id: %ErrorLevel%
        return
    }
    OutputDebug, Current Session Id: %SessionId%
    return SessionId
}

;
; This function switches to the desktop number provided.
;
switchDesktopByNumber(targetDesktop)
{
    global CurrentDesktop, DesktopCount

    ; Re-generate the list of desktops and where we fit in that. We do this because
    ; the user may have switched desktops via some other means than the script.
    mapDesktopsFromRegistry()

    ; Don't attempt to switch to an invalid desktop
    if (targetDesktop > DesktopCount || targetDesktop < 1) {
        OutputDebug, [invalid] target: %targetDesktop% current: %CurrentDesktop%
        return
    }

    WinActivate, ahk_class Shell_TrayWnd ; Fixes the issue of active windows in intermediate desktops capturing the switch shortcut and therefore delaying or stopping the switchng sequence. More info: https://github.com/pmb6tz/windows-desktop-switcher/pull/19

    ; Go right until we reach the desktop we want
    while(CurrentDesktop < targetDesktop) {
        Send ^#{Right}
        CurrentDesktop++
        OutputDebug, [right] target: %targetDesktop% current: %CurrentDesktop%
    }

    ; Go left until we reach the desktop we want
    while(CurrentDesktop > targetDesktop) {
        Send ^#{Left}
        CurrentDesktop--
        OutputDebug, [left] target: %targetDesktop% current: %CurrentDesktop%
    }

    Sleep, 50
    focusTheForemostWindow(targetDesktop)
}

focusTheForemostWindow(targetDesktop) 
{
    foremostWindowId := getForemostWindowIdOnDesktop(targetDesktop)
    WinActivate, ahk_id %foremostWindowId%
}

getForemostWindowIdOnDesktop(n) 
{
    n := n - 1 ; Desktops start at 0, while in script it's 1

    ; winIDList contains a list of windows IDs ordered from the top to the bottom for each desktop.
    WinGet winIDList, list
    Loop % winIDList {
        windowID := % winIDList%A_Index%
        windowIsOnDesktop := DllCall(IsWindowOnDesktopNumberProc, UInt, windowID, UInt, n)
        ; Select the first (and foremost) window which is in the specified desktop.
        if (windowIsOnDesktop == 1) {
            return windowID
        }
    }
}

;
; This function creates a new virtual desktop and switches to it
;
createVirtualDesktop()
{
    global CurrentDesktop, DesktopCount
    Send, #^d
    DesktopCount++
    CurrentDesktop = %DesktopCount%
    OutputDebug, [create] desktops: %DesktopCount% current: %CurrentDesktop%
}

;
; This function deletes the current virtual desktop
;
deleteVirtualDesktop()
{
    global CurrentDesktop, DesktopCount
    Send, #^{F4}
    DesktopCount--
    CurrentDesktop--
    OutputDebug, [delete] desktops: %DesktopCount% current: %CurrentDesktop%
}

; Main
SetKeyDelay, 75
mapDesktopsFromRegistry()
OutputDebug, [loading] desktops: %DesktopCount% current: %CurrentDesktop%

; User config!
; This section binds the key combo to the switch/create/delete actions
CapsLock & 1::switchDesktopByNumber(1)
CapsLock & 2::switchDesktopByNumber(2)
CapsLock & 3::switchDesktopByNumber(3)
CapsLock & 4::switchDesktopByNumber(4)
CapsLock & 5::switchDesktopByNumber(5)
CapsLock & 6::switchDesktopByNumber(6)
CapsLock & 7::switchDesktopByNumber(7)
CapsLock & 8::switchDesktopByNumber(8)
CapsLock & 9::switchDesktopByNumber(9)
CapsLock & n::switchDesktopByNumber(CurrentDesktop + 1)
CapsLock & p::switchDesktopByNumber(CurrentDesktop - 1)
CapsLock & s::switchDesktopByNumber(CurrentDesktop + 1)
CapsLock & a::switchDesktopByNumber(CurrentDesktop - 1)
CapsLock & c::createVirtualDesktop()
CapsLock & d::deleteVirtualDesktop()

; Alternate keys for this config. Adding these because DragonFly (python) doesn't send CapsLock correctly.
^!1::switchDesktopByNumber(1)
^!2::switchDesktopByNumber(2)
^!3::switchDesktopByNumber(3)
^!4::switchDesktopByNumber(4)
^!5::switchDesktopByNumber(5)
^!6::switchDesktopByNumber(6)
^!7::switchDesktopByNumber(7)
^!8::switchDesktopByNumber(8)
^!9::switchDesktopByNumber(9)
^!n::switchDesktopByNumber(CurrentDesktop + 1)
^!p::switchDesktopByNumber(CurrentDesktop - 1)
^!s::switchDesktopByNumber(CurrentDesktop + 1)
^!a::switchDesktopByNumber(CurrentDesktop - 1)
^!c::createVirtualDesktop()
^!d::deleteVirtualDesktop()
