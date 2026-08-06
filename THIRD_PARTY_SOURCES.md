# Third-party source inventory

The local `sources/` directory was extracted from `crossover-sources-26.3.0.tar.gz` and is excluded from this Git repository. It contains Wine 11.0 plus component source trees including DXVK, MoltenVK, vkd3d, GStreamer, GnuTLS, GLib, FreeType, Ghostscript, BusyBox, and cabextract.

The packaged runtime uses the Wine source tree from that archive. Each component retains its upstream license files inside its source directory. Before broad distribution, Secunda must ship the required Wine license text, notices, and corresponding source or source offer.

The DirectX 11 graphics bridge is DXMT v0.80, downloaded from the [official release](https://github.com/3Shain/dxmt/releases/tag/v0.80). The build verifies the developer-published SHA-256 before staging it. Version 0.80 is distributed under the MIT license included at `licenses/DXMT-v0.80-LICENSE.txt`; matching source is available at the tagged repository release.

Secunda does not bundle proprietary CrossOver application code, D3DMetal, Steam, or Skyrim binaries. Steam downloads itself from Valve, and players install their separately owned game through Steam.
