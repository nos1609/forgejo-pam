SHELL := /bin/bash
.ONESHELL:
.SHELLFLAGS := -euo pipefail -c

spec ?= forgejo.spec
outdir ?= $(CURDIR)

.PHONY: srpm
srpm:
	dnf -y install go-rpm-macros rpm-build rpmdevtools rpmautospec systemd-rpm-macros
	mkdir -p "$(outdir)"
	workdir="$$(mktemp -d)"
	trap 'rm -rf "$$workdir"' EXIT
	spectool --get-files --source 0 --directory "$(CURDIR)" "$(spec)"
	spectool --get-files --source 1 --directory "$(CURDIR)" "$(spec)"
	sed -E 's/^SHA512 \(([^)]+)\) = ([[:xdigit:]]+)$$/\2  \1/' sources \
		> "$$workdir/SHA512SUMS"
	sha512sum --check --strict "$$workdir/SHA512SUMS"
	rpmautospec process-distgit "$(spec)" "$$workdir/forgejo.spec"
	rpmbuild -bs \
		--define "_sourcedir $(CURDIR)" \
		--define "_srcrpmdir $$(realpath "$(outdir)")" \
		"$$workdir/forgejo.spec"
