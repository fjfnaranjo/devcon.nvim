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
