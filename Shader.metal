//
//  Shader.metal
//  LearningMetal
//
//  Created by Yevgen Ostroukhov on 5/3/25.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
};

struct InstanceData {
    float4x4 transform;
    float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
    float3 normal;
    float3 worldPosition;
};

vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                             uint instanceID [[instance_id]],
                             const device VertexIn* vertices [[buffer(0)]],
                             const device InstanceData* instanceData [[buffer(1)]]) {
    VertexIn vin = vertices[vertexID];
    float4x4 model = instanceData[instanceID].transform;

    float4 worldPos = model * vin.position;
    float3x3 normalMatrix = float3x3(model[0].xyz, model[1].xyz, model[2].xyz);
    float3 normal = normalize(normalMatrix * vin.normal);

    VertexOut out;
    out.position = worldPos;
    out.normal = normal;
    out.worldPosition = worldPos.xyz;
    out.color = instanceData[instanceID].color;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    float3 lightPos = float3(1.0, 1.0, 1.0);
    float3 cameraPos = float3(0.0, 0.0, 2.0);

    float3 normal = normalize(in.normal);
    float3 lightDir = normalize(lightPos - in.worldPosition);
    float3 viewDir = normalize(cameraPos - in.worldPosition);
    float3 halfVec = normalize(lightDir + viewDir);

    float diff = max(dot(normal, lightDir), 0.0);
    float spec = pow(max(dot(normal, halfVec), 0.0), 32.0);

    float3 ambient = 0.1 * in.color.rgb;
    float3 diffuse = diff * in.color.rgb;
    float3 specular = spec * float3(1.0);

    float3 color = ambient + diffuse + specular;
    return float4(color, 1.0);
}
