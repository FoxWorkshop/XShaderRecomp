# XShaderRecomp


XShaderRecomp is a helper library that extract, decode and convert Xbox shader binaries to modern HLSL. 
The resulting files can be recompiled to DXIL and SPIR-V using the DirectX Shader Compiler (DXC) for use in Direct3D 12 and Vulkan either automatically or manually through `XShaderRecompTool`.
The program is heavy based on CXBX's shader implementation.

> [!CAUTION]
This project is mean to be used at runtime paired to your recompiled Xbox game.
Why not analysing XBE file and extracting the shaders to HLSL statically? Because some games build most of their shaders dynamically, aka at runtime,
which make a static extraction impossible. So I decided to focus on dynamic extraction and recompilation.

While the library handles dynamic recompilation, it is recommended to use `XShaderRecompTool` that come with this project to convert all the hlsl files so you can have static shaders.
This allows you to cache shaders and integrate them directly into your executable for maximum performance.

> [!IMPORTANT]
> The current implementation uses custom templates which are designed around [Shadow Recompiled](https://github.com/FoxWorkshop/ShadowRecomp), a recompilation project that implements a translation layer for the renderer rather than emulating the Xbox GPU. Shadow Recompiled specific implementations are placed under the `SHADOW_RECOMP` preprocessor macro.
> Users are expected to modify the recompiler to fit their needs. Do not expect the recompiler to work out of the box.

## Implementation Details

Several components of the recompiler are currently incomplete or missing. Unimplemented or inaccurate features exist mainly because they were either unnecessary for Shadow Recompiled or did not cause visible issues.

### Shader Container

Xbox shaders are stored in the XBE file directly, as mentioned before, some games build shaders dynamically at runtime, so this library needs to be integrated into your recompiled game to extract and build shaders in real time.

### Instructions (todo)


### Constants

Both vertex and pixel shader stages use three constant buffers:

* Vertex shader constants: 4096 bytes (256 `float4` registers)
* Pixel shader constants: 3584 bytes (224 `float4` registers)
* Shared constants: Used specifically by Shadow Recompiled

Vertex and pixel shader constants are copied directly from the guest render device, and shaders expect them in little-endian format.

Constant buffer registers are populated using reflection data embedded in the shader binaries. If this data is missing, the recompiler will not function. However, support can be added by defining a `float4` array that covers the entire register range.

Integer constants are unimplemented. If the target game requires them, you will need to make new constant buffer slots or append them to the existing ones.

All constant buffers are implemented as root constant buffers in D3D12, making them easy to upload to the GPU using a linear allocator. In Vulkan, the GPU virtual addresses of constant buffers are passed as push constants. Constants are accessed via preprocessor macros that load values from the GPU virtual addresses using `vk::RawBufferLoad`. These macros ensure the shader function body remains the same for both DXIL and SPIR-V.

Out-of-bounds dynamic constant accesses should return 0. However, since root constant buffers in D3D12 and raw buffer loads in Vulkan do not enforce this behavior, the shader developer must handle it. To solve this, each dynamic index access is clamped to the valid range, and out-of-bounds registers are forced to become 0.

### Vertex Declaration

While Xbox can specify data types (`D3DVSDT_FLOAT3`, `D3DVSDT_SHORT2`, etc.), **there is no reliable way** to detect the real usage, aka `POSITION`, `NORMAL` etc. **Xbox has no concept of `usage types`**, it only requires a list of attribute register numbers.

The recompiler resolves this by treating all of them as `TEXCOORD` semantics since this can be used for any user-defined data with an Index of the Vertex Register, this prevents information loss due to non-matching dlc types.

### Templates

The recompiler originally treats all vertex as `float4` in the generated `VS_INPUT` structure. While this works for most attributes, it can break in cases where the original shader expects integer input data, such as bone indices used for skinning.
Modern graphics APIs require strict agreement between vertex buffer formats and shader input types, mismatches can lead to undefined behavior or incorrect data interpretation.

To address this, the recompiler has a custom template system that allows for game-specific shader variations. This system allows developers to define different versions of shaders based on the expected vertex declaration and other factors, ensuring compatibility with modern API.
This is the whole reason the recompiler is not as generic as I initially intended, but this was necessary to ensure correct shader behavior.


### Textures & Samplers

Textures and samplers use a bindless approach. Descriptor indices are stored in the shared constant buffer, with separate indices for each texture type to prevent mismatches in the shader. 1D textures are unimplemented but could be added easily.

## Usage

Once you have the library linked to your recompiled game, you can call the function `CreateShader` from the API when the game expects to use a shader. 
The library will then handle the process of decoding, extracting and converting to HLSL before eventually dynamically build the shader.
The function takes an output pointer which will store the recompiled shader in. Your recompiled game can then load the shader dynamically.

Additionally, you can specify to extract the HLSL files, they are located in the XShaderRecomp project directory, this will allow you to have static shader to cache them, see below for more information.


### Shader Cache (optional but recommended)

Once you have your HLSL files extracted, you can use XShaderRecompTool which can process an entire directory by scanning for HLSL files within the specified path. 
In this mode, valid shaders are converted and recompiled into a DXIL/SPIR-V cache, formatted for use with Shadow Recompiled. This cache is then exported as a .cpp file for direct embedding into the executable:

```
XShaderRecompTool [input directory path] [output .cpp file path] [header file path]
```

At runtime, shaders are mapped to their recompiled versions using a 64-bit XXH3 hash lookup. This scanning method is particularly useful for games that store embedded shaders within executables or uncompressed archive formats.

SPIR-V shaders are compressed using smol-v to improve zstd compression efficiency, while DXIL shaders are compressed as-is.

## Building

The project requires CMake 3.20 and a C++ compiler with C++17 support to build. While compilers other than Clang might work, they have not been tested. Since the repository includes submodules, ensure you clone it recursively.

## Special Thanks

This recompiler would not have been possible without the [CXBX-Reloaded](https://github.com/Cxbx-Reloaded/Cxbx-Reloaded) emulator. Nearly every aspect of the development was guided by referencing CXBX's shader translator and research.

## Final Words

I hope this recompiler proves useful in some way to help with your own recompilation efforts! While the implementation isn't as generic as I hoped it would be, the optimization opportunities from game specific implementations were too significant to ignore and paid off in the end.

If you find and fix mistakes in the recompiler or successfully implement missing features in a generic way, contributions would be greatly appreciated.
