# iOS SPIRV-Cross Dependency Lane

This lane supplies SPIRV-Cross to the experimental native Metal renderer. It
does not alter or automatically link the existing RPCS3 renderer.

## Pinned provenance

- MoltenVK release: `v1.4.2`
- MoltenVK tag commit: `db66022459ffb663aa2b50f6b018bc2e124f5edf`
- MoltenVK revision source: `ExternalRevisions/SPIRV-Cross_repo_revision`
- SPIRV-Cross revision: `6c09849fe88c48eaed08413aa022aaa136a3a057`
- Archive URL: `https://codeload.github.com/KhronosGroup/SPIRV-Cross/tar.gz/6c09849fe88c48eaed08413aa022aaa136a3a057`
- Archive SHA-256: `b81b9956289950570953738e666a031ca32ff64e4fc925eba89f227c42109518`
- MoltenVK converter header: `MoltenVKShaderConverter/SPIRVToMSLConverter.h`
- Converter header SHA-256: `124e571b7327c76ca0e340fc786deb53f114361dee3a1ae6d98c3d657a2878dc`
- Upstream license: Apache-2.0

The fetcher downloads and extracts only into the ignored repository-level
`.deps` directory by default. `ARMSX3_DEPS_ROOT` may point at a different
out-of-source `.deps` cache.

## Fetch and configure

```sh
platforms/ios/scripts/fetch-spirv-cross.sh
```

Include the helper from the main iOS CMake path, then opt in explicitly:

```cmake
include("${CMAKE_SOURCE_DIR}/rpcs3/ios/ARMSX3IOSSPIRVCross.cmake")
armsx3_ios_add_spirv_cross()

target_link_libraries(native_metal_renderer PRIVATE
    ${ARMSX3_IOS_SPIRV_CROSS_MSL_TARGET})
```

The helper requires `CMAKE_SYSTEM_NAME=iOS`, deployment target 15.0 or newer,
and `CMAKE_OSX_ARCHITECTURES=arm64`. It mirrors MoltenVK's bounded SPIRV-Cross
feature set and exposes `MVK_spirv_cross` as the C++ namespace.

The production iOS core does not link a second SPIRV-Cross copy. Its private
bridge calls the converter already exported by the exact MoltenVK `v1.4.2`
binary and compiles against the hash-pinned matching converter header. A
version, namespace, header, or symbol mismatch must fail configuration or link
rather than falling back to a different translator.

## Attribution and distribution gate

The verified archive retains its complete `LICENSE`. The helper exports its
path as `ARMSX3_IOS_SPIRV_CROSS_LICENSE_FILE`; any distribution using the
dependency must preserve that notice in its third-party attribution bundle.

The repository identifies most RPCS3 files as GPL-2.0-only, while SPIRV-Cross
uses Apache-2.0. This lane does not claim that directly linking and distributing
those components is already license-compatible. Resolve that boundary through
project approval, a suitable exception, or a separate build-time tool process
before shipping a combined binary.

## Lightweight verification

```sh
platforms/ios/scripts/test-spirv-cross-dependency.sh
```

The test rejects a deliberately corrupted archive, fetches and verifies the
pinned archive in a disposable `.deps`, validates provenance and attribution,
configures the iOS 15 arm64 targets, and compiles the ARMSX3 shader metadata and
SPIR-V-to-MSL translator against the pinned MSL library with one worker and
warnings treated as errors. It does not select the renderer or run the full
application build.
