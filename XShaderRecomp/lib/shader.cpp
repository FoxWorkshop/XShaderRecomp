
#include "pch.h"
#include "shader.h"
#include <filesystem>
#include <fstream>
#include <array>
#include <chrono>
#include <thread>
#include <sstream>
#include "generated_shader_templates.h"


ShaderSources g_ShaderSources;

std::string template_vs[VertexShaderTypeMax] =
{
	XShaderRecomp::Templates::VertexShaderTemplate,
	XShaderRecomp::Templates::bones_int2,
	XShaderRecomp::Templates::bones_int4,
	XShaderRecomp::Templates::_2D_vs,
};

std::string template_ps = XShaderRecomp::Templates::PixelShaderTemplate;


std::ifstream OpenWithRetry(const std::string& path)
{
	auto fstream = std::ifstream(path);
	int failures = 0;
	while (fstream.fail()) {
		std::this_thread::sleep_for(std::chrono::milliseconds(50));
		fstream = std::ifstream(path);

		if (failures++ > 10) {
			// crash?
			XSHR_LOG("Error opening shader file: %s\n", path.c_str());
			break;
		}
	}

	return fstream;
}

int ShaderSources::Update() {
	int versionOnDisk = shaderVersionOnDisk;
	if (shaderVersionLoadedFromDisk != versionOnDisk) {
		LoadShadersFromDisk();
		shaderVersionLoadedFromDisk = versionOnDisk;
	}

	return shaderVersionLoadedFromDisk;
}

void ShaderSources::LoadShadersFromDisk()
{

	// Pixel Shader Template
	std::string hlsl = XShaderRecomp::Templates::PixelShaderTemplate;

	// Split the HLSL file on insertion points
	std::array<std::string, 2> insertionPoints = {
		"// <HARDCODED STATE GOES HERE>\n",
		"// <XBOX SHADER PROGRAM GOES HERE>\n",
	};
	int pos = 0;
	for (int i = 0; i < insertionPoints.size(); i++)
	{
		auto insertionPoint = insertionPoints[i];
		auto index = hlsl.find(insertionPoint, pos);

		if (index == std::string::npos) {
			// Handle broken shaders
			this->pixelShaderTemplateHlsl[i] = "";
		}
		else {
			this->pixelShaderTemplateHlsl[i] = hlsl.substr(pos, index - pos);
			pos = index + insertionPoint.length();
		}
	}
	this->pixelShaderTemplateHlsl[insertionPoints.size()] = hlsl.substr(pos);



	// Vertex Shader Template
	this->vertexShaderCommon = XShaderRecomp::Templates::common_vs;

	for (int type = 0; type < VertexShaderTypeMax; type++)
	{
		std::string hlsl = template_vs[type];

		const std::string insertionPoint = "// <XBOX SHADER PROGRAM GOES HERE>\n";
		auto index = hlsl.find(insertionPoint);

		if (index == std::string::npos)
		{
			// Handle broken shaders
			this->vertexShaderTemplateHlsl[type][0] = hlsl;
			this->vertexShaderTemplateHlsl[type][1] = "";
		}
		else
		{
			this->vertexShaderTemplateHlsl[type][0] = hlsl.substr(0, index);
			this->vertexShaderTemplateHlsl[type][1] = hlsl.substr(index + insertionPoint.length());
		}
	}

}
