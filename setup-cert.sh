#!/bin/bash
# Creates a stable self-signed code-signing certificate named "MightyMouse Signing"
# in the login keychain. Signing with a stable identity means the macOS Accessibility
# (TCC) grant survives rebuilds, instead of being invalidated on every ad-hoc re-sign.
set -euo pipefail

NAME="MightyMouse Signing"

if security find-certificate -c "$NAME" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
  echo "Certificate '$NAME' already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/cert.key" -out "$TMP/cert.crt" \
  -days 3650 -nodes -config "$TMP/cert.cnf"
openssl pkcs12 -export -inkey "$TMP/cert.key" -in "$TMP/cert.crt" \
  -out "$TMP/cert.p12" -name "$NAME" -passout pass:mg

security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P mg -T /usr/bin/codesign

echo "Created '$NAME'. On first build macOS may ask to allow codesign to use the key -> click 'Always Allow'."
