# TLS Certificate Troubleshooting (Cloudflare WARP)

## Environment Context

This development environment uses Cloudflare WARP (1.1.1.1 VPN), which acts as a TLS-intercepting proxy. It installs its own root CA ("Gateway CA - Cloudflare Managed G1") into the macOS system keychain. Many tools ship their own CA bundles that do NOT include this certificate, causing TLS verification failures.

## Recognizing the Problem

When you see ANY of these error patterns, the cause is almost certainly the Cloudflare WARP certificate missing from the tool's CA bundle:

### Error Signatures
- `UNABLE_TO_VERIFY_LEAF_SIGNATURE` (Node.js)
- `SELF_SIGNED_CERT_IN_CHAIN` (Node.js)
- `certificate verify failed` (Python/pip/requests)
- `SSL: CERTIFICATE_VERIFY_FAILED` (Python)
- `unable to get local issuer certificate` (curl/git)
- `SSL certificate problem: unable to get local issuer certificate` (git)
- `CERTIFICATE_VERIFY_FAILED` (PlatformIO / embedded Python)
- `SSLError` or `SSLCertVerificationError` (Python)
- `ERR_TLS_CERT_ALTNAME_INVALID` (Node.js)
- `DEPTH_ZERO_SELF_SIGNED_CERT` (npm/yarn)
- `SSL routines::certificate verify failed` (OpenSSL)
- `curl: (60) SSL certificate problem` (curl)
- `fatal: unable to access 'https://...'` with SSL error (git)
- `RequestError: certificate has expired` (package managers)
- `CERT_HAS_EXPIRED` when cert clearly hasn't (proxy rewriting)

### Context Clues
- Errors happen on outbound HTTPS requests (package installs, API calls, git clone)
- The same URL works in a browser (browsers use the system keychain)
- Errors started after connecting to corporate VPN / Cloudflare WARP
- The error mentions a certificate chain or CA verification

## Automatic Remediation

When you detect a TLS cert error matching the patterns above, fix it immediately:

### Step 1: Check if the combined bundle exists
```bash
ls -la ~/.cloudflare-certs/combined-ca-bundle.pem
```

### Step 2a: If the bundle exists, set env vars for the current tool
```bash
# For the current shell session
export NODE_EXTRA_CA_CERTS="$HOME/.cloudflare-certs/cloudflare-warp-ca.pem"
export SSL_CERT_FILE="$HOME/.cloudflare-certs/combined-ca-bundle.pem"
export REQUESTS_CA_BUNDLE="$HOME/.cloudflare-certs/combined-ca-bundle.pem"
export PIP_CERT="$HOME/.cloudflare-certs/combined-ca-bundle.pem"
export CURL_CA_BUNDLE="$HOME/.cloudflare-certs/combined-ca-bundle.pem"
export GIT_SSL_CAINFO="$HOME/.cloudflare-certs/combined-ca-bundle.pem"
export CARGO_HTTP_CAINFO="$HOME/.cloudflare-certs/combined-ca-bundle.pem"
export DENO_CERT="$HOME/.cloudflare-certs/cloudflare-warp-ca.pem"
```

### Step 2b: If the bundle does NOT exist, create it
```bash
bash scripts/fix-cloudflare-certs.sh
```
If the project doesn't have the script, create the bundle manually:
```bash
mkdir -p ~/.cloudflare-certs
CF_CERT="/Library/Application Support/Cloudflare/installed_cert.pem"
if [[ ! -f "$CF_CERT" ]]; then
  security find-certificate -a -c "Cloudflare" -p /Library/Keychains/System.keychain > ~/.cloudflare-certs/cloudflare-warp-ca.pem
else
  cp "$CF_CERT" ~/.cloudflare-certs/cloudflare-warp-ca.pem
fi
cat /etc/ssl/cert.pem ~/.cloudflare-certs/cloudflare-warp-ca.pem > ~/.cloudflare-certs/combined-ca-bundle.pem
```

### Step 3: Retry the failed command with the env vars set

### Step 4: If the fix works, tell the user to make it permanent
Suggest adding the exports to `~/.zshrc` or running:
```bash
eval "$(bash scripts/fix-cloudflare-certs.sh)"
```

## Tool-Specific Fixes

Some tools need additional handling beyond env vars:

### PlatformIO (embedded Python)
PlatformIO uses its own Python and certifi bundle. After setting env vars:
```bash
# Inject Cloudflare cert into PlatformIO's certifi bundle
pio_certifi=$(~/.platformio/penv/bin/python -c "import certifi; print(certifi.where())" 2>/dev/null)
if [[ -n "$pio_certifi" ]]; then
  cat ~/.cloudflare-certs/cloudflare-warp-ca.pem >> "$pio_certifi"
fi
```

### Python virtual environments
Each venv may have its own certifi. After activating a venv:
```bash
venv_certifi=$(python -c "import certifi; print(certifi.where())" 2>/dev/null)
if [[ -n "$venv_certifi" ]]; then
  cat ~/.cloudflare-certs/cloudflare-warp-ca.pem >> "$venv_certifi"
fi
```

### pip (standalone)
```bash
pip config set global.cert ~/.cloudflare-certs/combined-ca-bundle.pem
```

### conda
```bash
conda config --set ssl_verify ~/.cloudflare-certs/combined-ca-bundle.pem
```

### npm/yarn
```bash
npm config set cafile ~/.cloudflare-certs/combined-ca-bundle.pem
# or for yarn
yarn config set httpsCaFilePath ~/.cloudflare-certs/combined-ca-bundle.pem
```

### Docker
```dockerfile
COPY combined-ca-bundle.pem /etc/ssl/certs/ca-certificates.crt
```

## Do NOT
- Do NOT set `NODE_TLS_REJECT_UNAUTHORIZED=0` — this disables all TLS verification.
- Do NOT use `--insecure` or `--no-check-certificate` as a fix.
- Do NOT use `pip install --trusted-host` as a permanent solution.
- Do NOT use `git config http.sslVerify false`.
- These are security bypasses, not fixes. Always use the proper CA bundle approach.
