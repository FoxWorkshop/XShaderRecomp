project(XShaderRecomp)

if (WIN32)
    option(XSHADER_RECOMP_DXIL "Generate DXIL shader cache" ON)
endif()

set(SMOLV_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/smol-v/source")

file(GLOB SHADER_TEMPLATES
    ${CMAKE_CURRENT_SOURCE_DIR}/template_vs/*.hlsl
    ${CMAKE_CURRENT_SOURCE_DIR}/template_ps/*.hlsl
    ${CMAKE_CURRENT_SOURCE_DIR}/hlsli/*.hlsli
)

set(GENERATED_SHADER_HEADER
    ${CMAKE_CURRENT_BINARY_DIR}/generated_shader_templates.h
)

file(WRITE ${GENERATED_SHADER_HEADER} "#pragma once\n\nnamespace XShaderRecomp::Templates {\n")
foreach(shader ${SHADER_TEMPLATES})
    get_filename_component(name ${shader} NAME_WE)
    file(READ ${shader} content)

    string(REPLACE "\\" "\\\\" content "${content}")
    string(REPLACE "\"" "\\\"" content "${content}")
    string(REPLACE "\n" "\\n\"\n\"" content "${content}")

    file(APPEND ${GENERATED_SHADER_HEADER}
        "inline const char* ${name} =\n\"${content}\";\n\n")
endforeach()
file(APPEND ${GENERATED_SHADER_HEADER} "}\n")

add_library(XShaderRecompLib STATIC
    "lib/constant_table.h"
    "lib/dxc_compiler.cpp"
    "lib/dxc_compiler.h"
    
    "lib/pch.h"
    "lib/shader.cpp"
    "lib/shader.h"
    "lib/shader_code.h"
    "lib/vertex_shader.cpp" 
    "lib/vertex_shader.h"
    "lib/pixel_shader.cpp"
    "lib/pixel_shader.h"
    "lib/vertex_declaration.cpp"
    "lib/vertex_declaration.h"
    "lib/api.cpp"
    "lib/include/xshader_api.h"
    "lib/os.cpp" 
    "lib/os.h"
    "${SMOLV_SOURCE_DIR}/smolv.cpp"
)



target_link_libraries(XShaderRecompLib PRIVATE
    Microsoft::DirectXShaderCompiler
    xxHash::xxhash
    libzstd_static
    fmt::fmt
)


# Tool executable
add_executable(XShaderRecompTool
    tool/main.cpp
)

target_link_libraries(XShaderRecompTool
    PRIVATE
        XShaderRecompLib
        Microsoft::DirectXShaderCompiler
        xxHash::xxhash
        libzstd_static
        fmt::fmt
)



target_include_directories(XShaderRecompLib
    PUBLIC 
        lib
        ${CMAKE_CURRENT_BINARY_DIR}
        ${SMOLV_SOURCE_DIR}
)

target_precompile_headers(XShaderRecompLib PRIVATE lib/pch.h)
target_precompile_headers(XShaderRecompTool REUSE_FROM XShaderRecompLib)

if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    target_compile_options(XShaderRecompLib PRIVATE -Wno-switch -Wno-unused-variable -Wno-null-arithmetic -fms-extensions)
    target_compile_options(XShaderRecompTool PRIVATE -Wno-switch -Wno-unused-variable -Wno-null-arithmetic -fms-extensions)

    include(CheckCXXSymbolExists)
    check_cxx_symbol_exists(_LIBCPP_VERSION version LIBCPP)
    if(LIBCPP)
        # Allows using std::execution
        target_compile_options(XShaderRecompLib PRIVATE -fexperimental-library)
        target_compile_options(XShaderRecompTool PRIVATE -fexperimental-library)
    endif()
endif()

if (WIN32)
    target_compile_definitions(XShaderRecompTool PRIVATE _CRT_SECURE_NO_WARNINGS)
    add_custom_command(TARGET XShaderRecompTool POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_RUNTIME_DLLS:XShaderRecompTool> $<TARGET_FILE_DIR:XShaderRecompTool>
        COMMAND_EXPAND_LISTS
    )
endif()

if (XSHADER_RECOMP_DXIL)
    target_compile_definitions(XShaderRecompLib PRIVATE XSHADER_RECOMP_DXIL)
    target_link_libraries(XShaderRecompLib PRIVATE Microsoft::DXIL)
    target_link_libraries(XShaderRecompTool PRIVATE Microsoft::DXIL)
    target_compile_definitions(XShaderRecompTool PRIVATE XSHADER_RECOMP_DXIL)
endif()
