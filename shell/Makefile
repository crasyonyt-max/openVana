PREFIX ?= /usr
CFLAGS ?= -Os -pipe
CFLAGS += -Wall -Wextra -Wno-unused-parameter
PKGS = gtk+-3.0 gtk-layer-shell-0 gio-unix-2.0

vana-shell: vana-shell.c
	$(CC) $(CFLAGS) $$(pkg-config --cflags $(PKGS)) -o $@ $< $$(pkg-config --libs $(PKGS)) $(LDFLAGS)

install: vana-shell
	install -Dm755 vana-shell $(DESTDIR)$(PREFIX)/bin/vana-shell
	install -Dm644 ../branding/logo.svg $(DESTDIR)$(PREFIX)/share/openvana/logo.svg

clean:
	rm -f vana-shell
.PHONY: install clean
