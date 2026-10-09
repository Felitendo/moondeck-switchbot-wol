# moondeck-switchbot-wol: build and install
#
# Everything here is plain shell and a few small Python scripts; "building"
# only means compiling the gettext catalogs and rendering the man page. Both
# targets degrade to a no-op when msgfmt/scdoc are missing, so the tree stays
# usable for development without the build dependencies installed.
#
# This is the install for the PC that gets woken, and for packages. SteamOS
# has no make, so the Deck installs with install.sh instead.

# Overridable so a packager can pass the version it is actually building
# (`make VERSION=$pkgver`). The literal below is the fallback for builds
# straight from a checkout, and is what a release tag has to carry.
VERSION      ?= 1.0.0

PREFIX       ?= /usr
DESTDIR      ?=
BINDIR       ?= $(PREFIX)/bin
LIBEXECDIR   ?= $(PREFIX)/lib/moondeck-switchbot-wol
DATADIR      ?= $(PREFIX)/share
LIBDIR       ?= $(DATADIR)/moondeck-switchbot-wol/lib
LOCALEDIR    ?= $(DATADIR)/locale
MANDIR       ?= $(DATADIR)/man

# Where systemd looks for system units, asked of systemd itself because the
# answer is not the same everywhere. Only guessed when there is no systemd.
ifeq ($(PREFIX),/usr)
SYSTEMDDIR   ?= $(shell pkg-config --variable=systemdsystemunitdir systemd 2>/dev/null || echo /usr/lib/systemd/system)
else
SYSTEMDDIR   ?= $(PREFIX)/lib/systemd/system
endif

LINGUAS      := de
MOFILES      := $(patsubst %,po/%.mo,$(LINGUAS))
MANPAGE      := doc/moondeck-switchbot-wol.1

LIBS         := $(wildcard src/lib/*.sh)
HELPERS      := $(wildcard src/lib/*.py)
UNITS        := $(wildcard res/systemd/*)

MSGFMT       := $(shell command -v msgfmt 2>/dev/null)
SCDOC        := $(shell command -v scdoc 2>/dev/null)

.PHONY: all build install uninstall check test pot clean version

all: build

build: $(MOFILES) $(MANPAGE)

# The one place the version is written down, for everything that has to agree
# with it.
version:
	@echo $(VERSION)

po/%.mo: po/%.po
ifdef MSGFMT
	$(MSGFMT) --check --output-file=$@ $<
else
	@echo "msgfmt not found, skipping $@"
endif

$(MANPAGE): doc/moondeck-switchbot-wol.1.scd
ifdef SCDOC
	$(SCDOC) < $< > $@
else
	@echo "scdoc not found, skipping $@"
endif

# Regenerates the template from the sources: the shell side translates with
# msw_msg, the login agent with Python's _().
pot:
	xgettext --language=Shell --from-code=UTF-8 -k --keyword=msw_msg --keyword=msw_msg_into \
		--package-name=moondeck-switchbot-wol --package-version=$(VERSION) \
		--msgid-bugs-address=https://github.com/Felitendo/moondeck-switchbot-wol/issues \
		--add-comments=TRANSLATORS --no-location --sort-by-file \
		--output=po/shell.pot src/moondeck-switchbot-wol $(LIBS)
	xgettext --language=Python --from-code=UTF-8 --keyword=_ \
		--add-comments=TRANSLATORS --no-location --sort-by-file \
		--output=po/python.pot src/login-agent
	msgcat --use-first --output-file=po/merged.pot po/shell.pot po/python.pot
	{ printf '%s\n' "# Translation template for moondeck-switchbot-wol." \
		"# Copyright (C) 2026 Felitendo" \
		"# This file is distributed under the same license as moondeck-switchbot-wol." "#"; \
	  sed -e '1,5d' -e 's/charset=CHARSET/charset=UTF-8/' po/merged.pot; } > po/moondeck-switchbot-wol.pot
	rm -f po/shell.pot po/python.pot po/merged.pot
	@for l in $(LINGUAS); do msgmerge --quiet --update --backup=none po/$$l.po po/moondeck-switchbot-wol.pot; done

# Syntax-check everything, and run shellcheck when it is available.
check:
	@set -e; for f in src/moondeck-switchbot-wol src/wake install.sh $(LIBS); do \
		bash -n "$$f" && echo "ok  $$f"; \
	done
	@set -e; for f in src/login-agent $(HELPERS); do \
		python3 -c "import ast, sys; ast.parse(open(sys.argv[1]).read())" "$$f" && echo "ok  $$f"; \
	done
	@set -e; if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck src/moondeck-switchbot-wol src/wake install.sh \
			scripts/sandbox.sh tests/run.sh $(LIBS); \
		echo "ok  shellcheck"; \
	else \
		echo "shellcheck not found, skipped"; \
	fi
	@if command -v msgfmt >/dev/null 2>&1; then \
		for l in $(LINGUAS); do msgfmt --check --output-file=/dev/null po/$$l.po && echo "ok  po/$$l.po"; done; \
	fi
	@tests/run.sh

test:
	@tests/run.sh

install: build
	# the command, and what MoonDeck and the socket start
	install -Dm755 src/moondeck-switchbot-wol "$(DESTDIR)$(BINDIR)/moondeck-switchbot-wol"
	install -Dm755 src/wake "$(DESTDIR)$(LIBEXECDIR)/wake"
	install -Dm755 src/login-agent "$(DESTDIR)$(LIBEXECDIR)/login-agent"

	# shell libraries and their Python helpers
	install -d "$(DESTDIR)$(LIBDIR)"
	install -Dm644 -t "$(DESTDIR)$(LIBDIR)" $(LIBS) $(HELPERS)

	# the version and the resolved paths are baked in at install time
	sed -i -e 's|@VERSION@|$(VERSION)|g' \
	       -e 's|@BINDIR@|$(BINDIR)|g' \
	       -e 's|@LIBDIR@|$(LIBDIR)|g' \
	       -e 's|@LIBEXECDIR@|$(LIBEXECDIR)|g' \
	       -e 's|@LOCALEDIR@|$(LOCALEDIR)|g' \
	       "$(DESTDIR)$(BINDIR)/moondeck-switchbot-wol" \
	       "$(DESTDIR)$(LIBEXECDIR)/wake" \
	       "$(DESTDIR)$(LIBEXECDIR)/login-agent" \
	       "$(DESTDIR)$(LIBDIR)"/*.sh

	# system units for the login trigger, switched on by `host enable`
	@for u in $(UNITS); do \
		install -Dm644 "$$u" "$(DESTDIR)$(SYSTEMDDIR)/$${u##*/}"; \
		sed -i -e 's|@LIBEXECDIR@|$(LIBEXECDIR)|g' "$(DESTDIR)$(SYSTEMDDIR)/$${u##*/}"; \
	done

	# translations
	@for l in $(LINGUAS); do \
		if [ -f "po/$$l.mo" ]; then \
			install -Dm644 "po/$$l.mo" \
				"$(DESTDIR)$(LOCALEDIR)/$$l/LC_MESSAGES/moondeck-switchbot-wol.mo"; \
		fi; \
	done

	# documentation
	@if [ -f $(MANPAGE) ]; then \
		install -Dm644 $(MANPAGE) "$(DESTDIR)$(MANDIR)/man1/moondeck-switchbot-wol.1"; \
	fi
	install -Dm644 README.md "$(DESTDIR)$(DATADIR)/doc/moondeck-switchbot-wol/README.md"

uninstall:
	rm -f  "$(DESTDIR)$(BINDIR)/moondeck-switchbot-wol"
	rm -rf "$(DESTDIR)$(LIBEXECDIR)"
	rm -rf "$(DESTDIR)$(DATADIR)/moondeck-switchbot-wol"
	@for u in $(UNITS); do rm -f "$(DESTDIR)$(SYSTEMDDIR)/$${u##*/}"; done
	rm -f  "$(DESTDIR)$(MANDIR)/man1/moondeck-switchbot-wol.1"
	rm -rf "$(DESTDIR)$(DATADIR)/doc/moondeck-switchbot-wol"
	@for l in $(LINGUAS); do \
		rm -f "$(DESTDIR)$(LOCALEDIR)/$$l/LC_MESSAGES/moondeck-switchbot-wol.mo"; \
	done

clean:
	rm -f po/*.mo $(MANPAGE)
