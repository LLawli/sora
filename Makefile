PREFIX  ?= /usr/local
DESTDIR ?=

BINDIR   = $(DESTDIR)$(PREFIX)/bin
SHAREDIR = $(DESTDIR)$(PREFIX)/share/sora

# Completion for the sora CLI itself goes to each shell's standard location,
# not under SHAREDIR: bash finds it lazily, and Homebrew links these three
# directories on its own, so a brew install wires it up with no extra steps.
BASHCOMPDIR = $(DESTDIR)$(PREFIX)/share/bash-completion/completions
ZSHCOMPDIR  = $(DESTDIR)$(PREFIX)/share/zsh/site-functions
FISHCOMPDIR = $(DESTDIR)$(PREFIX)/share/fish/vendor_completions.d

.PHONY: install uninstall test integration lint

install:
	install -D -m 0755 bin/sora            $(BINDIR)/sora
	install -D -m 0644 shell/hook.bash     $(SHAREDIR)/shell/hook.bash
	install -D -m 0644 shell/hook.zsh      $(SHAREDIR)/shell/hook.zsh
	install -D -m 0644 shell/hook.fish     $(SHAREDIR)/shell/hook.fish
	install -D -m 0755 libexec/sora-merge-index $(SHAREDIR)/libexec/sora-merge-index
	install -D -m 0644 shell/completion.bash $(BASHCOMPDIR)/sora
	install -D -m 0644 shell/completion.zsh  $(ZSHCOMPDIR)/_sora
	install -D -m 0644 shell/completion.fish $(FISHCOMPDIR)/sora.fish

uninstall:
	rm -f $(BINDIR)/sora
	rm -rf $(SHAREDIR)
	rm -f $(BASHCOMPDIR)/sora $(ZSHCOMPDIR)/_sora $(FISHCOMPDIR)/sora.fish

test:
	bash tests/run.sh

integration:
	RUN_INTEGRATION=1 bash tests/integration/run.sh

lint:
	shellcheck -x -s bash bin/sora bin/release shell/hook.bash \
		shell/completion.bash tests/*.sh tests/integration/run.sh
	shellcheck -s sh libexec/sora-merge-index packaging/install.sh
