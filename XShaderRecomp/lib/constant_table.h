#pragma once

enum class ParameterClass : uint16_t // D3DXPARAMETER_CLASS
{
    Scalar,
    Vector,
    MatrixRows,
    MatrixColumns,
    Object,
    Struct
};

enum class ParameterType : uint16_t // D3DXPARAMETER_TYPE 
{
    Void,
    Bool,
    Int,
    Float,
    String,
    Texture,
    Texture1D,
    Texture2D,
    Texture3D,
    TextureCube,
    Sampler,
    Sampler1D,
    Sampler2D,
    Sampler3D,
    SamplerCube,
    PixelShader,
    VertexShader,
    PixelFragment,
    VertexFragment,
    Unsupported
};

struct StructMemberInfo // D3DXSHADER_STRUCTMEMBERINFO
{
   uint32_t name;
   uint32_t typeInfo;
};

struct TypeInfo // D3DXSHADER_TYPEINFO
{
    ParameterClass parameterClass;
    ParameterType parameterType;
    uint16_t rows;
    uint16_t columns;
    uint16_t elements;
    uint16_t structMembers;
    uint32_t structMemberInfo;
};

enum class RegisterSet : uint16_t // D3DXREGISTER_SET
{
    Bool,
    Int4,
    Float4,
    Sampler
};

struct ConstantInfo // D3DXSHADER_CONSTANTINFO
{
    uint32_t name;
    RegisterSet registerSet;
    uint16_t registerIndex;
    uint16_t registerCount;
    uint16_t reserved;
    uint32_t typeInfo;
    uint32_t defaultValue;
};

struct ConstantTable // D3DXSHADER_CONSTANTTABLE
{
    uint32_t size;
    uint32_t creator;
    uint32_t version;
    uint32_t constants;
    uint32_t constantInfo;
    uint32_t flags;
    uint32_t target;
};

struct ConstantTableContainer
{
    uint32_t size;
    ConstantTable constantTable;
};