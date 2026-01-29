# FIPS Support in cflinuxfs5

This document describes the FIPS (Federal Information Processing Standards) support in cflinuxfs5.

## Overview

cflinuxfs5 can be built with FIPS-compliant cryptographic modules using two methods:

| Method | NIST Validated | Requirements |
|--------|----------------|--------------|
| `source` | No | None |
| `ubuntu-pro` | Yes | Ubuntu Pro subscription |

## Important Disclaimer

### Source Method Limitations

The `source` method builds OpenSSL with FIPS module support, but **this does NOT produce NIST FIPS 140-2/140-3 validated cryptography**. 

FIPS validation is specific to:
- A particular binary compiled in a specific controlled environment
- A validation certificate issued by NIST/CMVP
- Integrity verification against known-good certified binaries

Building from source, even with identical configuration, does not inherit the FIPS validation status.

**Use the `source` method only for:**
- Development and testing of FIPS-compatible applications
- Environments where FIPS-like algorithms are required but formal validation is not mandatory

### Ubuntu Pro Method

The `ubuntu-pro` method uses Canonical's FIPS-validated packages, which **are NIST certified**. This is the recommended method for production FIPS compliance.

## Usage

### Standard Build (No FIPS)

```bash
make
```

### FIPS Build - Source Method

```bash
make FIPS=true FIPS_METHOD=source
```

### FIPS Build - Ubuntu Pro Method

1. Create a token file (token is never stored in image):
   ```bash
   echo "your-ubuntu-pro-token" > .ubuntu-pro-token
   chmod 600 .ubuntu-pro-token
   ```

2. Build:
   ```bash
   make FIPS=true FIPS_METHOD=ubuntu-pro
   ```

3. Clean up token:
   ```bash
   rm .ubuntu-pro-token
   ```

### Security Note

The Ubuntu Pro token is passed via Docker BuildKit secrets, which:
- Are mounted temporarily during build
- Never stored in image layers
- Not visible in `docker history`

## Verifying FIPS Configuration

After building, the rootfs contains `/etc/cflinuxfs5-fips` with configuration details:

```bash
# Extract and check marker file
docker run --rm <image> cat /etc/cflinuxfs5-fips
```

### Source Method Verification

```bash
# Check FIPS provider is loaded
OPENSSL_CONF=/usr/local/ssl/openssl-fips.cnf /usr/local/bin/openssl list -providers

# Expected output should include:
#   fips
#     name: OpenSSL FIPS Provider
#     status: active
```

### Ubuntu Pro Verification

```bash
# Check system OpenSSL
openssl list -providers
```

## Runtime Configuration

### Source Method

Applications must explicitly use the FIPS-enabled OpenSSL configuration:

```bash
# Option 1: Set environment
export OPENSSL_CONF=/usr/local/ssl/openssl-fips.cnf
export PATH="/usr/local/bin:$PATH"
./your-application

# Option 2: Per-command
OPENSSL_CONF=/usr/local/ssl/openssl-fips.cnf /usr/local/bin/openssl s_client ...
```

### Ubuntu Pro Method

FIPS mode is system-wide. Applications use the system OpenSSL automatically.

## File Locations

### Source Method

| File | Path |
|------|------|
| OpenSSL binary | `/usr/local/bin/openssl` |
| FIPS config | `/usr/local/ssl/openssl-fips.cnf` |
| FIPS module | `/usr/local/lib/ossl-modules/fips.so` |
| Libraries | `/usr/local/lib/libssl.so*`, `/usr/local/lib/libcrypto.so*` |
| Marker file | `/etc/cflinuxfs5-fips` |

### Ubuntu Pro Method

Uses system defaults:
- `/usr/bin/openssl`
- `/etc/ssl/openssl.cnf`
- `/etc/cflinuxfs5-fips`

## Troubleshooting

### "FIPS provider not available"

For source builds, ensure you're using the correct OpenSSL binary and config:
```bash
/usr/local/bin/openssl version  # Should show 3.0.x
OPENSSL_CONF=/usr/local/ssl/openssl-fips.cnf /usr/local/bin/openssl list -providers
```

### "Ubuntu Pro token not provided"

Ensure token file exists and is readable:
```bash
ls -la .ubuntu-pro-token
cat .ubuntu-pro-token  # Verify content
```

### Build fails with checksum error

The OpenSSL source checksum is pinned. If it fails:
1. Verify network connectivity
2. Check if OpenSSL version was updated (requires script update)
3. Report as potential supply chain issue

## Security Considerations

1. **Supply Chain Security**: Source method verifies OpenSSL downloads via SHA256 checksum
2. **Token Security**: Ubuntu Pro tokens use BuildKit secrets (never stored in image)
3. **Isolation**: Source-built OpenSSL installs to `/usr/local` to avoid conflicts
4. **Compliance**: Only `ubuntu-pro` method provides actual FIPS compliance for certification

## References

- [NIST CMVP](https://csrc.nist.gov/projects/cryptographic-module-validation-program)
- [Ubuntu Pro FIPS](https://ubuntu.com/security/fips)
- [OpenSSL FIPS Module](https://www.openssl.org/docs/man3.0/man7/fips_module.html)
- [Docker BuildKit Secrets](https://docs.docker.com/build/building/secrets/)
