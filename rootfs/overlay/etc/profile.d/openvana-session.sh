# Start the openVana desktop automatically after autologin on tty1.
if [ "$(tty)" = /dev/tty1 ] && [ -z "$WAYLAND_DISPLAY" ] && [ "$(id -u)" != 0 ]; then
    export XDG_RUNTIME_DIR=/tmp/$(id -u)-runtime
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
    export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=openVana:wlroots
    exec dbus-run-session labwc >"$XDG_RUNTIME_DIR/session.log" 2>&1
fi
