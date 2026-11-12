#!/usr/bin/env bash
# Creates a self-signed code-signing identity "TouchBuddy Local Signing" in the login keychain.
# Run by the owner: it triggers keychain prompts (your login password).
set -euo pipefail

NAME="TouchBuddy Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL="/usr/bin/openssl"

VALID="$(security find-identity -v -p codesigning)"
if grep -qF "\"$NAME\"" <<<"$VALID"; then
    echo "Signing identity '$NAME' already exists and is valid; nothing to do."
    exit 0
fi
ALL="$(security find-identity -p codesigning)"

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

echo "About to create the self-signed code-signing certificate '$NAME' (valid ~10 years)."
echo "macOS will then ask for your login password to import the key and to trust the certificate for code signing."

if grep -qF "\"$NAME\"" <<<"$ALL"; then
    echo "Identity '$NAME' exists but is not trusted yet; trusting the existing certificate (no duplicate created)."
    security find-certificate -c "$NAME" -p >"$WORK/cert.pem"
else
    TB_P12_PASS="$("$OPENSSL" rand -hex 16)"
    export TB_P12_PASS
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf"
    "$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -name "$NAME" -out "$WORK/identity.p12" -passout env:TB_P12_PASS
    # security import has no env/stdin option for the passphrase; it is a random one-shot value
    # protecting a temp file that is deleted on exit, so briefly appearing in argv is accepted.
    security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TB_P12_PASS" -T /usr/bin/codesign
fi
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

FINAL="$(security find-identity -v -p codesigning)"
if grep -qF "\"$NAME\"" <<<"$FINAL"; then
    echo "Signing identity '$NAME' is ready."
else
    echo "error: identity '$NAME' is still not valid; re-run this script to retry." >&2
    exit 1
fi
