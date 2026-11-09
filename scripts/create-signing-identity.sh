#!/bin/bash
# Creates a free, self-signed code signing identity for NotchNotch builds.
#
# Why: ad-hoc signatures change with every build, so macOS forgets the
# Automation and Calendar permissions after each update. A stable identity keeps
# them. It does NOT replace notarization: on other Macs, the first launch still
# needs System Settings › Privacy & Security › Open Anyway.
#
# Usage:
#   scripts/create-signing-identity.sh                 # create + trust in the login keychain
#   scripts/create-signing-identity.sh --export FILE   # also write a .p12 for CI (GitHub secret)
#
# Then build with:
#   NOTCHNOTCH_SIGN_IDENTITY="NotchNotch Self-Signed" pnpm release
set -euo pipefail

NAME="NotchNotch Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
EXPORT=""
if [[ "${1:-}" == "--export" ]]; then EXPORT="${2:?--export needs a file path}"; fi

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists in your login keychain."
  [[ -z "$EXPORT" ]] && exit 0
  echo "To export it, use Keychain Access › My Certificates › $NAME › Export (.p12)."
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

# The system LibreSSL writes PKCS#12 files that `security import` accepts.
/usr/bin/openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
PASSWORD=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/identity.p12" -passout "pass:$PASSWORD"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASSWORD" -T /usr/bin/codesign
echo "Trusting the certificate for code signing (macOS asks for your password)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if [[ -n "$EXPORT" ]]; then
  ( umask 077; cp "$WORK/identity.p12" "$EXPORT" )
  echo
  echo "Exported to $EXPORT (keep it private). For the GitHub release workflow:"
  echo "  base64 -i \"$EXPORT\" | gh secret set SIGNING_P12"
  echo "  gh secret set SIGNING_P12_PASSWORD --body \"$PASSWORD\""
  echo "  gh secret set SIGNING_IDENTITY --body \"$NAME\""
fi

echo
security find-identity -v -p codesigning "$KEYCHAIN" | grep "$NAME" || {
  echo "The identity is not valid for code signing yet. Open Keychain Access, double-click"
  echo "\"$NAME\" › Trust › Code Signing: Always Trust."; exit 1; }
echo "Done. Build with: NOTCHNOTCH_SIGN_IDENTITY=\"$NAME\" pnpm release"
