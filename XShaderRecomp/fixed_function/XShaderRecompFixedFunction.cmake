# Fixed function ubershaders and their specialized variants.
#
# Include this file, then call xsr_add_fixed_function_shaders from the game.
# See README.md in this folder for the whole flow.

set(XSR_FIXED_FUNCTION_DIR "${CMAKE_CURRENT_LIST_DIR}")

# Quick validation:
#
# SHA-256 over file text with line endings.
# We use to ensure generator+generated stay in sync;
# and re-generation was not forgotten.
#
# Normalized to LF, so consistent on Linux+Windows.
function(xsr_normalized_text_sha256 FILE_PATH OUTPUT_VARIABLE)
    file(READ "${FILE_PATH}" FILE_CONTENT)
    string(REPLACE "\r\n" "\n" FILE_CONTENT "${FILE_CONTENT}")
    string(REPLACE "\r" "\n" FILE_CONTENT "${FILE_CONTENT}")
    string(SHA256 FILE_HASH "${FILE_CONTENT}")
    set(${OUTPUT_VARIABLE} "${FILE_HASH}" PARENT_SCOPE)
endfunction()

# Compiles one shader to SPIR-V (and DXIL when enabled) as C headers.
#
# Parameters:
# - TARGET: target that gets the headers as sources
# - SOURCE: .hlsl file to compile
# - OUTPUT_DIR: where SOURCE_NAME.hlsl.spirv.h / .dxil.h are written
# - PROFILE: shader profile, e.g. ps_6_0
# - DXC: path to dxc
# - DXIL: true to also build DXIL
# - DEPENDS: sources the shader includes
# - ARGS: extra dxc flags for SPIR-V, e.g. -fvk-invert-y
function(xsr_compile_fixed_function_shader)
    cmake_parse_arguments(ARG "" "TARGET;SOURCE;OUTPUT_DIR;PROFILE;DXIL" "DXC;DEPENDS;ARGS" ${ARGN})

    cmake_path(GET ARG_SOURCE FILENAME FILE_NAME)
    cmake_path(GET ARG_SOURCE STEM VARIABLE_NAME)
    set(OUTPUT_PATH "${ARG_OUTPUT_DIR}/${FILE_NAME}")
    file(MAKE_DIRECTORY "${ARG_OUTPUT_DIR}")

    if (ARG_DXIL)
        add_custom_command(
            OUTPUT ${OUTPUT_PATH}.dxil.h
            COMMAND ${ARG_DXC} -T ${ARG_PROFILE} -HV 2021 -all-resources-bound -Wno-ignored-attributes -I ${XSR_FIXED_FUNCTION_DIR} -Fh ${OUTPUT_PATH}.dxil.h ${ARG_SOURCE} -Vn g_${VARIABLE_NAME}_dxil
            DEPENDS ${ARG_SOURCE} ${ARG_DEPENDS}
        )
        target_sources(${ARG_TARGET} PRIVATE ${OUTPUT_PATH}.dxil.h)
    endif()
    add_custom_command(
        OUTPUT ${OUTPUT_PATH}.spirv.h
        COMMAND ${ARG_DXC} -T ${ARG_PROFILE} -HV 2021 -all-resources-bound -spirv -fvk-use-dx-layout -I ${XSR_FIXED_FUNCTION_DIR} ${ARG_ARGS} -Fh ${OUTPUT_PATH}.spirv.h ${ARG_SOURCE} -Vn g_${VARIABLE_NAME}_spirv
        DEPENDS ${ARG_SOURCE} ${ARG_DEPENDS}
    )
    target_sources(${ARG_TARGET} PRIVATE ${OUTPUT_PATH}.spirv.h)
endfunction()

# Registers a compile rule for every variant of one family.
# Configure aborts unless the committed generated outputs match the
# generator inputs pinned in the manifest.
#
# Parameters:
# - FAMILY_NAME: prefix of the manifest variables
# - FAMILY_SUBDIR: family folder in this directory, holds generate.py
# - GENERATED_DIR: the game's folder with the generator outputs
# - STATES: states.jsonl files, in the order given to generate.py
# - DXIL_MACRO: value given to generate.py --dxil-macro
# - SHARED_DEPENDENCIES: sources every variant depends on
# - TARGET, PROFILE, DXC, DXIL, ARGS: forwarded to xsr_compile_fixed_function_shader
#
# Reads these variables from GENERATED_DIR/manifest.cmake, each prefixed
# with FAMILY_NAME:
# - *_STATES_SHA256: pinned hashes of the states files, in order
# - *_GENERATOR_SHA256, *_VARIANT_HASH_SHA256: pinned hashes of generate.py
#   and variant_hash.py
# - *_VARIANTS, *_VARIANT_COUNT: variant names and their count
# - *_GENERATED_FILES, *_GENERATED_SHA256: output files and pinned hashes,
#   matched by index
#
# Errors: configure stops with FATAL_ERROR when:
# - a states file, generate.py or variant_hash.py no longer matches its
#   pinned hash
# - *_VARIANT_COUNT differs from the length of *_VARIANTS
# - *_GENERATED_FILES and *_GENERATED_SHA256 have different lengths
# - a pinned output file is missing or no longer matches its pinned hash
# - the wrapper files on disk do not match *_VARIANTS
function(xsr_define_fixed_function_variants)
    cmake_parse_arguments(ARG "" "FAMILY_NAME;FAMILY_SUBDIR;GENERATED_DIR;DXIL_MACRO;TARGET;PROFILE;DXIL"
        "DXC;STATES;SHARED_DEPENDENCIES;ARGS" ${ARGN})

    set(FAMILY_NAME ${ARG_FAMILY_NAME})
    set(GENERATED_DIR "${ARG_GENERATED_DIR}")
    set(GENERATOR_PATH "${XSR_FIXED_FUNCTION_DIR}/${ARG_FAMILY_SUBDIR}/generate.py")
    set(VARIANT_HASH_PATH "${XSR_FIXED_FUNCTION_DIR}/variant_hash.py")

    # Quoted, so it still works when pasted with spaces in the paths.
    set(STATES_ARGS)
    foreach(STATES_PATH IN LISTS ARG_STATES)
        string(APPEND STATES_ARGS " \"${STATES_PATH}\"")
    endforeach()
    set(REGENERATE_COMMAND
        "  python3 \"${GENERATOR_PATH}\" --states${STATES_ARGS} --output \"${GENERATED_DIR}\" --dxil-macro ${ARG_DXIL_MACRO}")

    include("${GENERATED_DIR}/manifest.cmake")

    # Rerun configure when any generator input or the manifest changes.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
        ${ARG_STATES}
        "${GENERATOR_PATH}"
        "${VARIANT_HASH_PATH}"
        "${GENERATED_DIR}/manifest.cmake")

    # Generator inputs must still match the pins recorded in the manifest.
    set(STATES_CURRENT_SHA256)
    foreach(STATES_PATH IN LISTS ARG_STATES)
        xsr_normalized_text_sha256("${STATES_PATH}" STATES_FILE_SHA256)
        list(APPEND STATES_CURRENT_SHA256 "${STATES_FILE_SHA256}")
    endforeach()
    xsr_normalized_text_sha256("${GENERATOR_PATH}" GENERATOR_CURRENT_SHA256)
    xsr_normalized_text_sha256("${VARIANT_HASH_PATH}" VARIANT_HASH_CURRENT_SHA256)

    if (NOT "${STATES_CURRENT_SHA256}" STREQUAL "${${FAMILY_NAME}_STATES_SHA256}")
        message(FATAL_ERROR
            "${FAMILY_NAME} variants are stale: the states files changed.\n"
            "Regenerate and commit the outputs:\n"
            "${REGENERATE_COMMAND}")
    endif()
    if (NOT GENERATOR_CURRENT_SHA256 STREQUAL ${FAMILY_NAME}_GENERATOR_SHA256)
        message(FATAL_ERROR
            "${FAMILY_NAME} variants are stale: generate.py changed.\n"
            "Regenerate and commit the outputs so their pins match the generator:\n"
            "${REGENERATE_COMMAND}")
    endif()
    if (NOT VARIANT_HASH_CURRENT_SHA256 STREQUAL ${FAMILY_NAME}_VARIANT_HASH_SHA256)
        message(FATAL_ERROR
            "${FAMILY_NAME} variants are stale: variant_hash.py changed.\n"
            "Regenerate and commit the outputs so their pins match the shared hash module:\n"
            "${REGENERATE_COMMAND}")
    endif()

    list(LENGTH ${FAMILY_NAME}_VARIANTS MANIFEST_VARIANT_COUNT)
    if (NOT MANIFEST_VARIANT_COUNT EQUAL ${FAMILY_NAME}_VARIANT_COUNT)
        message(FATAL_ERROR "${FAMILY_NAME} variant manifest count mismatch")
    endif()

    list(LENGTH ${FAMILY_NAME}_GENERATED_FILES GENERATED_FILE_COUNT)
    list(LENGTH ${FAMILY_NAME}_GENERATED_SHA256 GENERATED_HASH_COUNT)
    if (NOT GENERATED_FILE_COUNT EQUAL GENERATED_HASH_COUNT)
        message(FATAL_ERROR "${FAMILY_NAME} generated-file hash count mismatch")
    endif()

    # Verify every pinned output file exists and still matches its pin.
    if (GENERATED_FILE_COUNT GREATER 0)
        math(EXPR GENERATED_LAST_INDEX "${GENERATED_FILE_COUNT} - 1")
        foreach(GENERATED_INDEX RANGE ${GENERATED_LAST_INDEX})
            list(GET ${FAMILY_NAME}_GENERATED_FILES ${GENERATED_INDEX} GENERATED_FILE)
            list(GET ${FAMILY_NAME}_GENERATED_SHA256 ${GENERATED_INDEX} GENERATED_EXPECTED_SHA256)
            set(GENERATED_PATH "${GENERATED_DIR}/${GENERATED_FILE}")
            if (NOT EXISTS "${GENERATED_PATH}")
                message(FATAL_ERROR "Missing ${FAMILY_NAME} generated file: ${GENERATED_FILE}")
            endif()
            xsr_normalized_text_sha256("${GENERATED_PATH}" GENERATED_CURRENT_SHA256)
            if (NOT GENERATED_CURRENT_SHA256 STREQUAL GENERATED_EXPECTED_SHA256)
                message(FATAL_ERROR
                    "${FAMILY_NAME} generated file is stale: ${GENERATED_FILE}\n"
                    "Regenerate and commit the outputs:\n"
                    "${REGENERATE_COMMAND}")
            endif()
            set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${GENERATED_PATH}")
        endforeach()
    endif()

    # Wrapper files on disk must be exactly the manifest variant list.
    file(GLOB GENERATED_WRAPPERS CONFIGURE_DEPENDS RELATIVE "${GENERATED_DIR}"
        "${GENERATED_DIR}/variant_*.hlsl")
    set(EXPECTED_WRAPPERS)
    foreach(VARIANT IN LISTS ${FAMILY_NAME}_VARIANTS)
        list(APPEND EXPECTED_WRAPPERS "${VARIANT}.hlsl")
    endforeach()
    list(SORT GENERATED_WRAPPERS)
    list(SORT EXPECTED_WRAPPERS)
    if (NOT GENERATED_WRAPPERS STREQUAL EXPECTED_WRAPPERS)
        message(FATAL_ERROR
            "${FAMILY_NAME} generated wrapper list is stale.\n"
            "Regenerate and commit the outputs:\n"
            "${REGENERATE_COMMAND}")
    endif()

    # Variants compile next to their wrappers, the catalog header includes them from there.
    foreach(VARIANT IN LISTS ${FAMILY_NAME}_VARIANTS)
        xsr_compile_fixed_function_shader(
            TARGET ${ARG_TARGET}
            SOURCE "${GENERATED_DIR}/${VARIANT}.hlsl"
            OUTPUT_DIR "${GENERATED_DIR}"
            PROFILE ${ARG_PROFILE}
            DXC "${ARG_DXC}"
            DXIL ${ARG_DXIL}
            DEPENDS ${ARG_SHARED_DEPENDENCIES}
            ARGS ${ARG_ARGS})
    endforeach()
endfunction()

# Adds the fixed function shaders to a game target:
# - the generic ubershaders, used for any state without a variant
# - the variants generated from the states files, when a generated dir is given
#
# Parameters:
# - TARGET: game target
# - DXC: path to dxc
# - DXIL: true to also build DXIL
# - DXIL_MACRO: C++ define that guards DXIL in the catalog headers
# - OUTPUT_DIR: where the generic ubershader headers go; added to the
#   target include dirs, so include "FixedFunctionPixelShader.hlsl.spirv.h"
# - PIXEL_GENERATED_DIR, VERTEX_GENERATED_DIR: optional, the game's
#   generate.py output folders; leave out to only use the generic shaders
# - PIXEL_STATES, VERTEX_STATES: optional, states files given to generate.py;
#   default to the shared states.jsonl of each family
function(xsr_add_fixed_function_shaders)
    cmake_parse_arguments(ARG "" "TARGET;DXIL;DXIL_MACRO;OUTPUT_DIR;PIXEL_GENERATED_DIR;VERTEX_GENERATED_DIR"
        "DXC;PIXEL_STATES;VERTEX_STATES" ${ARGN})

    if (NOT ARG_DXIL_MACRO)
        set(ARG_DXIL_MACRO XSHADER_RECOMP_DXIL)
    endif()
    if (NOT ARG_PIXEL_STATES)
        set(ARG_PIXEL_STATES "${XSR_FIXED_FUNCTION_DIR}/fixed_function_pixel_shader/states.jsonl")
    endif()
    if (NOT ARG_VERTEX_STATES)
        set(ARG_VERTEX_STATES "${XSR_FIXED_FUNCTION_DIR}/fixed_function_vertex_shader/states.jsonl")
    endif()

    target_include_directories(${ARG_TARGET} PRIVATE "${ARG_OUTPUT_DIR}")

    set(PIXEL_SHARED_FILES
        "${XSR_FIXED_FUNCTION_DIR}/FixedFunctionPixelShader.hlsl"
        "${XSR_FIXED_FUNCTION_DIR}/common_fixed_ps.hlsli"
        "${XSR_FIXED_FUNCTION_DIR}/fixed_function_pixel_shader/state.hlsli")

    xsr_compile_fixed_function_shader(
        TARGET ${ARG_TARGET}
        SOURCE "${XSR_FIXED_FUNCTION_DIR}/FixedFunctionPixelShader.hlsl"
        OUTPUT_DIR "${ARG_OUTPUT_DIR}"
        PROFILE ps_6_0
        DXC "${ARG_DXC}"
        DXIL ${ARG_DXIL}
        DEPENDS ${PIXEL_SHARED_FILES})

    if (ARG_PIXEL_GENERATED_DIR)
        xsr_define_fixed_function_variants(
            FAMILY_NAME FIXED_FUNCTION_PIXEL_SHADER
            FAMILY_SUBDIR fixed_function_pixel_shader
            GENERATED_DIR "${ARG_PIXEL_GENERATED_DIR}"
            STATES ${ARG_PIXEL_STATES}
            DXIL_MACRO ${ARG_DXIL_MACRO}
            SHARED_DEPENDENCIES ${PIXEL_SHARED_FILES}
            TARGET ${ARG_TARGET}
            PROFILE ps_6_0
            DXC "${ARG_DXC}"
            DXIL ${ARG_DXIL})
    endif()

    set(VERTEX_SHARED_FILES
        "${XSR_FIXED_FUNCTION_DIR}/FixedFunctionVertexShader.hlsl"
        "${XSR_FIXED_FUNCTION_DIR}/common_fixed_vs.hlsli"
        "${XSR_FIXED_FUNCTION_DIR}/fixed_function_vertex_shader/state.hlsli")

    xsr_compile_fixed_function_shader(
        TARGET ${ARG_TARGET}
        SOURCE "${XSR_FIXED_FUNCTION_DIR}/FixedFunctionVertexShader.hlsl"
        OUTPUT_DIR "${ARG_OUTPUT_DIR}"
        PROFILE vs_6_0
        DXC "${ARG_DXC}"
        DXIL ${ARG_DXIL}
        DEPENDS ${VERTEX_SHARED_FILES}
        ARGS -fvk-invert-y)

    if (ARG_VERTEX_GENERATED_DIR)
        xsr_define_fixed_function_variants(
            FAMILY_NAME FIXED_FUNCTION_VERTEX_SHADER
            FAMILY_SUBDIR fixed_function_vertex_shader
            GENERATED_DIR "${ARG_VERTEX_GENERATED_DIR}"
            STATES ${ARG_VERTEX_STATES}
            DXIL_MACRO ${ARG_DXIL_MACRO}
            SHARED_DEPENDENCIES ${VERTEX_SHARED_FILES}
            TARGET ${ARG_TARGET}
            PROFILE vs_6_0
            DXC "${ARG_DXC}"
            DXIL ${ARG_DXIL}
            ARGS -fvk-invert-y)
    endif()
endfunction()
