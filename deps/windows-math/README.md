# Windows GMP / MPFR dependency builds

This is a standalone, manually dispatched dependency workflow, not an official
Prusa binary distribution or a slicer release workflow. It builds matching
GMP 6.2.1 and MPFR 4.2.1 DLLs, MSVC import libraries, and headers on native
Windows ARM64 and x64 runners. Existing committed Windows binaries and all
application/dependency consumption paths are unchanged.

## Qualification status: passed on both native architectures

The [native qualification run](https://github.com/crutkas/PrusaSlicer/actions/runs/36378098643)
at recipe commit `4eff56c10d5eea198bdc72bed7f6c5dbf1b6faff` passed every dependency, native consumer and
packaging gate on both architectures and uploaded verified binary/source
packages. ARM64 used the explicit `windows-11-vs2026-arm` image
`20260920.164.1`; x64 used `windows-2025` image `20260922.246.2`.
Both selected VS `18.10.12210.168` and MSVC `14.51.36231`.
The completed jobs have no check annotations, and complete logs have no
build/compiler or Node deprecation warnings.

Download the matched binary/source packages:
[ARM64](https://github.com/crutkas/PrusaSlicer/actions/runs/36378098643/artifacts/10952626981)
and [x64](https://github.com/crutkas/PrusaSlicer/actions/runs/36378098643/artifacts/10952088465).
Both downloaded ZIP hashes, all 58 manifest entries, original source archive
checksums and applied-patch provenance were independently checked after upload.
Packages are retained for 30 days; preserve them and their source together.
The qualification identifies the exact recipe commit above; subsequent
documentation-only updates do not change the tested scripts or workflow.

| Gate | x64 | ARM64 |
| --- | --- | --- |
| GMP upstream tests | 175 passed, no skips | 175 passed, no skips |
| MPFR upstream tests | 196 passed, 2 skipped | 195 passed, 3 skipped |
| MSVC import generation and DLL audit | Passed | Passed |
| MSVC consumer arithmetic/ABI/TLS | Passed | Passed |
| LLVM consumer / cross-compiler ABI comparison | Passed | Passed |
| Clean unpacked ZIP consumer | Passed | Passed |
| Full PrusaSlicer integration | Not attempted | Not attempted |

The previous failure was `tsprintf.exe`, which hit GMP's
`printf/repl-vsnprintf.c:389` assertion `len < total_width`. GMP's configure log
shows its `vsnprintf` conformance probe failing on `"%nhello world"` under the
selected UCRT formatted-I/O configuration, selecting the replacement routine.
The failing assertion was a correctness blocker, not an expected test skip.
The `%n`/CRT behavior legitimately selects GMP's replacement routine. That
routine omitted hexadecimal floating conversions (`%a`/`%A`) from its output
size calculation and argument traversal before calling `vsprintf`.
The recipe now patches those omissions and adds printf-family regression
coverage; `tsprintf.exe` passed on both architectures. The assertion
has not been disabled and no configure result has been forced.

The header fix makes GMP's documented low-`unsigned long` extraction
explicit and expresses limb negation as unsigned subtraction rather than
unary minus. This addresses MSVC C4244/C4146 without lowering `/W4 /WX`;
the consumer smoke checks both operations. Those checks now pass. The smoke
now explicitly targets Windows 10 or newer for `IsWow64Process2` in both SDKs,
without falling back to an architecture check that allows emulation.
These checks passed in the final qualification run.

Upstream skips were decimal64/decimal128 tests on both targets, plus float128
on ARM64. Complete logs are available as
[x64 diagnostics](https://github.com/crutkas/PrusaSlicer/actions/runs/36378098643/artifacts/10951799755)
and [ARM64 diagnostics](https://github.com/crutkas/PrusaSlicer/actions/runs/36378098643/artifacts/10953171044)
(14-day retention). These results are the last completed dependency
qualification; further fixes must pass the entire workflow before adoption.

## Actions runtime checks are not library qualification

The original checkout and diagnostic-upload Actions declared Node 20. In the
earlier run `36331885720`, GitHub forced them onto Node 24 and logged a Node 20
deprecation warning; the upload also logged `DEP0040` (`punycode`) and `DEP0169`
(`url.parse()`). Checkout, diagnostic upload, and checkout post-cleanup all
completed successfully. These warnings were separate from the fatal MPFR test
failure.

Both Actions are now pinned to v7.0.1 commits that explicitly declare Node 24.
`check_windows_math_actions.yml` exercises checkout, both upload patterns, and
checkout cleanup on the same Windows runner matrix, without building libraries.
Its artifacts are explicitly labeled runtime fixtures, not dependency packages.
A green **Actions runtime only** run is not dependency qualification;
all library, MSVC-consumer, and package gates must also pass.

[Runtime-only run 36348481031](https://github.com/crutkas/PrusaSlicer/actions/runs/36348481031)
passed checkout, both actual fixture uploads, upload ID/SHA256 validation, and
post-checkout cleanup on ARM64 and x64. Its complete logs contain no Actions
warning/error annotations or Node deprecation warnings. The ARM64 runner emits
an informational notice about its Visual Studio 2026 image migration in that
historical run. The final dependency run uses the explicit VS 2026 ARM image
and has no migration annotation. The runtime-only run produced fixtures only,
not qualified libraries.

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
The provided `target-gcc` alias invokes the pinned Clang. `CXX=no` is explicit:
GMP 6.2.1 skips GNU C++ detection with `--disable-cxx`, but a supplied `CXX`
would still initialize Libtool's C++ tag with an unset `GXX` and overwrite the
C library's shared filename/install settings. No C++ library is built.

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
does not mean every optional upstream test exists on Windows. Clang does not
provide `_Decimal64`/`_Decimal128` on either target, so upstream's decimal tests
return 77; ARM64 also lacks the `__float128` fallback detected on x64, so its
`tset_float128` test returns 77. These are configure-detected unavailable
extensions, not disabled arithmetic tests. Libtool's supported
`-no-fast-install` test link mode is selected explicitly instead of requesting
the unsupported Windows `-no-install` mode and relying on its warning/fallback.
The original
`smoke.cpp` checks integer, rational, high-precision MPFR arithmetic, version
data imports, allocation/free APIs, and the exact structure/type layouts seen
by both compilers, plus MPFR thread-local precision isolation. MSVC `lib.exe`
constructs genuine COFF import libraries from
actual DLL exports, classifying DATA exports from PE sections. Dependency
inspection rejects unexpected DLLs (including MSYS, libgcc, and C++ runtimes).
After packaging, the ZIP is extracted into a fresh directory, every manifest
entry and the file count are checked, and the packaged smoke source is compiled
again with MSVC against the extracted headers and import libraries. That fresh
process runs with only the package and Windows system directories on `PATH`;
the smoke verifies both loaded DLLs are beside its executable. Build-tree DLLs
cannot satisfy this gate. Its output is retained in `unpacked-native-abi.txt`.

Both DLLs use the UCRT. The MSVC consumer uses `/MD`. Memory returned by GMP
must be released through the allocator returned by `mp_get_memory_functions`,
and MPFR strings through `mpfr_free_str`; do not free them across arbitrary CRT
or custom-allocator boundaries. This gate is not a guarantee for every CRT
setting, varargs/stdio boundary, consumer compiler, or full CGAL/slicer workload.

GitHub runner images and their MSVC/SDK servicing versions can change. Runner
labels are explicit (`windows-11-vs2026-arm`, `windows-2025`), and exact compiler,
runner, source, and recipe identities are recorded in `provenance.json`.
The ARM label deliberately adopts the supported VS 2026 image described in
[the migration announcement](https://github.com/actions/runner-images/issues/14602),
rather than waiting for `windows-11-arm` to change underneath a run. On that
label, `vswhere` is constrained to VS 18.x and the selected installation
version, native compiler, toolset and image version are recorded. The x64
label and selection remain unchanged. A runner label is not an immutable
toolchain pin; hosted image servicing still requires requalification.
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

`patches/windows-warning-cleanup.patch` fixes diagnostics rather than adding
warning-suppression flags: Clang DLL consumers use local GMP inline definitions
instead of incompatible `dllimport` plus GNU external-inline definitions;
non-inline functions and data remain imports. LLP64 test diagnostics use GMP's
limb-sized format and construct a full maximum limb without truncating it
through `unsigned long`. Compile-time width guards retain small-limb/nail
branches only when their conditions can be true, and retain the existing
LP64-only MPFR test vector only when `unsigned long` can represent it.
Parentheses, explicit discarded carry results (only where assertions were
already disabled), and a widened formatting-bound comparison preserve the
original arithmetic checks. No compiler warning category is disabled.
The workflow rejects remaining compiler/build warnings before packaging.

`patches/gmp-replacement-vsnprintf-hex.patch` repairs hexadecimal floating
formatting in GMP's replacement `vsnprintf`: it accounts for the conversion's
maximum size and consumes the correct `double`/`long double` argument.
The UCRT policy disabling direct CRT `%n` remains unchanged; GMP handles its
own `%n` conversion. Regression coverage exercises mixed arguments, precision,
truncation, long-double extremes, and GMP-managed `%n`, without bypassing the
configure probe, removing assertions, or excluding upstream tests.

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
