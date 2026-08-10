PREFIX  ?= /usr/local
DESTDIR ?=

BINDIR   = $(DESTDIR)$(PREFIX)/bin
SHAREDIR = $(DESTDIR)$(PREFIX)/share/sora

.PHONY: install uninstall test integration lint

install:
	install -D -m 0755 bin/sora            $(BINDIR)/sora
	install -D -m 0644 shell/hook.bash     $(SHAREDIR)/shell/hook.bash
	install -D -m 0644 shell/hook.zsh      $(SHAREDIR)/shell/hook.zsh
	install -D -m 0644 shell/hook.fish     $(SHAREDIR)/shell/hook.fish
	install -D -m 0755 libexec/sora-merge-index $(SHAREDIR)/libexec/sora-merge-index

uninstall:
	rm -f $(BINDIR)/sora
	rm -rf $(SHAREDIR)

test:
	bash tests/run.sh

integration:
	RUN_INTEGRATION=1 bash tests/integration/run.sh

lint:
	shellcheck -x -s bash bin/sora bin/release shell/hook.bash \
		tests/*.sh tests/integration/run.sh
	shellcheck -s sh libexec/sora-merge-index packaging/install.sh
