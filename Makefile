ifeq ($(shell command -v podman 2> /dev/null),)
	CMD=docker
else
	CMD=podman
endif

.PHONY: all
all:
	@$(MAKE) -C doc all

.PHONY: clean
clean:
	@$(MAKE) -C doc clean

.PHONY: stylua
stylua:
	@$(CMD) run \
		--rm -ti \
		-v `pwd`:/src -w/src \
		johnnymorganz/stylua:2.0.2 \
		/stylua \
		--output-format=summary \
		lua

.PHONY: stylua-check
stylua-check:
	@$(CMD) run \
		--rm -ti \
		-v `pwd`:/src -w/src \
		johnnymorganz/stylua:2.0.2 \
		/stylua --check \
		--output-format=summary \
		lua
