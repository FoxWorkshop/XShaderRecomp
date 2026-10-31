#!/usr/bin/env python3
"""Generates one specialized vertex shader per logged state.

Background: see ../README.md.

Terms:
- state: one logged combination of shader inputs (a states.jsonl line).
- program: the settings we compile one variant from; states can share one.

Usage:
    generate.py --states states.jsonl [more.jsonl ...] --output generated [--dxil-macro NAME]

Every --states file is merged, so a game can add its own logs on top of
the shared states.jsonl. --dxil-macro is the C++ define that guards the
DXIL blobs in the catalog header.

Outputs:
- variant_NNN.hlsl: FFVS_*_VALUE defines + FixedFunctionVertexShader.hlsl.
- fixed_function_vertex_shader_variants.generated.h:
  state hash -> program key -> shader blobs.
- summary.txt: state and program counts.
- manifest.cmake: SHA-256 pins; CMake fails until you rerun after edits.
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import NamedTuple

# variant_hash.py is one directory up.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import variant_hash

CATALOG_FILE = "fixed_function_vertex_shader_variants.generated.h"
SUMMARY_FILE = "summary.txt"

LIGHT_COUNT = 8
TEXTURE_STAGE_COUNT = 4
TEXCOORD_SET_COUNT = 4  # texcoord0-3 in the vertex

# Material color sources (D3DMCS_*).
MATERIAL = 0
VERTEX_DIFFUSE = 1
VERTEX_SPECULAR = 2

# Texcoord generation modes (D3DTSS_TCI_*).
TEXCOORD_PASSTHROUGH = 0
GENERATIONS_USING_NORMAL = (1, 3, 5)

FOG_DEPTH_NONE = 0  # fog value comes from specular alpha

# Vertex input registers (D3DVSDE_*).
REGISTER_POSITION = 0
REGISTER_BLEND_WEIGHT = 1
REGISTER_NORMAL = 2
REGISTER_DIFFUSE = 3
REGISTER_SPECULAR = 4
REGISTER_BACK_DIFFUSE = 7
REGISTER_BACK_SPECULAR = 8
REGISTER_TEXCOORD0 = 9  # texcoord1-3 follow


class VertexState(NamedTuple):
    """One logged state. Same order as the C++ FixedFunctionVertexShaderControlState."""

    vertex_blend_matrix_count: int
    vertex_blend_calc_last_weight: int
    lighting_enable: int
    two_sided_lighting_enable: int
    local_viewer_enable: int
    normalize_normals_enable: int
    ambient_material_source: int
    diffuse_material_source: int
    specular_material_source: int
    emissive_material_source: int
    fog_enable: int
    fog_depth_mode: int
    light_types: tuple  # per light; 0 = unused
    texture_transform_counts: tuple  # per stage
    texture_transform_projected: tuple  # per stage; JSON only, not in C++
    texcoord_indices: tuple  # per stage
    texcoord_generation: tuple  # per stage
    texcoord_component_counts: tuple  # per texcoord set
    vertex_register_default_mask: int
    point_sprite_enable: int
    point_scale_enable: int
    specular_enable: int


ARRAY_LENGTHS = {
    "light_types": LIGHT_COUNT,
    "texture_transform_counts": TEXTURE_STAGE_COUNT,
    "texture_transform_projected": TEXTURE_STAGE_COUNT,
    "texcoord_indices": TEXTURE_STAGE_COUNT,
    "texcoord_generation": TEXTURE_STAGE_COUNT,
    "texcoord_component_counts": TEXCOORD_SET_COUNT,
}


class TextureStage(NamedTuple):
    transform_enable: int
    texcoord_index: int
    texcoord_generation: int
    texcoord_component_count: int


class VertexProgram(NamedTuple):
    """The settings we compile one variant from.

    Warning: PRESERVE THE ORDER OF THE FIELDS

    We hash them in order. So changing the order here would cook the player
    and require a hash re-generation.
    """

    vertex_blend_matrix_count: int
    vertex_blend_calc_last_weight: int
    lighting_enable: int
    two_sided_lighting_enable: int
    local_viewer_enable: int
    normalize_normals_enable: int
    material_sources: tuple  # ambient, diffuse, specular, emissive
    fog_enable: int
    fog_depth_mode: int
    light_types: tuple
    texture_stages: tuple  # TextureStage per stage
    vertex_register_default_mask: int
    point_sprite_enable: int
    point_scale_enable: int
    specular_enable: int


def load_states(path, state_by_hash):
    """Reads states.jsonl into (state hash, VertexState) pairs."""
    states = []

    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line:
            continue

        record = json.loads(line)
        if record.get("version") != 1:
            raise RuntimeError(f"{path}:{line_number}: unsupported version")

        fields = {}
        for field in VertexState._fields:
            if field not in ARRAY_LENGTHS:
                fields[field] = int(record[field])
                continue

            values = tuple(int(value) for value in record[field])
            if len(values) != ARRAY_LENGTHS[field]:
                raise RuntimeError(f"{path}:{line_number}: {field} must contain {ARRAY_LENGTHS[field]} values")
            fields[field] = values

        state = VertexState(**fields)
        state_hash = int(record["hash"], 16)

        if state_hash in state_by_hash and state_by_hash[state_hash] != state:
            raise RuntimeError(f"{path}:{line_number}: hash collision {state_hash:016X}")

        state_by_hash[state_hash] = state
        states.append((state_hash, state))

    return states


def normalize_state(state):
    """Zeroes inputs the shader never reads.

    Must match VertexShaderFamily::Normalize in
    fixed_function_vertex_shader_variants.cpp.

    This ensures that EQUAL states match.
    """
    lighting = state.lighting_enable != 0
    if lighting:
        light_types = state.light_types
        two_sided = int(state.two_sided_lighting_enable != 0)
        local_viewer = int(state.local_viewer_enable != 0 and any(light_types))  # needs a light
        material_sources = (
            state.ambient_material_source,
            state.diffuse_material_source,
            state.specular_material_source,
            state.emissive_material_source,
        )
    else:
        light_types = (0,) * LIGHT_COUNT
        two_sided = 0
        local_viewer = 0
        material_sources = (MATERIAL,) * 4

    # Generated texcoords ignore texcoord_index.
    texcoord_indices = []
    read_texcoord_sets = set()
    normal_used = lighting
    for stage in range(TEXTURE_STAGE_COUNT):
        generation = state.texcoord_generation[stage]
        if generation == TEXCOORD_PASSTHROUGH:
            index = state.texcoord_indices[stage]
            if index < TEXCOORD_SET_COUNT:
                read_texcoord_sets.add(index)
        else:
            index = 0

        if generation in GENERATIONS_USING_NORMAL:
            normal_used = True

        texcoord_indices.append(index)

    calc_last_weight = int(state.vertex_blend_calc_last_weight != 0)
    fog = state.fog_enable != 0
    point_sprite = state.point_sprite_enable != 0

    # Keep default-value bits only for registers the shader reads.
    lit_two_sided = lighting and two_sided
    used_registers = {REGISTER_POSITION}
    if state.vertex_blend_matrix_count > 1 or not calc_last_weight:
        used_registers.add(REGISTER_BLEND_WEIGHT)
    if normal_used:
        used_registers.add(REGISTER_NORMAL)
    if not lighting or VERTEX_DIFFUSE in material_sources:
        used_registers.add(REGISTER_DIFFUSE)
    if not lighting or VERTEX_SPECULAR in material_sources or (fog and state.fog_depth_mode == FOG_DEPTH_NONE):
        used_registers.add(REGISTER_SPECULAR)
    if not lit_two_sided or VERTEX_DIFFUSE in material_sources:
        used_registers.add(REGISTER_BACK_DIFFUSE)
    if not lit_two_sided or VERTEX_SPECULAR in material_sources:
        used_registers.add(REGISTER_BACK_SPECULAR)
    for index in read_texcoord_sets:
        used_registers.add(REGISTER_TEXCOORD0 + index)
    used_register_mask = sum(1 << register for register in used_registers)

    ambient, diffuse, specular, emissive = material_sources
    return VertexState(
        vertex_blend_matrix_count=state.vertex_blend_matrix_count,
        vertex_blend_calc_last_weight=calc_last_weight,
        lighting_enable=int(lighting),
        two_sided_lighting_enable=two_sided,
        local_viewer_enable=local_viewer,
        normalize_normals_enable=int(state.normalize_normals_enable != 0 and normal_used),
        ambient_material_source=ambient,
        diffuse_material_source=diffuse,
        specular_material_source=specular,
        emissive_material_source=emissive,
        fog_enable=int(fog),
        fog_depth_mode=state.fog_depth_mode if fog else 0,
        light_types=light_types,
        texture_transform_counts=tuple(int(count != 0) for count in state.texture_transform_counts),  # shader only checks != 0
        texture_transform_projected=(0,) * TEXTURE_STAGE_COUNT,  # unused
        texcoord_indices=tuple(texcoord_indices),
        texcoord_generation=tuple(state.texcoord_generation),
        texcoord_component_counts=tuple(
            count if index in read_texcoord_sets else 0
            for index, count in enumerate(state.texcoord_component_counts)
        ),
        vertex_register_default_mask=state.vertex_register_default_mask & used_register_mask,
        point_sprite_enable=int(point_sprite),
        point_scale_enable=int(state.point_scale_enable != 0 and point_sprite),
        specular_enable=int(state.specular_enable != 0 and lighting),
    )


def program_for(state):
    """Builds the VertexProgram for a normalized state."""
    texture_stages = []
    for stage in range(TEXTURE_STAGE_COUNT):
        index = state.texcoord_indices[stage]
        generation = state.texcoord_generation[stage]
        if generation == TEXCOORD_PASSTHROUGH and index < TEXCOORD_SET_COUNT:
            component_count = state.texcoord_component_counts[index]
        else:
            component_count = 0

        texture_stages.append(TextureStage(
            transform_enable=state.texture_transform_counts[stage],
            texcoord_index=index,
            texcoord_generation=generation,
            texcoord_component_count=component_count,
        ))

    return VertexProgram(
        vertex_blend_matrix_count=state.vertex_blend_matrix_count,
        vertex_blend_calc_last_weight=state.vertex_blend_calc_last_weight,
        lighting_enable=state.lighting_enable,
        two_sided_lighting_enable=state.two_sided_lighting_enable,
        local_viewer_enable=state.local_viewer_enable,
        normalize_normals_enable=state.normalize_normals_enable,
        material_sources=(
            state.ambient_material_source,
            state.diffuse_material_source,
            state.specular_material_source,
            state.emissive_material_source,
        ),
        fog_enable=state.fog_enable,
        fog_depth_mode=state.fog_depth_mode,
        light_types=state.light_types,
        texture_stages=tuple(texture_stages),
        vertex_register_default_mask=state.vertex_register_default_mask,
        point_sprite_enable=state.point_sprite_enable,
        point_scale_enable=state.point_scale_enable,
        specular_enable=state.specular_enable,
    )


def flatten(values):
    """Yields every number in a nested tuple, in order."""
    for value in values:
        if isinstance(value, tuple):
            yield from flatten(value)
        else:
            yield value


def program_key(program):
    return variant_hash.rapidhash64(list(flatten(program)))


def variant_name(number):
    return f"variant_{number:03}"


def write_text(path, text):
    """Writes UTF-8 with \\n line endings on every OS."""
    path.write_bytes(text.encode("utf-8"))


def sha256_of_text(path):
    """Same hash as CMake's normalized_text_sha256: line endings become \\n first."""
    text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_wrapper(path, program):
    ambient, diffuse, specular, emissive = program.material_sources
    lines = [
        "#define FIXED_FUNCTION_VERTEX_SHADER_VARIANT 1",
        f"#define FFVS_VERTEX_BLEND_MATRIX_COUNT_VALUE {program.vertex_blend_matrix_count}",
        f"#define FFVS_VERTEX_BLEND_CALC_LAST_WEIGHT_VALUE {program.vertex_blend_calc_last_weight}",
        f"#define FFVS_LIGHTING_ENABLE_VALUE {program.lighting_enable}",
        f"#define FFVS_TWO_SIDED_LIGHTING_ENABLE_VALUE {program.two_sided_lighting_enable}",
        f"#define FFVS_LOCAL_VIEWER_ENABLE_VALUE {program.local_viewer_enable}",
        f"#define FFVS_NORMALIZE_NORMALS_ENABLE_VALUE {program.normalize_normals_enable}",
        f"#define FFVS_AMBIENT_MATERIAL_SOURCE_VALUE {ambient}",
        f"#define FFVS_DIFFUSE_MATERIAL_SOURCE_VALUE {diffuse}",
        f"#define FFVS_SPECULAR_MATERIAL_SOURCE_VALUE {specular}",
        f"#define FFVS_EMISSIVE_MATERIAL_SOURCE_VALUE {emissive}",
        f"#define FFVS_FOG_ENABLE_VALUE {program.fog_enable}",
        f"#define FFVS_FOG_DEPTH_MODE_VALUE {program.fog_depth_mode}",
        f"#define FFVS_VERTEX_REGISTER_DEFAULT_MASK_VALUE {program.vertex_register_default_mask}",
        f"#define FFVS_POINT_SPRITE_ENABLE_VALUE {program.point_sprite_enable}",
        f"#define FFVS_POINT_SCALE_ENABLE_VALUE {program.point_scale_enable}",
        f"#define FFVS_SPECULAR_ENABLE_VALUE {program.specular_enable}",
    ]

    for index, light_type in enumerate(program.light_types):
        lines.append(f"#define FFVS_LIGHT_TYPE_{index}_VALUE {light_type}")

    for index, stage in enumerate(program.texture_stages):
        lines += [
            f"#define FFVS_TEXTURE_TRANSFORM_ENABLE_{index}_VALUE {stage.transform_enable}",
            f"#define FFVS_TEXCOORD_INDEX_{index}_VALUE {stage.texcoord_index}",
            f"#define FFVS_TEXCOORD_GENERATION_{index}_VALUE {stage.texcoord_generation}",
            f"#define FFVS_TEXCOORD_COMPONENT_COUNT_{index}_VALUE {stage.texcoord_component_count}",
        ]

    lines += ['#include "FixedFunctionVertexShader.hlsl"', ""]
    write_text(path, "\n".join(lines))


def cpp_initializer(state):
    """Formats a state as a C++ initializer, e.g. {1,0,...,{0,0,0,0},...}."""
    parts = []
    for field, value in state._asdict().items():
        if field == "texture_transform_projected":
            continue  # not in the C++ struct
        if isinstance(value, tuple):
            parts.append("{" + ",".join(str(item) for item in value) + "}")
        else:
            parts.append(str(value))
    return "{" + ",".join(parts) + "}"


PROGRAM_TABLE_START = """\
struct Program
{
    uint64_t key;
    const uint8_t* spirv;
    size_t spirvSize;
#ifdef DXIL_MACRO
    const uint8_t* dxil;
    size_t dxilSize;
#endif
};

static const Program Programs[] =
{"""

STATE_TABLE_START = """\
};

struct State
{
    uint64_t hash;
    FixedFunctionVertexShaderControlState state;
    uint64_t programKey;
};

static const State States[] =
{"""


def write_catalog(path, states, program_numbers, program_keys, dxil_macro):
    """Writes the Programs and States tables, sorted for binary search.

    states must already be sorted.
    """
    variants = [variant_name(number) for number in range(len(program_numbers))]

    lines = ["#pragma once", ""]
    lines += [f'#include "{variant}.hlsl.spirv.h"' for variant in variants]
    lines += ["", f"#ifdef {dxil_macro}"]
    lines += [f'#include "{variant}.hlsl.dxil.h"' for variant in variants]
    lines += ["#endif", "", "namespace FixedFunctionVertexShaderVariants::Generated", "{"]

    lines += PROGRAM_TABLE_START.replace("DXIL_MACRO", dxil_macro).splitlines()
    for program, key in sorted(program_keys.items(), key=lambda item: item[1]):
        variant = variant_name(program_numbers[program])
        lines += [
            "    {",
            f"        0x{key:016X}ULL,",
            f"        g_{variant}_spirv, sizeof(g_{variant}_spirv),",
            f"#ifdef {dxil_macro}",
            f"        g_{variant}_dxil, sizeof(g_{variant}_dxil),",
            "#endif",
            "    },",
        ]

    lines += STATE_TABLE_START.splitlines()
    for state_hash, state in states:
        key = program_keys[program_for(state)]
        lines.append(f"    {{ 0x{state_hash:016X}ULL, {cpp_initializer(state)}, 0x{key:016X}ULL }},")

    lines += [
        "};",
        f"static_assert(std::size(Programs) == {len(program_numbers)});",
        f"static_assert(std::size(States) == {len(states)});",
        "}",
        "",
    ]
    write_text(path, "\n".join(lines))


def write_manifest(path, states_paths, output_dir, program_count):
    """Writes manifest.cmake: SHA-256 pins that CMake checks at configure."""
    prefix = "FIXED_FUNCTION_VERTEX_SHADER"
    variants = [variant_name(number) for number in range(program_count)]
    states_sha256 = " ".join(f'"{sha256_of_text(states_path)}"' for states_path in states_paths)
    generated_files = [CATALOG_FILE, SUMMARY_FILE] + [f"{variant}.hlsl" for variant in variants]

    lines = [
        f'set({prefix}_STATES_SHA256 {states_sha256})',
        f'set({prefix}_GENERATOR_SHA256 "{sha256_of_text(Path(__file__))}")',
        f'set({prefix}_VARIANT_HASH_SHA256 "{sha256_of_text(Path(variant_hash.__file__))}")',
        f"set({prefix}_VARIANT_COUNT {program_count})",
        f"set({prefix}_VARIANTS",
    ]
    lines += [f'    "{variant}"' for variant in variants]
    lines += [")", "", f"set({prefix}_GENERATED_FILES"]
    lines += [f'    "{file_name}"' for file_name in generated_files]
    lines += [")", "", f"set({prefix}_GENERATED_SHA256"]
    lines += [f'    "{sha256_of_text(output_dir / file_name)}"' for file_name in generated_files]
    lines += [")", ""]
    write_text(path, "\n".join(lines))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--states", required=True, type=Path, nargs="+")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--dxil-macro", default="XSHADER_RECOMP_DXIL")
    args = parser.parse_args()

    # Logged and ran hashes at runtime are of normalized states.
    # So normalize the records to match.
    # Shared between files so a collision across files is caught too.
    state_by_hash = {}
    captured_states = [entry for path in args.states for entry in load_states(path, state_by_hash)]
    states = sorted({(state_hash, normalize_state(state)) for state_hash, state in captured_states})

    # Sorted so variant numbers stay stable between runs.
    programs = sorted({program_for(state) for _, state in states})
    program_numbers = {program: number for number, program in enumerate(programs)}
    program_keys = {program: program_key(program) for program in programs}
    if len(set(program_keys.values())) != len(programs):
        raise RuntimeError("program key collision")

    args.output.mkdir(parents=True, exist_ok=True)

    # Delete old wrappers in case we generate less variants than last time.
    for wrapper in args.output.glob("variant_*.hlsl"):
        wrapper.unlink()
    for program, number in program_numbers.items():
        write_wrapper(args.output / f"{variant_name(number)}.hlsl", program)

    write_catalog(args.output / CATALOG_FILE, states, program_numbers, program_keys, args.dxil_macro)
    write_text(
        args.output / SUMMARY_FILE,
        f"observed_states={len(captured_states)}\neffective_states={len(states)}\nprograms={len(programs)}\n",
    )
    write_manifest(args.output / "manifest.cmake", args.states, args.output, len(programs))


if __name__ == "__main__":
    main()
