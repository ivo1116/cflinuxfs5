ARCH := x86_64
NAME := cflinuxfs5
BASE := ubuntu:noble
BUILD := $(NAME).$(ARCH)

# FIPS configuration (set via environment: FIPS=true FIPS_METHOD=source|ubuntu-pro)
FIPS ?= false
FIPS_METHOD ?= source

# Ubuntu Pro token file for FIPS builds (only used with FIPS_METHOD=ubuntu-pro)
# Create a file containing your token: echo "your-token" > .ubuntu-pro-token
UBUNTU_PRO_TOKEN_FILE ?= .ubuntu-pro-token

# Select Dockerfile based on FIPS mode
ifeq ($(FIPS),true)
DOCKERFILE := Dockerfile.fips
else
DOCKERFILE := Dockerfile
endif

# Enable BuildKit for secret support
export DOCKER_BUILDKIT := 1

# Build secret argument for Ubuntu Pro token (only if file exists and using ubuntu-pro method)
DOCKER_SECRET_ARG :=
ifeq ($(FIPS_METHOD),ubuntu-pro)
ifneq (,$(wildcard $(UBUNTU_PRO_TOKEN_FILE)))
DOCKER_SECRET_ARG := --secret id=ubuntu_pro_token,src=$(UBUNTU_PRO_TOKEN_FILE)
endif
endif

all: $(BUILD).tar.gz

$(BUILD).iid:
	docker build \
	--platform linux/amd64 \
	-f "$(DOCKERFILE)" \
	--build-arg "base=$(BASE)" \
	--build-arg packages="`cat "packages/$(NAME)" 2>/dev/null`" \
	--build-arg fips_packages="`cat "packages/$(NAME).fips" 2>/dev/null`" \
	--build-arg locales="`cat locales`" \
	--build-arg "fips=$(FIPS)" \
	--build-arg "fips_method=$(FIPS_METHOD)" \
	$(DOCKER_SECRET_ARG) \
	--no-cache "--iidfile=$(BUILD).iid" .

$(BUILD).tar.gz: $(BUILD).iid
	docker run "--cidfile=$(BUILD).cid" `cat "$(BUILD).iid"` dpkg -l | tee "packages-list"
	docker export `cat "$(BUILD).cid"` | gzip > "$(BUILD).tar.gz"
	echo "Rootfs SHASUM: `shasum -a 256 "$(BUILD).tar.gz" | cut -d' ' -f1`" > "receipt.$(BUILD)"
	echo "" >> "receipt.$(BUILD)"
	cat "packages-list" >> "receipt.$(BUILD)"
	docker rm -f `cat "$(BUILD).cid"`
	rm -f "$(BUILD).cid" "packages-list"

.PHONY: clean
clean:
	rm -f $(BUILD).iid $(BUILD).cid $(BUILD).tar.gz packages-list

.PHONY: help
help:
	@echo "cflinuxfs5 Build System"
	@echo ""
	@echo "Usage:"
	@echo "  make                    - Build standard rootfs"
	@echo "  make FIPS=true          - Build with FIPS support (source method)"
	@echo "  make FIPS=true FIPS_METHOD=ubuntu-pro - Build with Ubuntu Pro FIPS"
	@echo ""
	@echo "FIPS Methods:"
	@echo "  source     - Build OpenSSL with FIPS module (NOT NIST-validated)"
	@echo "  ubuntu-pro - Use Ubuntu Pro FIPS packages (NIST-validated)"
	@echo ""
	@echo "For ubuntu-pro method, create token file:"
	@echo "  echo 'your-ubuntu-pro-token' > .ubuntu-pro-token"
	@echo ""
	@echo "Variables:"
	@echo "  FIPS                    - Enable FIPS build (true/false, default: false)"
	@echo "  FIPS_METHOD             - FIPS method (source/ubuntu-pro, default: source)"
	@echo "  UBUNTU_PRO_TOKEN_FILE   - Token file path (default: .ubuntu-pro-token)"
	@echo "  BASE                    - Base image (default: ubuntu:noble)"
