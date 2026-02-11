project(XShaderRecomp)

if (WIN32)
    option(XSHADER_RECOMP_DXIL "Generate DXIL shader cache" ON)
endif()

set(SMOLV_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../thirdparty/smol-v/source")

file(GLOB SHADER_TEMPLATES
    ${CMAKE_CURRENT_SOURCE_DIR}/template_vs/*.hlsl
    ${CMAKE_CURRENT_SOURCE_DIR}/template_ps/*.hlsl
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

add_library(XShaderRecomp STATIC
    constant_table.h
    dxc_compiler.cpp
    dxc_compiler.h
    pch.h
    shader.cpp
    shader.h
    shader_code.h
    shader_recompiler.cpp
    shader_recompiler.h
    vertex_shader.cpp 
    vertex_shader.h
    pixel_shader.cpp
    pixel_shader.h
    "include/api.h"
    "${SMOLV_SOURCE_DIR}/smolv.cpp")

target_link_libraries(XShaderRecomp PRIVATE
    Microsoft::DirectXShaderCompiler
    xxHash::xxhash
    libzstd_static
    fmt::fmt)

target_include_directories(XShaderRecomp
    PRIVATE ${SMOLV_SOURCE_DIR}
    PUBLIC ${CMAKE_CURRENT_BINARY_DIR}
)

target_precompile_headers(XShaderRecomp PRIVATE pch.h)

if (CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    target_compile_options(XShaderRecomp PRIVATE -Wno-switch -Wno-unused-variable -Wno-null-arithmetic -fms-extensions)

    include(CheckCXXSymbolExists)
    check_cxx_symbol_exists(_LIBCPP_VERSION version LIBCPP)
    if(LIBCPP)
        # Allows using std::execution
        target_compile_options(XShaderRecomp PRIVATE -fexperimental-library)
    endif()
endif()

#if (WIN32)
 #   target_compile_definitions(XShaderRecomp PRIVATE _CRT_SECURE_NO_WARNINGS)
  #  add_custom_command(TARGET XShaderRecomp POST_BUILD
   #     COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_RUNTIME_DLLS:XShaderRecomp> $<TARGET_FILE_DIR:XShaderRecomp>
    #    COMMAND_EXPAND_LISTS
    #)
#endif()

if (XSHADER_RECOMP_DXIL)
    target_compile_definitions(XShaderRecomp PRIVATE XSHADER_RECOMP_DXIL)
    target_link_libraries(XShaderRecomp PRIVATE Microsoft::DXIL)
endif()
