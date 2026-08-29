# knock-examples

Live proof of [knock](https://github.com/trivoallan/knock)'s provenance stamp.

Every Monday a workflow in this repository runs the **real** example policies — checked out of the
knock repository at a pinned tag, never copied here — and publishes the results to GHCR. So you are
verifying the exact file the documentation site shows, produced by a run you can inspect.

You need [`regctl`](https://github.com/regclient/regclient) and
[`cosign` **v3**](https://github.com/sigstore/cosign). No account, no credentials, no cluster.

```bash
./verify.sh trivoallan
```

That script is the workflow's own final step, so this page cannot promise something the showcase does
not do. What it runs, on one copied image and one rebuilt one:

## 1. Read the stamp

```bash
regctl manifest get ghcr.io/trivoallan/demo/debian:bookworm-slim-eu \
  --format '{{json .Annotations}}' | jq .
```

```json
{
  "io.knock.owners": "group:default/platform,group:default/base-images",
  "io.knock.policy": "debian-tz",
  "io.knock.transform.steps": "setTimezone",
  "io.knock.transform.version": "sha256:7a56a9650ad282167202e76a8f83d8d1758250dd43e85e7abb255613a6cbd103",
  "io.knock.variant": "eu",
  "org.opencontainers.image.base.digest": "sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171",
  "org.opencontainers.image.base.name": "docker.io/library/debian:bookworm-slim",
  "org.opencontainers.image.vendor": "Example Platform Team"
}
```

`org.opencontainers.image.base.*` are OCI-standard keys, so any scanner reads them for free.
`io.knock.transform.steps` is what knock changed on the way through — this image was **rebuilt**, not
copied, and the lineage says so.

## 2. Fetch the package SBOM

```bash
regctl artifact list ghcr.io/trivoallan/demo/debian:bookworm-slim-eu
```

Both SPDX and CycloneDX are attached as OCI referrers on the same digest — the package inventory that
turns *"which images ship the vulnerable package?"* into one query at CVE time.

> GHCR does not implement the OCI referrers API, so these are stored under the specification's
> fallback tag schema. `regctl` resolves that transparently, which is why the command above works —
> but a raw `curl` against `/v2/.../referrers/` will find nothing, and you will see `sha256-…` tags
> beside the real ones in the tag listing. That is the fallback, not damage.

## 3. Verify the signature

```bash
cosign verify-attestation \
  --type https://knock.dev/predicate/transform/v1 \
  --certificate-identity-regexp '^https://github.com/trivoallan/knock-examples/\.github/workflows/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/trivoallan/demo/debian:bookworm-slim-eu
```

Note what you are trusting. The signing identity is not a key anyone handed you — it is the URL of
the GitHub Actions workflow that produced the image, recorded in Sigstore's transparency log at
signing time. You verify *that this workflow ran*, which is checkable without trusting us.

Both SBOMs are signed too, under `https://spdx.dev/Document` and `https://cyclonedx.org/bom`. Pass
either to `--type` to verify those instead.

## The counter-example

`ghcr.io/trivoallan/bypass/busybox:1.37.0` was pushed **directly** to the same registry,
never through knock. Run the same three commands against it: no stamp, no SBOM, no signature.

That is the whole argument, standing next to its own refutation. What does not come through the
mandated door is ungovernable — and a stamp on part of the fleet leaves a blast-radius query with
blind spots.

## What runs here

| Policy | Path | What it shows |
|---|---|---|
| [`reference/busybox`](https://github.com/trivoallan/knock/blob/main/docs/examples/reference/busybox/busybox.yml) | copy | semver tag selection, derived moving aliases |
| [`reference/debian-tz`](https://github.com/trivoallan/knock/blob/main/docs/examples/reference/debian-tz/debian-tz.yml) | rebuild | one source tag fanned into two regional variants, `io.knock.transform.*` lineage |

The knock version is pinned in [`knock.env`](knock.env) and bumped deliberately, so a regression in
knock cannot redden this page on its own. A nightly canary replays the same policies against knock's
`main` into a throwaway namespace, so a regression shows up there first.

## What is not here

**The skill front door.** knock can place an external agent skill — a git repository fetched at an
immutable commit, packaged into a byte-reproducible zip, stamped, and pushed as an OCI artifact a
developer's client installs from. Every piece is built and tested, and there is a real example
policy — [`skills/agent-skill.yml`](https://github.com/trivoallan/knock/blob/main/docs/examples/skills/agent-skill.yml),
placing `mcp-builder` out of Anthropic's public skills repository.

It is not in the table above because **nothing here can run it yet**: no CLI verb composes the
intake pieces, so `knock reconcile` on a skill policy reports `failed` and exits 1 — and the pinned
release in `knock.env` predates the work regardless. Adding it to the showcase loop today would
redden this page every Monday and, worse, would have this page promise something the workflow does
not do. It moves to *What runs here* when the verb ships and a release carries it, not before.

No coverage report. `knock audit` enumerates through the OCI catalog API, which GHCR does not serve,
so the bypass image above is a manual contrast rather than an automated blind-spot count. That is a
GHCR limitation, not a knock one — against a catalog-capable registry, `knock audit --signed --sbom`
reports the same fleet as `uncovered / stamped / signed / has-SBOM`.
