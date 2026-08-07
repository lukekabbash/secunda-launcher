SECUNDA SOURCE RUNTIME — CORRESPONDING SOURCE

This folder accompanies the binary compatibility runtime inside Secunda.

crossover-sources-26.3.0.tar.gz
SHA-256: ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872

The archive contains the Wine 11.0, FreeType 2.13.3, GMP 6.3.0, and GnuTLS
3.8.3 source trees used by this build. The exact official Nettle 3.10 source
archive is included at build/source-cache/nettle-3.10.tar.gz.

The mounted disk image is read-only. Copy this entire Sources folder to a
writable folder before rebuilding. Install Xcode Command Line Tools plus CMake,
Ninja, LLVM, LLD, and Bison. From the writable copy, run:

scripts/build-runtime-from-archive.sh

That command verifies and freshly extracts crossover-sources-26.3.0.tar.gz,
builds in an isolated temporary directory, applies the Wine patches enumerated
in packaging/runtime-provenance.json, validates every runtime binary, and only
then publishes Runtime/wine-macos15. It refuses to merge into an existing
runtime.

DXMT 0.80 is distributed under the MIT license. Its matching source is:
https://github.com/3Shain/dxmt/tree/v0.80

The Secunda launcher, Steam, Skyrim, user prefixes, credentials, saves, and
proprietary compatibility-engine files are not part of this source bundle.
