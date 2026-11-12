#!/usr/bin/env bash
# Creates a self-signed code-signing identity "TouchBuddy Local Signing" in the login keychain.
# Run by the owner: it triggers keychain prompts (your login password).
set -euo pipefail

NAME="TouchBuddy Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL="/usr/bin/openssl"

if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
    echo "Signing identity '$NAME' already exists; nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

PASS="$("$OPENSSL" rand -hex 16)"

echo "About to create the self-signed code-signing certificate '$NAME' (valid ~10 years)."
echo "macOS will then ask for your login password to import the key and to trust the certificate for code signing."

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout "pass:$PASS"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
    echo "Created signing identity '$NAME'."
else
    echo "error: identity '$NAME' is still not listed by 'security find-identity -p codesigning'." >&2
    exit 1
fi
