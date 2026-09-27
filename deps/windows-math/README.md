# Windows GMP / MPFR dependency builds

This is a standalone, manually dispatched dependency workflow, not an official
Prusa binary distribution or a slicer release workflow. It builds matching
GMP 6.2.1 and MPFR 4.2.1 DLLs, MSVC import libraries, and headers on native
Windows ARM64 and x64 runners. Existing committed Windows binaries and all
application/dependency consumption paths are unchanged.

## Running

After the workflow is available on the repository's default branch, select
**Windows GMP and MPFR** in Actions, choose the reviewed branch, and dispatch.
Alternatively:

```powershell
gh workflow run build_windows_math.yml --repo YOUR-OWNER/PrusaSlicer --ref YOUR-BRANCH
```

Only `workflow_dispatch` is enabled; there is no pull-request execution,
release publishing, write token, cache of binaries, or application build.
Both architecture jobs must succeed before adopting a package. Successful jobs
upload packages for 30 days; separate diagnostic artifacts retain configure,
build, upstream test, PE inspection, and native ABI logs for 14 days. Download
and preserve both the package and its matching source before artifacts expire.

For a local build, use native PowerShell 7 on the target OS with Visual Studio
C++ tools for the native host/target, Windows SDK, `vswhere`, Git, and Windows
`tar` available:

```powershell
.\deps\windows-math\build.ps1 -Architecture arm64 -WorkRoot C:\math-build-arm64
```

Commit reviewed recipe changes before building; a dirty recipe is rejected so
the recorded commit identifies the packaged scripts. The work directory must
be new and have no spaces. Downloads and unpacked
tools are confined to that directory. There is no global package installation.
Do not reuse a partial or old build directory.

## Build and ABI choices

The versions match this repository's existing non-MSVC source recipes. They
do **not** match the old shipped Windows GMP 5.0.1 / MPFR 3.0.0 headers.
MPFR 4.2.1 produces **libmpfr-6.dll**, not the shipped libmpfr-4.dll. Never rename
it to the old ABI name or combine these DLLs with old headers/import libraries.

`inputs.json` pins source and tool archive URLs and SHA256 checksums.
The build uses LLVM-MinGW 20260922 (Clang plus MinGW-w64, UCRT), with
architecture-native compiler binaries. This is not an assumption that upstream
GMP/MPFR compile unchanged with clang-cl: their upstream Autoconf Windows
MinGW support is used with a GNU-style Clang driver. GMP's Windows LLP64 branch
selects `long long` limbs for the 64-bit ABI. Assembly is disabled for an
explicit portable-C baseline on both architectures; no performance equivalence
to optimized shipped binaries is claimed. C++ `gmpxx` is intentionally excluded.
The C ABI, not the MinGW C++ ABI, is the integration boundary.

Prior art reviewed: [GMP's Windows DLL/import-library documentation](https://gmplib.org/manual/Notes-for-Particular-Systems),
the [vcpkg GMP](https://github.com/microsoft/vcpkg/tree/856e200a1264bf2fcbe7a19b0dcd0ed7aa1cf1bd/ports/gmp)
and [MPFR](https://github.com/microsoft/vcpkg/tree/856e200a1264bf2fcbe7a19b0dcd0ed7aa1cf1bd/ports/mpfr)
recipes, and [LLVM-MinGW's runtime interoperability notes](https://github.com/mstorsjo/llvm-mingw/blob/0eca5ac93da14a74bc81c249e841356ececc5d95/README.md).
Those vcpkg recipes remove upstream test traversal; this workflow keeps it.
No contributor-produced GMP or MPFR binary is an input.

On x64, `-mlong-double-64` explicitly matches MSVC's 64-bit `long double`,
including MPFR's `mpfr_set_ld`/`mpfr_get_ld` interface. ARM64 already uses that
layout. Both compilers exercise those calls. This is a dedicated MSVC-consumer
build, not a drop-in package for arbitrary MinGW consumers with other flags.
`__USE_MINGW_ANSI_STDIO=0` selects UCRT formatted I/O instead of MinGW's
extended-precision printf wrappers. This matters for variadic long-double
arguments on x64; the upstream formatting suites remain enabled as gates.

The pinned MSYS2 bootstrap, make, m4, and diffutils are **build tools only**. On ARM64
Windows their x64 processes run under emulation. The library compiler, produced
DLLs, LLVM-built smoke executable, MSVC compiler, and MSVC-built smoke executable
are all required to have the target PE machine type; the smoke also checks
`IsWow64Process2` to reject emulated execution. Configure is told the native
build and host triplet so upstream test executables are run, not silently
treated as cross-compiled.

The workflow runs `make check` for both libraries and fails on errors. Their
logs preserve upstream-reported skips/unsupported features; a successful exit
does not mean every optional upstream test exists on Windows. The original
`smoke.cpp` checks integer, rational, high-precision MPFR arithmetic, version
data imports, allocation/free APIs, and the exact structure/type layouts seen
by both compilers, plus MPFR thread-local precision isolation. MSVC `lib.exe`
constructs genuine COFF import libraries from
actual DLL exports, classifying DATA exports from PE sections. Dependency
inspection rejects unexpected DLLs (including MSYS, libgcc, and C++ runtimes).

Both DLLs use the UCRT. The MSVC consumer uses `/MD`. Memory returned by GMP
must be released through the allocator returned by `mp_get_memory_functions`,
and MPFR strings through `mpfr_free_str`; do not free them across arbitrary CRT
or custom-allocator boundaries. This gate is not a guarantee for every CRT
setting, varargs/stdio boundary, consumer compiler, or full CGAL/slicer workload.

GitHub runner images and their MSVC/SDK servicing versions can change. Runner
labels are explicit (`windows-11-arm`, `windows-2025`), and exact compiler,
runner, source, and recipe identities are recorded in `provenance.json`.
The procedure is repeatable; **bit-for-bit reproducibility is not established**.

## Package layout

Each artifact name includes GMP/MPFR versions, target architecture, LLVM
version, MSVC toolset, pinned-input hash, and recipe commit. It contains a binary/source ZIP
and a SHA256 manifest for the ZIP. Inside the ZIP:

```text
bin/                 libgmp-10.dll, libmpfr-6.dll
lib/                 corresponding .lib and export .def files
include/             generated gmp.h, mpfr.h, mpf2mpfr.h
source/              complete verified upstream source archives
source/recipe/       build scripts, input lock, original smoke, this document,
                     and the workflow
licenses/            upstream library and toolchain notices, recipe license
provenance.json      exact inputs, compiler/runner identity, native ABI result
SHA256SUMS           hashes of all other packaged files
```

`patches/libtool-response-files.patch` adapts the
[MSYS2/LLVM-MinGW response-file fix](https://github.com/msys2/MINGW-packages/blob/95b093e888/mingw-w64-libtool/0012-Prefer-response-files-over-linker-scripts-for-mingw-.patch)
to the bundled generated `configure`/`ltmain.sh` files. It selects `@file`
instead of GNU linker scripts, which LLD's PE linker cannot read. It changes
build machinery only, not arithmetic or public headers. The original complete
source archives plus the applied patch are shipped. Patches are checked against
the pinned source context, recorded with SHA256 hashes in provenance, and never
downloaded dynamically. No Autoconf regeneration or unpinned package update is
needed.

## Adoption and licensing

Prusa can review and run this workflow in its own repository under its own
control without trusting contributed precompiled DLLs. Adoption into the
slicer is deliberately a separate change: `deps/+GMP/GMP.cmake` and
`deps/+MPFR/MPFR.cmake` currently copy `win${DEPS_BITS}` files, while
`cmake/modules/Utils.cmake` separately copies runtime DLLs directly from the
source tree. Pointer width alone cannot select ARM64 versus x64. Any opt-in
integration must update both paths together, keep the new headers and libraries
paired, explicitly select the architecture, and account for MPFR's new DLL
name. Do not overwrite the current x64 defaults to consume these packages.

GMP 6.2.1 library sources offer LGPL-3.0-or-later OR GPL-2.0-or-later;
MPFR 4.2.1 uses LGPL-3.0-or-later. Their test/demo components can have different
terms (including GPL); upstream tests are executed, not copied into our smoke
test. The standalone helper follows the repository's AGPL-3.0-or-later
convention and does not relicense library code. LLVM includes Apache-2.0 with
LLVM exceptions, and MinGW-w64/runtime components have their own notices.
The package includes the toolchain's supplied notices for review.

Build tools themselves are not redistributed in the payload. No Microsoft
runtime redistributable is bundled. The UCRT is supplied by supported Windows;
the build machine needs Visual Studio. Downstream redistribution must preserve
applicable notices, source and modification availability, and relinking rights.
Review the exact included licenses and runtime obligations before shipping;
this workflow is not legal certification.
