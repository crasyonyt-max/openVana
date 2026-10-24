# Start the openVana desktop automatically after autologin on tty1.
if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(id -u)" != 0 ]; then
    export XDG_RUNTIME_DIR=/tmp/$(id -u)-runtime
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=openVana:wlroots
    LOG=$XDG_RUNTIME_DIR/session.log

    start=$(date +%s)
    dbus-run-session labwc >"$LOG" 2>&1
    # Crashed within a few seconds: retry with software rendering, which works
    # on GPUs without a working 3D driver (e.g. NVIDIA, missing firmware).
    if [ $(( $(date +%s) - start )) -lt 15 ]; then
        cp "$LOG" "$LOG.gpu"
        start=$(date +%s)
        WLR_RENDERER=pixman WLR_NO_HARDWARE_CURSORS=1 dbus-run-session labwc >"$LOG" 2>&1
    fi
    if [ $(( $(date +%s) - start )) -lt 15 ]; then
        clear
        echo "openVana: the desktop could not start on this hardware."
        echo "Please report the lines below (also saved in $LOG):"
        echo
        tail -n 25 "$LOG"
        echo
        echo "Press Enter for a text shell."
        read -r _
    else
        exit 0   # normal logout: let tty1 log in again
    fi
fi
