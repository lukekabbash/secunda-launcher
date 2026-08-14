# Runtime build and provenance plan

## Goal

Make one canonical machine-readable runtime specification the authority for source inputs, patches, configuration, payload contents, provenance, SBOM, and runtime capability identity.

The runtime build is separate from app-only iteration. A launcher/UI change does not rebuild, relocate, or resign every runtime component.

## Current provenance gap

At inspection time:

- `scripts/build-runtime.sh` applies ten patches.
- `packaging/runtime-provenance.json` records nine applied patches.
- `wine-secunda-compat-knobs.patch` is applied by the script but absent from provenance.
- The current `wine-secunda-rosetta-debug-registers.patch` SHA-256 differs from the value in provenance.

Conclusion: current repository provenance is stale relative to the inspected source/build recipe. No claim is made about the contents of a separately built or packaged runtime because this audit did not execute verification.

## Canonical runtime specification

Add one versioned source of truth, for example:

```text
packaging/runtime-spec.json
```

Suggested conceptual schema:

```json
{
  "schemaVersion": 1,
  "runtimeName": "secunda-player-runtime",
  "minimumMacOS": "15.0",
  "architectures": ["arm64", "x86_64"],
  "sources": [],
  "dependencies": [],
  "patches": [],
  "toolchain": {},
  "configure": {},
  "compilerFlags": {},
  "payloadProjection": {},
  "capabilities": [],
  "notices": []
}
```

Required source entry fields:

- component identity;
- version/revision;
- canonical archive URL/source reference;
- SHA-256;
- license identity;
- source-closure location.

Required patch entry fields:

- ordered path;
- SHA-256;
- component target;
- declared capability/fix identity;
- exact executable/process gate where relevant;
- required/optional status.

Required dependency entry fields:

- name and version;
- source/hash;
- architecture/deployment target;
- build flags;
- output manifest.

Required payload projection fields:

- allowlisted paths/globs with constrained semantics;
- file/link/directory type;
- expected mode where material;
- capability association;
- SDK-only/player status;
- required notice/license.

## Generated artifacts

The canonical spec generates rather than manually duplicates:

- runtime build inputs;
- ordered patch application list;
- `runtime-provenance.json`;
- runtime SBOM;
- source-closure manifest;
- license/notice staging list;
- player payload allowlist;
- runtime capability manifest;
- final content manifest;
- content-derived `RuntimeID`.

Generated outputs include the spec schema and digest that created them.

## Runtime identity

`RuntimeID` includes canonical digests of:

- runtime spec;
- source archives/revisions;
- ordered patches;
- dependency artifacts;
- toolchain identity;
- deployment/architecture/configuration flags;
- final player payload manifest.

It is not only a marketing version string or directory name.

The launcher records the runtime ID in session fingerprints, outcome records, and capability receipts.

## Clean reproducible build flow

```text
validate spec
  -> fetch/locate exact archives
  -> verify source hashes
  -> fresh verified extraction
  -> apply ordered patches once
  -> build exact dependencies
  -> build runtime
  -> stage complete RuntimeSDK
  -> project allowlisted PlayerRuntime
  -> generate provenance/SBOM/notices/manifests
  -> verify payload and capability contracts
  -> sign/notarize release artifact when authorized
```

Do not treat "patch already applied" in a reused source tree as a successful canonical build. Canonical release builds begin from a fresh verified extraction.

Developer source overrides:

- are explicit;
- record path-independent source identity where possible;
- mark output noncanonical;
- mark output unpublishable;
- cannot reuse release provenance labels.

## Runtime SDK versus player runtime

Current `Runtime/wine` is approximately 564 MB and includes about:

- 62.4 MB headers;
- 22.7 MB static/import/development libraries;
- 1.8 MB developer-oriented tools.

This makes approximately 86.9 MB a candidate SDK/player separation, subject to exact dependency and package acceptance.

### `RuntimeSDK`

Contains complete build/development materials:

- headers;
- static/import libraries;
- build helper programs;
- development metadata;
- complete source/provenance closure.

### `PlayerRuntime`

Contains only verified runtime requirements:

- `wine` and `wineserver`;
- `wineboot`;
- `reg` and `tasklist`;
- `expand` and other explicitly used runtime tools;
- all required 32-bit and 64-bit workers/loaders;
- DXMT, DXVK, MoltenVK, WineD3D components;
- audio/controller support;
- managed runtime helpers;
- runtime capability manifest;
- notices, provenance, SBOM, and source obligations.

Do not remove 32-bit payloads or infer safety from file names alone. The player projection becomes accepted only after package verification and the complete supported-game matrix.

## Sealed runtime reuse

After PlayerRuntime verification:

- stage it under its content-derived runtime ID;
- treat it as immutable;
- reuse it for app-only packaging;
- avoid rebuilding or mutating it for UI/source changes;
- avoid repeatedly relocating or ad-hoc resigning individual Mach-O files when an accepted sealed artifact is available;
- still sign the final outer application as required.

Any mutation creates a new runtime ID and invalidates receipts.

## App resource packaging

Current package logic copies the launcher binary but does not generally copy SwiftPM resource bundles.

Initial architecture therefore keeps game profiles in compiled Swift.

If resources are later introduced:

- declare them in Package.swift;
- copy every emitted resource bundle into the app;
- verify presence, digest, and code-signature coverage;
- include resources in package provenance;
- make missing/unknown schema a boot failure;
- ensure the app resolves resources from its bundle, not the source checkout.

Do not introduce resource-backed profiles without first extending packaging and distribution verification.

## Version/hash duplication cleanup

Component versions and hashes currently appear across fetch/build/provenance scripts. The runtime spec should be the only hand-authored authority.

Scripts consume generated normalized values. Verification compares:

- spec to fetched archive;
- spec to built dependency receipts;
- spec to applied patch records;
- spec to final runtime provenance;
- final provenance to packaged embedded provenance.

No verifier should merely validate entries that happen to be listed while failing to detect a build-script input omitted from provenance.

## Provenance verification contracts

Verify:

- every build-script patch exists in the spec;
- every spec patch is applied in the declared order;
- every patch digest matches;
- no extra patch is applied;
- source and dependency digests match;
- configuration/deployment/architecture flags match;
- payload path, type, link target, mode, and digest match the manifest;
- required notices and source closure are present;
- capability manifest is consistent with payload contents;
- packaged provenance exactly matches the staged runtime's provenance;
- runtime ID recomputes successfully.

Verification failure blocks publish/release labeling.

## Self-check and test targets

The current broad self-check suite is compiled into the release executable through `--self-test` dispatch.

Target split:

- `SecundaDomainTests`: catalog, IDs, plans, settings migrations, state manifests.
- `SecundaGameSupportTests`: per-game contract/fingerprint fixtures.
- `SecundaRuntimeTests`: parsers, editors, containment, process lifecycle with fakes.
- `SecundaApplicationTests`: coordinator state/reentrancy/cancellation with fake ports.
- `SecundaPackageTests` or distribution scripts: packaged payload/provenance/capability checks.

Keep `PackagedHealthCheck` small:

- catalog constructs;
- bundled runtime/provenance readable;
- required player capabilities present;
- critical cleanup/containment contracts represented;
- no fixture-heavy full suite.

## Verification tiers

### Tier 1: fast pure checks

- domain/catalog/profile tests;
- pure editors;
- settings/state migrations;
- source-boundary checks;
- no runtime required.

### Tier 2: fake/temp-filesystem integration

- Steam manifests;
- containment/symlink behavior;
- settings atomicity;
- coordinator races;
- process lifecycle fakes;
- compatibility-plan compilation.

### Tier 3: runtime source/build checks

- spec validation;
- clean patch application;
- dependency/runtime build;
- runtime manifest/capabilities;
- source closure and SBOM.

### Tier 4: package checks

- player projection;
- resources;
- Mach-O/link/signature/provenance;
- packaged health check;
- source-only/release artifact labeling.

### Tier 5: live release acceptance

- user-owned Steam authentication;
- cold/warm session matrix;
- exact window, render, audio, input, gameplay evidence;
- cross-game contamination matrix;
- Developer ID/notarization and quarantined clean-Mac acceptance when releasing.

A lower tier never promotes a higher-tier acceptance claim.

## Build and package performance contracts

- Incremental launcher build does not rebuild Wine or dependencies.
- App-only packaging reuses one accepted sealed runtime artifact.
- The same immutable runtime is not fully hashed multiple times in one pipeline without reason.
- Any APFS clone/content-addressed staging optimization reproduces the exact verified package.
- Clean-build and package timing are recorded separately.
- Performance optimizations never reduce audit strength.

## Release gate

A runtime may be called canonical/release-ready only when:

- the spec is valid;
- all source/dependency/patch inputs match;
- clean build completed;
- player payload matches its manifest;
- capability manifest matches actual contents;
- provenance/SBOM/source closure are complete;
- app resources and embedded provenance match;
- required signing/notarization state is truthful;
- the supported-game acceptance matrix for that runtime ID is recorded.

