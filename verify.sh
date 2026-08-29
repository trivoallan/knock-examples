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
# `${2-}` and not `${2:-…}`: the workflow passes an EMPTY namespace by default (it
# publishes straight under the owner, since the policies already declare
# `project: demo`). `:-` would substitute a default for empty as well as unset, and
# the script would then verify a different, possibly stale, set of images — passing
# green while looking at the wrong thing, which is the one failure this script must
# not have.
NS="${2-}"
PREFIX="ghcr.io/${OWNER}${NS:+/$NS}"

fail=0
note() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
bad()  { printf '  MISSING: %s\n' "$1"; fail=1; }
good() { printf '  ok: %s\n' "$1"; }
skip() { printf '  n/a: %s\n' "$1"; }

# Two of the seven policies declare no alias, so their destination carries only the
# concrete upstream versions and those drift with every upstream release. Hardcoding
# one would quietly stop verifying the newest placement. Filter first: GHCR forces
# clients to write referrers-fallback `sha256-<hex>` tags, which land in this listing
# beside the real ones — a bare `tail -1` would pick one of those and report a
# missing stamp on an artifact that is not an image at all.
highest_tag() {
  local repo="$1" pattern="$2" tag
  tag=$(regctl tag ls "${PREFIX}/${repo}" 2>/dev/null \
          | grep -E "$pattern" | sort -V | tail -1)
  # Returns non-zero rather than setting `fail`: this runs inside a command
  # substitution, so the subshell's assignment would never reach the caller — the
  # reference would silently vanish from the list and the script would pass green
  # while verifying less than it claims. The caller sets `fail`.
  [ -n "$tag" ] || { printf '  NO TAG matching %s in %s\n' "$pattern" "$repo" >&2; return 1; }
  printf '%s:%s\n' "${PREFIX}/${repo}" "$tag"
}

# Every `sha-<revision>` placed in the skill repository. The policy pins one immutable
# commit today, so this is one entry; verifying whatever is there beats hardcoding a
# revision that a bump in knock's own policy file would silently invalidate.
skill_refs() {
  local repo="skills/mcp-builder" tag
  for tag in $(regctl tag ls "${PREFIX}/${repo}" 2>/dev/null | grep -E '^sha-'); do
    printf '%s:%s\n' "${PREFIX}/${repo}" "$tag"
  done
}

# One entry per reference: what must be there, and what must NOT be expected.
#
#   <ref>|<stamp anchor>|<sbom>|<signature>
#
# The stamp anchor differs by source. An image copied or rebuilt from an upstream
# image is anchored on `org.opencontainers.image.base.digest`. A git-sourced artifact
# has no base image and knock refuses to fabricate one (ADR 0020, `domain/stamp.py`),
# so it is anchored on `org.opencontainers.image.revision` — the upstream commit,
# which is exactly what that OCI key means.
#
# The skill also carries NEITHER an SBOM NOR a signature: `use_cases/reconcile_git.py`
# contains no occurrence of `sbom` or `attest`. That is the intake path's current
# shape, not a failure — asserting all three uniformly here would turn a correct run
# red, so the expectation is written down instead of assumed.
ENTRIES=(
  "${PREFIX}/demo/busybox:latest|org.opencontainers.image.base.digest|yes|yes"
  "${PREFIX}/demo/debian:bookworm-slim-eu|org.opencontainers.image.base.digest|yes|yes"
  "${PREFIX}/demo/debian:bookworm-slim-us|org.opencontainers.image.base.digest|yes|yes"
  "${PREFIX}/demo/redis:latest|org.opencontainers.image.base.digest|yes|yes"
  "${PREFIX}/demo/mongo:8.0|org.opencontainers.image.base.digest|yes|yes"
)
# Aliases above, discovery below — see highest_tag.
for repo in demo/redis-retention demo/redis-delegated; do
  if ref=$(highest_tag "$repo" '^7\.2\.'); then
    ENTRIES+=("${ref}|org.opencontainers.image.base.digest|yes|yes")
  else
    fail=1
  fi
done

skills_found=0
while read -r ref; do
  [ -n "$ref" ] || continue
  ENTRIES+=("${ref}|org.opencontainers.image.revision|no|no")
  skills_found=1
done < <(skill_refs)
[ "$skills_found" -eq 1 ] || { echo "  NO sha-<revision> tag in skills/mcp-builder" >&2; fail=1; }

printf 'verifying %d references under %s\n' "${#ENTRIES[@]}" "$PREFIX"

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r image anchor want_sbom want_sig <<< "$entry"
  note "$image"

  # 1. the provenance stamp
  annotations=$(regctl manifest get "$image" --format '{{json .Annotations}}' 2>/dev/null)
  if [ -z "$annotations" ] || [ "$annotations" = "null" ]; then
    bad "no annotations at all"
  else
    echo "$annotations" | jq .
    for key in "$anchor" io.knock.policy; do
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
  if [ "$want_sbom" = "yes" ]; then
    types=$(regctl artifact list "$image" --format '{{json .}}' 2>/dev/null \
              | jq -r '.descriptors[]?.artifactType' | sort -u)
    echo "  referrer artifact types:"; echo "$types" | sed 's/^/    /'
    echo "$types" | grep -q 'spdx'      && good "SPDX SBOM referrer"      || bad "SPDX SBOM referrer"
    echo "$types" | grep -q 'cyclonedx' && good "CycloneDX SBOM referrer" || bad "CycloneDX SBOM referrer"
  else
    skip "no SBOM expected — the git intake path attaches none"
  fi

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
  if [ "$want_sig" = "yes" ]; then
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
  else
    skip "no signature expected — the git intake path signs nothing"
  fi
done

echo
if [ "$fail" -ne 0 ]; then
  echo "FAILED — something was placed without its full provenance." >&2
  exit 1
fi
echo "All checks passed."
