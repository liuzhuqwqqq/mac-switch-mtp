# Third-party components

The app dynamically links these libraries rebuilt from pinned upstream sources
with the same macOS deployment target as the application (13.0 by default).
Only their Mach-O library install paths and local ad-hoc signatures are changed
for loading them from the application bundle. No third-party library source code
has been changed. The helper and its build source are supplied in this project.

## libmtp 1.1.23

- Project and corresponding source: https://github.com/libmtp/libmtp/tree/v1.1.23
- Source archives: https://sourceforge.net/projects/libmtp/files/libmtp/1.1.23/
- Copyright: the libmtp contributors, as identified in the upstream source files.
- License: GNU Lesser General Public License v2.1 or later. The complete license
  is included at `vendor/licenses/libmtp-LICENSE.txt` and in the app Resources.
- Bundled file: `Contents/Frameworks/libmtp.9.dylib`.

## libusb 1.0.30

- Project and corresponding source: https://github.com/libusb/libusb/tree/v1.0.30
- Source release: https://github.com/libusb/libusb/releases/tag/v1.0.30
- Copyright: the libusb contributors, as identified in the upstream source files.
- License: GNU Lesser General Public License v2.1 or later. The complete license
  is included at `vendor/licenses/libusb-LICENSE.txt` and in the app Resources.
- Bundled file: `Contents/Frameworks/libusb-1.0.0.dylib`.

You may replace the dynamically linked libraries with compatible builds. The app
does not enable hardened-runtime library validation. After replacing a library,
use local ad-hoc code signing if required by macOS. Nothing here restricts reverse
engineering for debugging modifications to these LGPL libraries. If distributing
the app onward, also comply with the libraries' corresponding-source requirements.

Each binary release is accompanied by a `ThirdParty-Sources.zip` asset containing
the exact upstream source archives, SHA-256 checksums, build scripts and
licenses. No additional source patches are applied to these versions.
Use `vendor/build-libraries.sh` to rebuild the libraries;
`build.sh` records the dynamic-library path edits and signing steps used to bundle
them. The MIT license for this project does not replace these LGPL licenses.
