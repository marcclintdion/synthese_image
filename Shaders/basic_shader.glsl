
#version 330

#ifdef VERTEX_SHADER
uniform mat4 mvpMatrix;
uniform mat4 trsMatrix;

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texcoord;
layout(location = 2) in vec3 normal;

out vec2 vtexcoord;
out vec3 worldPos;
out vec3 worldNormal;

void main( )
{
	gl_Position = mvpMatrix * vec4(position, 1);
	vtexcoord = texcoord;
	worldPos = (trsMatrix * vec4(position, 1)).xyz;
	worldNormal = (trsMatrix * vec4(normal, 0)).xyz;
}
#endif




#ifdef FRAGMENT_SHADER
uniform vec4 color;
uniform float shininess;

uniform vec3 camPos;
uniform vec4 ambientLight;
uniform vec3 lightDir;
uniform vec4 lightColor;
uniform float lightStrength;

uniform sampler2D diffuseTex;

in vec2 vtexcoord;
in vec3 worldPos;
in vec3 worldNormal;

out vec4 fragment_color;

void main()
{
	vec4 diffuseColor = color * texture(diffuseTex, vtexcoord);

	// Diffuse term (Lambert)
	float diffuse = max(0.0, dot(-lightDir, worldNormal));

	// Specular term (Blinn Phong)
	float specular = 0;
	if(diffuse > 0)
	{
		vec3 viewDir = normalize(camPos - worldPos);
		vec3 halfDir = normalize(-lightDir + viewDir);
		float specAngle = max(dot(halfDir, worldNormal), 0.0);
		specular = pow(specAngle, shininess);
	}

	// Final color
	fragment_color = ambientLight 
		+ diffuse * diffuseColor * (lightColor * lightStrength) 
		+ specular * (lightColor * lightStrength);
}
#endif