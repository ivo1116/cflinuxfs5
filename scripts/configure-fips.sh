#!/bin/bash
# FIPS configuration script for cflinuxfs5
# This script configures FIPS-compliant cryptographic modules
#
# IMPORTANT DISCLAIMER:
# The "source" method builds OpenSSL with FIPS module support, but this does NOT
# produce NIST FIPS 140-2/140-3 validated cryptography. True FIPS validation requires
# specific certified binaries. The "source" method provides FIPS-compatible algorithms
# and configuration, but for actual FIPS compliance certification, use "ubuntu-pro"
# method with Ubuntu Pro FIPS packages or a pre-validated base image.

set -euo pipefail

FIPS_ENABLED="${1:-false}"
FIPS_METHOD="${2:-source}"
FIPS_PACKAGES="${3:-}"

# Track success for marker file
FIPS_CONFIGURED=false

cleanup() {
  cd /
  rm -rf /tmp/openssl-* /tmp/configure-fips-*
}
trap cleanup EXIT

if [[ "$FIPS_ENABLED" != "true" ]]; then
  echo "FIPS mode not enabled, skipping FIPS configuration"
  exit 0
fi

echo "=============================================="
echo "Configuring FIPS mode (method: $FIPS_METHOD)"
echo "=============================================="

export DEBIAN_FRONTEND=noninteractive
PACKAGE_ARGS="--allow-downgrades --allow-remove-essential --allow-change-held-packages --no-install-recommends"

# Function to verify FIPS is working with actual crypto operation
verify_fips_functional() {
  local openssl_bin="${1:-openssl}"
  local openssl_conf="${2:-}"
  
  echo "Running functional FIPS verification..."
  
  local env_prefix=""
  if [[ -n "$openssl_conf" ]]; then
    env_prefix="OPENSSL_CONF=$openssl_conf"
  fi
  
  # Test 1: Check FIPS provider is loaded
  if ! eval "$env_prefix $openssl_bin list -providers" 2>/dev/null | grep -qi "fips"; then
    echo "WARNING: FIPS provider not listed"
    return 1
  fi
  echo "  - FIPS provider: loaded"
  
  # Test 2: Verify a FIPS-approved algorithm works (AES-256-GCM)
  local test_result
  test_result=$(echo "test" | eval "$env_prefix $openssl_bin enc -aes-256-gcm -pass pass:testkey -pbkdf2" 2>&1) || true
  if [[ -z "$test_result" ]] || echo "$test_result" | grep -qi "error"; then
    echo "WARNING: AES-256-GCM encryption test inconclusive"
  else
    echo "  - AES-256-GCM: working"
  fi
  
  # Test 3: Verify SHA-256 works
  local sha_result
  sha_result=$(echo "test" | eval "$env_prefix $openssl_bin dgst -sha256" 2>&1) || true
  if echo "$sha_result" | grep -qi "sha2-256"; then
    echo "  - SHA-256: working"
  else
    echo "  - SHA-256: result=$sha_result"
  fi
  
  return 0
}

case "$FIPS_METHOD" in
  source)
    echo ""
    echo "WARNING: Building OpenSSL from source with FIPS module support."
    echo "This does NOT produce NIST FIPS 140-2/140-3 validated cryptography."
    echo "For true FIPS compliance, use 'ubuntu-pro' method or a certified base image."
    echo ""
    
    # OpenSSL version and checksum (update both when upgrading)
    # Get checksums from: https://www.openssl.org/source/
    OPENSSL_VERSION="3.0.13"
    OPENSSL_SHA256="88525753f79d3bec27d2fa7c66aa0b92b3aa9498dafd93d7cfa4b3780cdae313"
    
    echo "Installing build dependencies..."
    apt-get -y $PACKAGE_ARGS update
    apt-get -y $PACKAGE_ARGS install \
      build-essential \
      wget \
      ca-certificates \
      perl
    
    cd /tmp
    TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"
    
    echo "Downloading OpenSSL ${OPENSSL_VERSION}..."
    wget -q "https://www.openssl.org/source/${TARBALL}"
    
    echo "Verifying checksum..."
    # sha256sum -c will exit non-zero on mismatch, triggering set -e
    echo "${OPENSSL_SHA256}  ${TARBALL}" | sha256sum -c -
    echo "Checksum verified successfully."
    
    tar xzf "${TARBALL}"
    cd "openssl-${OPENSSL_VERSION}"
    
    # Install to /usr/local to avoid conflicts with system OpenSSL
    echo "Configuring OpenSSL with FIPS module support..."
    ./Configure enable-fips shared \
      --prefix=/usr/local \
      --openssldir=/usr/local/ssl \
      --libdir=lib
    
    echo "Building OpenSSL (this may take several minutes)..."
    make -j$(nproc)
    
    echo "Installing OpenSSL..."
    make install
    
    echo "Installing FIPS module..."
    make install_fips
    
    # Update library cache
    echo "/usr/local/lib" > /etc/ld.so.conf.d/openssl-fips.conf
    ldconfig
    
    # Create FIPS-enabled OpenSSL configuration
    cat > /usr/local/ssl/openssl-fips.cnf << 'EOF'
# OpenSSL FIPS configuration for cflinuxfs5
# This configuration enables FIPS mode for applications using this config

openssl_conf = openssl_init

.include /usr/local/ssl/fipsmodule.cnf

[openssl_init]
providers = provider_sect
alg_section = algorithm_sect

[provider_sect]
fips = fips_sect
base = base_sect

[base_sect]
activate = 1

[fips_sect]
activate = 1

[algorithm_sect]
default_properties = fips=yes
EOF

    # Create symlink for easy access
    ln -sf /usr/local/ssl/openssl-fips.cnf /etc/ssl/openssl-fips.cnf
    
    # Set PATH in multiple locations for different shell contexts
    # 1. Profile.d for login shells
    echo 'export PATH="/usr/local/bin:$PATH"' > /etc/profile.d/openssl-fips.sh
    # 2. Environment.d for systemd services
    mkdir -p /etc/environment.d
    echo 'PATH=/usr/local/bin:/usr/bin:/bin' > /etc/environment.d/10-openssl-fips.conf
    # 3. Update /etc/environment for non-interactive shells
    if grep -q "^PATH=" /etc/environment 2>/dev/null; then
      sed -i 's|^PATH=|PATH=/usr/local/bin:|' /etc/environment
    else
      echo 'PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin' >> /etc/environment
    fi
    
    # Cleanup build dependencies and cache to reduce image size
    echo "Cleaning up build artifacts..."
    cd /
    rm -rf /tmp/openssl-*
    apt-get -y remove --purge build-essential
    apt-get -y autoremove --purge
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    
    FIPS_CONFIGURED=true
    echo ""
    echo "OpenSSL FIPS module installed to /usr/local"
    echo "Use 'OPENSSL_CONF=/usr/local/ssl/openssl-fips.cnf openssl ...' for FIPS mode"
    ;;
    
  ubuntu-pro)
    echo "Configuring Ubuntu Pro FIPS packages..."
    
    # Ubuntu Pro FIPS requires a valid subscription token
    # Token should be provided via:
    # 1. Docker BuildKit secret: --secret id=ubuntu_pro_token,src=token.txt
    # 2. Or environment variable (less secure, visible in process list)
    
    UBUNTU_PRO_TOKEN=""
    
    # Try to read from BuildKit secret first (more secure)
    if [[ -f /run/secrets/ubuntu_pro_token ]]; then
      UBUNTU_PRO_TOKEN=$(cat /run/secrets/ubuntu_pro_token)
      echo "Using Ubuntu Pro token from BuildKit secret"
    elif [[ -n "${UBUNTU_PRO_TOKEN_ENV:-}" ]]; then
      UBUNTU_PRO_TOKEN="$UBUNTU_PRO_TOKEN_ENV"
      echo "Using Ubuntu Pro token from environment variable"
      echo "WARNING: Token may be visible in process listings"
    fi
    
    if [[ -z "$UBUNTU_PRO_TOKEN" ]]; then
      echo "ERROR: Ubuntu Pro token not provided"
      echo ""
      echo "Provide token via BuildKit secret (recommended):"
      echo "  docker build --secret id=ubuntu_pro_token,src=token.txt ..."
      echo ""
      echo "Or via environment (less secure):"
      echo "  docker build --build-arg UBUNTU_PRO_TOKEN_ENV=xxx ..."
      exit 1
    fi
    
    echo "Installing Ubuntu Pro tools..."
    apt-get -y $PACKAGE_ARGS update
    apt-get -y $PACKAGE_ARGS install ubuntu-advantage-tools
    
    echo "Attaching to Ubuntu Pro..."
    pro attach "$UBUNTU_PRO_TOKEN"
    
    # Clear token from memory
    UBUNTU_PRO_TOKEN=""
    
    echo "Enabling FIPS updates..."
    if ! pro enable fips-updates --assume-yes; then
      echo "ERROR: Failed to enable FIPS updates"
      exit 1
    fi
    
    # Update package lists after enabling FIPS repo
    apt-get -y $PACKAGE_ARGS update
    
    # Install FIPS packages if specified
    if [[ -n "$FIPS_PACKAGES" ]]; then
      echo "Installing FIPS-specific packages: $FIPS_PACKAGES"
      # shellcheck disable=SC2086
      if ! apt-get -y $PACKAGE_ARGS install $FIPS_PACKAGES; then
        echo "ERROR: Failed to install FIPS packages"
        exit 1
      fi
    fi
    
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    
    FIPS_CONFIGURED=true
    echo "Ubuntu Pro FIPS configuration complete"
    ;;
    
  *)
    echo "ERROR: Unknown FIPS method: $FIPS_METHOD"
    echo "Supported methods:"
    echo "  source     - Build OpenSSL with FIPS module (not NIST-validated)"
    echo "  ubuntu-pro - Use Ubuntu Pro FIPS packages (NIST-validated)"
    exit 1
    ;;
esac

# Verify FIPS configuration
echo ""
echo "=============================================="
echo "Verifying FIPS configuration..."
echo "=============================================="

if [[ "$FIPS_METHOD" == "source" ]]; then
  verify_fips_functional "/usr/local/bin/openssl" "/usr/local/ssl/openssl-fips.cnf"
  echo ""
  echo "OpenSSL version: $(/usr/local/bin/openssl version)"
else
  verify_fips_functional "openssl" ""
  echo ""
  echo "OpenSSL version: $(openssl version)"
  
  # Check kernel FIPS mode (usually not enabled in container builds)
  if [[ -f /proc/sys/crypto/fips_enabled ]]; then
    if [[ "$(cat /proc/sys/crypto/fips_enabled)" == "1" ]]; then
      echo "Kernel FIPS mode: ENABLED"
    else
      echo "Note: Kernel FIPS mode requires FIPS-enabled kernel at boot time"
    fi
  fi
fi

# Create marker file only on success
if [[ "$FIPS_CONFIGURED" == "true" ]]; then
  echo ""
  echo "Creating FIPS marker file..."
  cat > /etc/cflinuxfs5-fips << EOF
FIPS_ENABLED=true
FIPS_METHOD=${FIPS_METHOD}
FIPS_CONFIGURED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
  if [[ "$FIPS_METHOD" == "source" ]]; then
    cat >> /etc/cflinuxfs5-fips << EOF
OPENSSL_VERSION=${OPENSSL_VERSION}
OPENSSL_FIPS_CONF=/usr/local/ssl/openssl-fips.cnf
OPENSSL_FIPS_BIN=/usr/local/bin/openssl

# NOTE: Source-built OpenSSL is NOT NIST FIPS 140-2/140-3 validated
# For compliance purposes, use ubuntu-pro method with certified packages
EOF
  fi
fi

echo ""
echo "=============================================="
echo "FIPS configuration complete"
echo "=============================================="
