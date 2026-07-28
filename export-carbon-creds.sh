#!/usr/bin/env bash
# Export carbon's TPM-bound systemd-creds as a portable age-encrypted bundle, so
# the secrets survive losing the TPM. Run ON carbon (rescue mode, as root).
# Plaintext only ever lives in tmpfs (/run) and is wiped on exit.
#
# Recipients: put age recipients (age1… or ssh pubkey lines) in
# /root/creds-recipients.txt — recommended: YOUR personal ssh pubkey (backed up in
# your password manager). If that file is missing, falls back to a passphrase
# prompt (needs an interactive terminal).
set -uo pipefail

SRC=/usr/lib/credstore.encrypted
RECIP=/root/creds-recipients.txt
OUT=/root/carbon-creds-backup.tar.age

AGE=$(command -v age || find /nix/store -maxdepth 3 -type f -path '*-age-*/bin/age' 2>/dev/null | head -1)
[ -x "${AGE:-}" ] || { echo "ERROR: age not found (bring up net + 'nix run nixpkgs#age')." >&2; exit 1; }

WORK=$(mktemp -d /run/creds-export.XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

echo "== decrypting $SRC into tmpfs =="
ok=0; fail=0; failed=""
for f in "$SRC"/*; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  if systemd-creds decrypt "$f" "$WORK/$n" 2>/dev/null; then
    printf '  ok    %s\n' "$n"; ok=$((ok+1))
  else
    printf '  FAIL  %s\n' "$n"; fail=$((fail+1)); failed="$failed $n"
  fi
done
echo "decrypted $ok, failed $fail"
[ "$ok" -gt 0 ] || { echo "nothing decrypted; aborting" >&2; exit 1; }

echo "== encrypting bundle -> $OUT =="
if [ -s "$RECIP" ]; then
  echo "recipients from $RECIP"
  tar c -C "$WORK" . | "$AGE" -R "$RECIP" -o "$OUT"
else
  echo "no $RECIP -> passphrase mode (use a STRONG passphrase; save it in your password manager)"
  tar c -C "$WORK" . | "$AGE" -p -o "$OUT"
fi
chmod 600 "$OUT"

echo
echo "DONE. Wrote $OUT ($(stat -c %s "$OUT") bytes) containing $ok creds."
[ -n "$failed" ] && echo "NOTE: could not decrypt:$failed (embedded name != filename — grab those manually)."
echo "Decrypt later with:"
echo "  age -d [-i ~/.ssh/id_ed25519] $OUT | tar xv -C ./carbon-creds"
