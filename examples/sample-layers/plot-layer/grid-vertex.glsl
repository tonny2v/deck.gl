// Copyright (c) 2015 Uber Technologies, Inc.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#define SHADER_NAME graph-layer-axis-vertex-shader

attribute vec3 positions;
attribute vec3 normals;
attribute vec2 instancePositions;
attribute vec3 instanceNormals;

uniform vec3 modelCenter;
uniform vec3 modelDim;
uniform float gridOffset;
uniform vec4 strokeColor;

varying vec4 vColor;
varying float shouldDiscard;

// determines if the grid line is behind or in front of the center
float frontFacing(vec3 v) {
  vec4 v_viewspace = project_to_viewspace(vec4(v, 0.0));
  return step(0.0, v_viewspace.z);
}

void main(void) {
  
  // rotated rectangle to align with slice:
  // for each x tick, draw rectangle on yz plane
  // for each y tick, draw rectangle on zx plane
  // for each z tick, draw rectangle on xy plane

  // offset of each corner of the rectangle from tick on axis
  vec3 gridVertexOffset = mat3(
      vec3(positions.z, positions.xy),
      vec3(positions.yz, positions.x),
      positions
    ) * instanceNormals;

  // normal of each edge of the rectangle from tick on axis
  vec3 gridLineNormal = mat3(
      vec3(normals.z, normals.xy),
      vec3(normals.yz, normals.x),
      normals
    ) * instanceNormals;

  // do not draw grid line in front of the graph
  shouldDiscard = frontFacing(gridLineNormal);

  vec3 position_modelspace = (vec3(instancePositions.x) - modelCenter) * instanceNormals + gridVertexOffset * modelDim / 2.0;

  // scale bounding box to fit into a unit cube that centers at [0, 0, 0]
  float scale = 1.0 / max(modelDim.x, max(modelDim.y, modelDim.z));
  position_modelspace *= scale;

  // apply offsets
  position_modelspace += gridOffset * gridLineNormal;

  gl_Position = project_to_clipspace(vec4(position_modelspace, 1.0));

  vColor = strokeColor / 255.0;
}
