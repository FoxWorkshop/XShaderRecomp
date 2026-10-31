#!/usr/bin/env python3
"""Generates one specialized pixel shader per logged state.

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
- variant_NNN.hlsl: FF_*_VALUE defines + FixedFunctionPixelShader.hlsl.
- fixed_function_pixel_shader_variants.generated.h:
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


CATALOG_FILE = "fixed_function_pixel_shader_variants.generated.h"
SUMMARY_FILE = "summary.txt"

TEXTURE_STAGE_COUNT = 4
D3DTOP_DISABLE = 1  # color_op that turns a stage, and every later stage, off


class TextureStage(NamedTuple):
    """One texture stage: how it blends texture, vertex color and previous stage."""

    color_op: int
    color_arg0: int
    color_arg1: int
    color_arg2: int
    alpha_op: int
    alpha_arg0: int
    alpha_arg1: int
    alpha_arg2: int
    result_arg: int
    texture_sample_type: int


DISABLED_STAGE = TextureStage(
    color_op=D3DTOP_DISABLE, color_arg0=1, color_arg1=0, color_arg2=1,
    alpha_op=D3DTOP_DISABLE, alpha_arg0=1, alpha_arg1=0, alpha_arg2=1,
    result_arg=1, texture_sample_type=0,
)


class PixelState(NamedTuple):
    """One logged state captured at runtime.

    Warning: PRESERVE THE ORDER OF THE FIELDS

    We hash them in order. So changing the order here would cook the player
    and require a hash re-generation.
    """

    stages: tuple  # TextureStage per stage
    specular_enable: int
    fog_enable: int
    fog_table_mode: int
    alpha_test_enable: int
    alpha_func: int


def load_states(path, state_by_hash):
    """Reads states.jsonl into (state hash, PixelState) pairs.

    Raises RuntimeError on a bad version, wrong stage count or hash collision.
    """
    states = []

    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if not line:
            continue

        record = json.loads(line)
        if record.get("version") != 1:
            raise RuntimeError(f"{path}:{line_number}: unsupported version")
        if len(record.get("stages", [])) != TEXTURE_STAGE_COUNT:
            raise RuntimeError(f"{path}:{line_number}: expected four stages")

        stages = tuple(
            TextureStage(**{field: int(stage[field]) for field in TextureStage._fields})
            for stage in record["stages"]
        )
        state = PixelState(
            stages=stages,
            specular_enable=int(record["specular_enable"]),
            fog_enable=int(record["fog_enable"]),
            fog_table_mode=int(record["fog_table_mode"]),
            alpha_test_enable=int(record["alpha_test_enable"]),
            alpha_func=int(record["alpha_func"]),
        )
        state_hash = int(record["hash"], 16)

        if state_hash in state_by_hash and state_by_hash[state_hash] != state:
            raise RuntimeError(f"{path}:{line_number}: hash collision {state_hash:016X}")

        state_by_hash[state_hash] = state
        states.append((state_hash, state))

    return states


def program_for(state):
    """Drops trailing disabled stages and zeroes settings of disabled features.

    Example: color_ops (4, 1, 1, 1) keep only stage 0.
    """
    active_stage_count = 0
    for index, stage in enumerate(state.stages):
        if stage.color_op != D3DTOP_DISABLE:
            active_stage_count = index + 1

    return PixelState(
        stages=state.stages[:active_stage_count],
        specular_enable=int(state.specular_enable != 0),
        fog_enable=int(state.fog_enable != 0),
        fog_table_mode=state.fog_table_mode if state.fog_enable else 0,
        alpha_test_enable=int(state.alpha_test_enable != 0),
        alpha_func=state.alpha_func if state.alpha_test_enable else 0,
    )


def program_key(program):
    """Hashes the stage count, each active stage, then the other fields."""
    values = [len(program.stages)]
    for stage in program.stages:
        values += stage
    values += program[1:]
    return variant_hash.rapidhash64(values)


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
    padding = [DISABLED_STAGE] * (TEXTURE_STAGE_COUNT - len(program.stages))
    lines = ["#define FIXED_FUNCTION_PIXEL_SHADER_VARIANT 1"]

    for index, stage in enumerate(list(program.stages) + padding):
        for field, value in stage._asdict().items():
            lines.append(f"#define FF_{field.upper()}_{index}_VALUE {value}")

    lines += [
        f"#define FF_ACTIVE_STAGE_COUNT_VALUE {len(program.stages)}",
        f"#define FF_SPECULAR_ENABLE_VALUE {program.specular_enable}",
        f"#define FF_FOG_ENABLE_VALUE {program.fog_enable}",
        f"#define FF_FOG_TABLE_MODE_VALUE {program.fog_table_mode}",
        f"#define FF_ALPHA_TEST_ENABLE_VALUE {program.alpha_test_enable}",
        f"#define FF_ALPHA_FUNC_VALUE {program.alpha_func}",
        '#include "FixedFunctionPixelShader.hlsl"',
        "",
    ]
    write_text(path, "\n".join(lines))


def cpp_initializer(state):
    """Formats a state as a C++ initializer.

    The C++ struct is field-major:
    {{op0,op1,op2,op3},{arg0 x4},...,specular,fog,...}.
    """
    parts = []
    for field in TextureStage._fields:
        values = (getattr(stage, field) for stage in state.stages)
        parts.append("{" + ",".join(str(value) for value in values) + "}")
    parts += [str(value) for value in state[1:]]
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
    FixedFunctionPixelShaderState state;
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
    lines += ["#endif", "", "namespace FixedFunctionPixelShaderVariants::Generated", "{"]

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
    prefix = "FIXED_FUNCTION_PIXEL_SHADER"
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

    # Shared between files so a collision across files is caught too.
    state_by_hash = {}
    # drop duplicates
    states = sorted({entry for path in args.states for entry in load_states(path, state_by_hash)})

    # Sorted so we're consistent between runs.
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
    write_text(args.output / SUMMARY_FILE, f"states={len(states)}\nprograms={len(programs)}\n")
    write_manifest(args.output / "manifest.cmake", args.states, args.output, len(programs))


if __name__ == "__main__":
    main()
