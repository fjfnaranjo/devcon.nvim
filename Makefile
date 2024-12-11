ifeq ($(shell command -v podman 2> /dev/null),)
	CMD=docker
else
	CMD=podman
endif

.PHONY: all
all: image
	@$(MAKE) -C doc all

image:
	@$(CMD) build -t devcon:devcon -f Dockerfile.devcon .
	@touch image

.PHONY: clean
clean:
	@$(MAKE) -C doc clean
	$(CMD) image rm devcon:devcon
	rm -f image
