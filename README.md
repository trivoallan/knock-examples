# knock-examples

Live proof of [knock](https://github.com/trivoallan/knock)'s provenance stamp: a scheduled workflow
runs the **real** example policies — checked out of the knock repository at a pinned tag, never
copied here — and publishes stamped, SBOM-carrying, signed images to GHCR.

The verification commands land here once the showcase publishes. They are generated from
`verify.sh`, which also runs as the workflow's final step, so this page cannot promise something the
showcase does not do.
