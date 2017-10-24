
#version 330

#ifdef VERTEX_SHADER
uniform vec3 nearTopLeft;
uniform vec3 nearTopRight;
uniform vec3 nearBottomRight;
uniform vec3 nearBottomLeft;

const vec2 quadVertices[4] = vec2[4]( vec2( -1.0, -1.0), vec2( 1.0, -1.0), vec2( -1.0, 1.0), vec2( 1.0, 1.0));

out vec2 vtexcoord;
out vec3 vViewPos;

void main( )
{
	gl_Position = vec4(quadVertices[gl_VertexID], 0.0, 1.0);
	vtexcoord = (quadVertices[gl_VertexID] + 1.0) / 2.0;
	vViewPos.x = mix(nearBottomLeft.x, nearBottomRight.x, vtexcoord.x);
	vViewPos.y = mix(nearBottomLeft.y, nearTopLeft.y, vtexcoord.y);
	vViewPos.z = nearBottomLeft.z;
}
#endif




#ifdef FRAGMENT_SHADER
uniform sampler2D colorBuffer;
uniform sampler2D normalBuffer;
uniform sampler2D depthBuffer;
uniform vec2 renderSize;
uniform mat4 viewMatrix;
uniform mat4 projToPixel;
uniform float nearZ;
uniform float farZ;

const float maxSteps = 256;
const float maxDistance = 200.0;
const float jitter = 0.0;
const float stride = 4.0;
const float zThickness = 0.1;

in vec2 vtexcoord;
in vec3 vViewPos;

out vec4 pixelColor;

float distanceSquared(vec2 a, vec2 b) 
{ 
	a -= b; 
	return dot(a, a); 
}
 
bool traceScreenSpaceRay1(vec3 csOrig, vec3 csDir,
	out vec2 hitPixel, out vec3 hitPoint) 
{
    // Clip to the near plane
    float rayLength = ((csOrig.z + csDir.z * maxDistance) > -nearZ) ?
        (-nearZ - csOrig.z) / csDir.z : maxDistance;
    vec3 csEndPoint = csOrig + csDir * rayLength;
 
    // Project into homogeneous clip space
    vec4 H0 = projToPixel * vec4(csOrig, 1.0);
    vec4 H1 = projToPixel * vec4(csEndPoint, 1.0);
    float k0 = 1.0 / H0.w, k1 = 1.0 / H1.w;
 
    // The interpolated homogeneous version of the camera-space points  
    vec3 Q0 = csOrig * k0, Q1 = csEndPoint * k1;
 
    // Screen-space endpoints
	vec2 P0 = H0.xy * k0, P1 = H1.xy * k1;
 
    // If the line is degenerate, make it cover at least one pixel
    // to avoid handling zero-pixel extent as a special case later
    P1 += vec2((distanceSquared(P0, P1) < 0.0001) ? 0.01 : 0.0);
    vec2 delta = P1 - P0;
 
    // Permute so that the primary iteration is in x to collapse
    // all quadrant-specific DDA cases later
    bool permute = false;
    if (abs(delta.x) < abs(delta.y)) 
	{ 
        // This is a more-vertical line
        permute = true;
		delta = delta.yx;
		P0 = P0.yx;
		P1 = P1.yx; 
    }
 
    float stepDir = sign(delta.x);
    float invdx = stepDir / delta.x;
 
    // Track the derivatives of Q and k
    vec3  dQ = (Q1 - Q0) * invdx;
    float dk = (k1 - k0) * invdx;
    vec2  dP = vec2(stepDir, delta.y * invdx);
 
    // Scale derivatives by the desired pixel stride and then
    // offset the starting values by the jitter fraction
    dP *= stride; dQ *= stride; dk *= stride;
    P0 += dP * jitter; Q0 += dQ * jitter; k0 += dk * jitter;
 
    // Slide P from P0 to P1, (now-homogeneous) Q from Q0 to Q1, k from k0 to k1
    vec3 Q = Q0; 
 
    // Adjust end condition for iteration direction
    float end = P1.x * stepDir;
 
    float k = k0, stepCount = 0.0, prevZMaxEstimate = csOrig.z;
    float rayZMin = prevZMaxEstimate, rayZMax = prevZMaxEstimate;
    float sceneZMax = rayZMax + 100;
    for (vec2 P = P0; 
         ((P.x * stepDir) <= end) && (stepCount < maxSteps) &&
			((rayZMax < sceneZMax - zThickness) || (rayZMin > sceneZMax)) &&
			(sceneZMax != 0); 
         P += dP, Q.z += dQ.z, k += dk, ++stepCount) 
	{
        rayZMin = prevZMaxEstimate;
        rayZMax = (dQ.z * 0.5 + Q.z) / (dk * 0.5 + k);
        prevZMaxEstimate = rayZMax;
        if (rayZMin > rayZMax) 
		{ 
           float t = rayZMin;
		   rayZMin = rayZMax;
		   rayZMax = t;
        }
 
        hitPixel = permute ? P.yx : P;
        // You may need hitPixel.y = renderSize.y - hitPixel.y; here if your vertical axis
        // is different than ours in screen space
		float tempZ = (2 * nearZ) / (farZ + nearZ - texture(depthBuffer, hitPixel / renderSize).x * (farZ - nearZ));
		sceneZMax = -(tempZ * (farZ - nearZ) + nearZ);
    }
     
    // Advance Q based on the number of steps
    Q.xy += dQ.xy * stepCount;
    hitPoint = Q * (1.0 / k);
    return (rayZMax >= sceneZMax - zThickness) && (rayZMin < sceneZMax);
}

void main()
{
	// Sample original color
	pixelColor = texture(colorBuffer, vtexcoord.xy);

	// Calculate world pixel pos and normal
	float z = (2 * nearZ) / (farZ + nearZ - texture(depthBuffer, vtexcoord).x * (farZ - nearZ));
	if(z >= 0.9999f)
		return;

	vec3 vsPos = vViewPos + normalize(vViewPos) * (z * (farZ - nearZ) + nearZ);
	vsPos.z = -vsPos.z;
	vec3 vsNormal = (viewMatrix * vec4(texture(normalBuffer, vtexcoord).xyz, 0)).xyz;
	
	// Screen Space Reflection Test
	vec3 vsReflect = reflect(normalize(vViewPos), vsNormal);
	vsReflect.z = -vsReflect.z;
	vec2 hitPixel = vec2(0, 0);
	vec3 hitPoint = vec3(0, 0, 0);
	bool hit = traceScreenSpaceRay1(vsPos, vsReflect, hitPixel, hitPoint);

	// Move hit pixel from pixel position to UVs
	hitPixel /= renderSize;
	if(hitPixel.x > 1.0f || hitPixel.x < 0.0f || hitPixel.y > 1.0f || hitPixel.y < 0.0f)
		hit = false;
	
	// Combine colors
	if(hit == true)
		pixelColor += texture(colorBuffer, hitPixel.xy) * 0.5f;

	//pixelColor = vec4(vsReflect.xyz, 1);

	//pixelColor.x = hit ? 1.0 : 0.0;
	//pixelColor.xyz = vec3(hitPixel.xy, 0);
	//pixelColor.xyz = vec3(-csOrig.z/farZ, -csOrig.z/farZ, -csOrig.z/farZ);
	//pixelColor = pixelColor * texture(depthBuffer, vtexcoord.xy);
}
#endif