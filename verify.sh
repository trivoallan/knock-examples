#!/usr/bin/env bash
# The proof — and the same commands the README shows, so the page cannot promise
# something the showcase does not do.
#
#   ./verify.sh <owner> [namespace]
#
# It also runs as the workflow's last step. knock has no transaction: if the SBOM
# or the signature fails AFTER the copy, the image is placed without an inventory
# — precisely the coverage hole the product claims to close. Running this before
# anyone looks is what stops a half-stamped publish from going public.
set -uo pipefail

OWNER="${1:?usage: verify.sh <owner> [namespace]}"
# `${2-}` and not `${2:-…}`: the showcase passes an EMPTY namespace (it publishes
# straight under the owner, since the policies already declare `project: demo`).
# `:-` would substitute a default for empty as well as unset, and the script would
# then verify a different, possibly stale, set of images — passing green while
# looking at the wrong thing, which is the one failure this script must not have.
NS="${2-}"
PREFIX="ghcr.io/${OWNER}${NS:+/$NS}"

# One image per path: a copied one and a rebuilt one. The rebuild is the one that
# carries transform lineage, so both are checked rather than a single sample.
IMAGES=(
  "${PREFIX}/demo/busybox:1.38.0"
  "${PREFIX}/demo/debian:bookworm-slim-eu"
)

fail=0
note() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
bad()  { printf '  MISSING: %s\n' "$1"; fail=1; }
good() { printf '  ok: %s\n' "$1"; }

for image in "${IMAGES[@]}"; do
  note "$image"

  # 1. the provenance stamp
  annotations=$(regctl manifest get "$image" --format '{{json .Annotations}}' 2>/dev/null)
  if [ -z "$annotations" ] || [ "$annotations" = "null" ]; then
    bad "no annotations at all"
  else
    echo "$annotations" | jq .
    for key in org.opencontainers.image.base.digest io.knock.policy; do
      if echo "$annotations" | jq -e --arg k "$key" 'has($k)' >/dev/null; then
        good "stamp carries $key"
      else
        bad "stamp is missing $key"
      fi
    done
  fi

  # 2. the package SBOM, attached as an OCI referrer. GHCR serves no referrers API,
  #    so regctl resolves this through the fallback tag schema — transparently for
  #    this command, but a raw curl against /v2/.../referrers/ would find nothing.
  types=$(regctl artifact list "$image" --format '{{json .}}' 2>/dev/null \
            | jq -r '.descriptors[]?.artifactType' | sort -u)
  echo "  referrer artifact types:"; echo "$types" | sed 's/^/    /'
  echo "$types" | grep -q 'spdx'      && good "SPDX SBOM referrer"      || bad "SPDX SBOM referrer"
  echo "$types" | grep -q 'cyclonedx' && good "CycloneDX SBOM referrer" || bad "CycloneDX SBOM referrer"

  # 3. the signature — the identity IS the workflow that produced it, so a visitor
  #    trusts a GitHub Actions run rather than trusting us.
  #    Needs cosign v3: knock signs into a sigstore bundle
  #    (application/vnd.dev.sigstore.bundle.v0.3+json), which cosign v2 cannot read
  #    — it reports the attestation as absent rather than as unreadable.
  # Capture rather than pipe: piping into `tail` would make the `if` test tail's
  # exit status, which is always 0 — the check would silently always pass.
  #    `--type` is required: without it cosign looks for the default `custom`
  #    predicate and rejects, listing what it did find — which reads like a missing
  #    signature but is the opposite. knock signs three predicates here: its own
  #    transform provenance, and both SBOMs, so the inventories are signed too.
  if out=$(cosign verify-attestation \
       --type https://knock.dev/predicate/transform/v1 \
       --certificate-identity-regexp "^https://github.com/${OWNER}/knock-examples/\.github/workflows/" \
       --certificate-oidc-issuer https://token.actions.githubusercontent.com \
       "$image" 2>&1); then
    good "signed, and the identity is this repository's workflow"
  else
    printf '%s\n' "$out" | tail -6 | sed 's/^/    /'
    bad "no attestation verifiable against this repository's workflow identity"
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "FAILED — something was placed without its full provenance." >&2
  exit 1
fi
echo "All checks passed."
