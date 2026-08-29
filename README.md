# knock-examples

Live proof of [knock](https://github.com/trivoallan/knock)'s provenance stamp.

Every night a workflow in this repository runs the **real** example policies — checked out of the
knock repository, never copied here — and publishes the results to GHCR. So you are verifying the
exact files the documentation site shows, produced by a run you can inspect.

It runs knock's `main`, not a pinned release. That is deliberate, and it has a price: a regression
in knock reddens this page. The alternative was worse. While this page pinned a released tag, it
could only ever show what a release already carried — so `skills/agent-skill`, a policy this page
documents, had never once run here. A showcase that cannot run a third of what it describes is not
showing you the product; it is showing you the safe part of it.

You need [`regctl`](https://github.com/regclient/regclient) and
[`cosign` **v3**](https://github.com/sigstore/cosign). No account, no credentials, no cluster.

```bash
./verify.sh trivoallan
```

That script is the workflow's own final step, so this page cannot promise something the run does
not do. It checks eight references — the copy path, the rebuild path and both of its regional
variants, and the git intake path. What it runs on each:

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

The git-sourced artifact is the one exception: it has no base image, and knock refuses to fabricate
one. It is anchored on `org.opencontainers.image.revision` — the upstream commit — instead.

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

Seven example directories, reconciled in one pass. Every one of them lives in the knock repository;
none is copied here.

| Policy | Path | What it shows | Verified |
|---|---|---|---|
| [`reference/busybox`](https://github.com/trivoallan/knock/blob/main/docs/examples/reference/busybox/busybox.yml) | copy | semver tag selection, derived moving aliases | stamp · SBOM · signature |
| [`reference/debian-tz`](https://github.com/trivoallan/knock/blob/main/docs/examples/reference/debian-tz/debian-tz.yml) | rebuild | one source tag fanned into two regional variants, `io.knock.transform.*` lineage | stamp · SBOM · signature (both variants) |
| [`skills/agent-skill`](https://github.com/trivoallan/knock/blob/main/docs/examples/skills/agent-skill.yml) | git intake | a git repository placed as an OCI artifact under an immutable `sha-<revision>` tag plus a moving alias | stamp only — see below |
| [`redis`](https://github.com/trivoallan/knock/blob/main/docs/examples/redis/redis.yml) | copy | semver aliases over a heavier image | stamp · SBOM · signature |
| [`retention`](https://github.com/trivoallan/knock/blob/main/docs/examples/retention/redis.yml) | copy | the `archive` knobs — keep N, mark the rest pending-deletion | stamp · SBOM · signature |
| [`pending-deletion`](https://github.com/trivoallan/knock/blob/main/docs/examples/pending-deletion/pending-deletion.yml) | copy | `deletionMode: mark` — a referrer instead of a delete, for an external reaper | stamp · SBOM · signature |
| [`brownfield`](https://github.com/trivoallan/knock/blob/main/docs/examples/brownfield/mongo.yml) | copy | a package-level SBOM that catalogs what distro scanners miss | stamp · SBOM · signature |

**The git intake path carries no SBOM and no signature.** That is the path's shape today, not a
failure here — `verify.sh` asserts the stamp on it and says so out loud, rather than reporting a
correct run as red.

The workflow reconciles `skills/` twice on purpose: the second run must report `skipped=1,
imported=0`, because a scheduled run over an unchanged upstream that quietly re-pushed would still
exit 0.

Three example directories are deliberately absent. `admission/` holds a Kyverno policy, not a
MirrorPolicy, and knock's loader refuses a directory containing one. `reference/debian-xz` sources a
fixture seeded into an in-cluster registry, unreachable from a hosted runner. `hardened/` and
`attested/` reconcile, but need an internal CA and package mirror that do not exist in a public
repository.

## Replaying a released version

The workflow takes a `version` input on `workflow_dispatch`: empty (the scheduled default) builds
knock from `main`, and a tag replays that release instead.

Pass a `namespace` when you do. `reconcile` converges on **content**, not on the stamp: a replay
writes the older release's stamp onto the same references, and the next nightly run sees identical
content, skips, and does **not** repair it.

## What is not here

No coverage report. `knock audit` enumerates through the OCI catalog API, which GHCR does not serve,
so the bypass image above is a manual contrast rather than an automated blind-spot count. That is a
GHCR limitation, not a knock one — against a catalog-capable registry, `knock audit --signed --sbom`
reports the same fleet as `uncovered / stamped / signed / has-SBOM`.

Seven green example runs are not that count, and this page will not present them as one.
