const float TILE_SIZE = 512.0;
const float PI = 3.1415926536;
const float WORLD_SCALE = TILE_SIZE / (PI * 2.0);

// ref: lib/constants.js
const float PROJECT_IDENTITY = 0.;
const float PROJECT_MERCATOR = 1.;
const float PROJECT_MERCATOR_OFFSETS = 2.;

uniform float projectionMode;
uniform float projectionScale;
uniform vec4 projectionCenter;
uniform vec3 projectionPixelsPerUnit;

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;
uniform mat4 projectionMatrixUncentered;

#ifdef INTEL_TAN_WORKAROUND

// All these functions are for substituting tan() function from Intel GPU only
const float TWO_PI = 6.2831854820251465;
const float PI_2 = 1.5707963705062866;
const float PI_16 = 0.1963495463132858;

const float SIN_TABLE_0 = 0.19509032368659973;
const float SIN_TABLE_1 = 0.3826834261417389;
const float SIN_TABLE_2 = 0.5555702447891235;
const float SIN_TABLE_3 = 0.7071067690849304;

const float COS_TABLE_0 = 0.9807852506637573;
const float COS_TABLE_1 = 0.9238795042037964;
const float COS_TABLE_2 = 0.8314695954322815;
const float COS_TABLE_3 = 0.7071067690849304;

const float INVERSE_FACTORIAL_3 = 1.666666716337204e-01; // 1/3!
const float INVERSE_FACTORIAL_5 = 8.333333767950535e-03; // 1/5!
const float INVERSE_FACTORIAL_7 = 1.9841270113829523e-04; // 1/7!
const float INVERSE_FACTORIAL_9 = 2.75573188446287533e-06; // 1/9!

float sin_taylor_fp32(float a) {
  float r, s, t, x;

  if (a == 0.0) {
    return 0.0;
  }

  x = -a * a;
  s = a;
  r = a;

  r = r * x;
  t = r * INVERSE_FACTORIAL_3;
  s = s + t;

  r = r * x;
  t = r * INVERSE_FACTORIAL_5;
  s = s + t;

  r = r * x;
  t = r * INVERSE_FACTORIAL_7;
  s = s + t;

  r = r * x;
  t = r * INVERSE_FACTORIAL_9;
  s = s + t;

  return s;
}

void sincos_taylor_fp32(float a, out float sin_t, out float cos_t) {
  if (a == 0.0) {
    sin_t = 0.0;
    cos_t = 1.0;
  }
  sin_t = sin_taylor_fp32(a);
  cos_t = sqrt(1.0 - sin_t * sin_t);
}

float tan_taylor_fp32(float a) {
    float sin_a;
    float cos_a;

    if (a == 0.0) {
        return 0.0;
    }

    // 2pi range reduction
    float z = floor(a / TWO_PI);
    float r = a - TWO_PI * z;

    float t;
    float q = floor(r / PI_2 + 0.5);
    int j = int(q);

    if (j < -2 || j > 2) {
        return 0.0 / 0.0;
    }

    t = r - PI_2 * q;

    q = floor(t / PI_16 + 0.5);
    int k = int(q);
    int abs_k = int(abs(float(k)));

    if (abs_k > 4) {
        return 0.0 / 0.0;
    } else {
        t = t - PI_16 * q;
    }

    float u = 0.0;
    float v = 0.0;

    float sin_t, cos_t;
    float s, c;
    sincos_taylor_fp32(t, sin_t, cos_t);

    if (k == 0) {
        s = sin_t;
        c = cos_t;
    } else {
        if (abs(float(abs_k) - 1.0) < 0.5) {
            u = COS_TABLE_0;
            v = SIN_TABLE_0;
        } else if (abs(float(abs_k) - 2.0) < 0.5) {
            u = COS_TABLE_1;
            v = SIN_TABLE_1;
        } else if (abs(float(abs_k) - 3.0) < 0.5) {
            u = COS_TABLE_2;
            v = SIN_TABLE_2;
        } else if (abs(float(abs_k) - 4.0) < 0.5) {
            u = COS_TABLE_3;
            v = SIN_TABLE_3;
        }
        if (k > 0) {
            s = u * sin_t + v * cos_t;
            c = u * cos_t - v * sin_t;
        } else {
            s = u * sin_t - v * cos_t;
            c = u * cos_t + v * sin_t;
        }
    }

    if (j == 0) {
        sin_a = s;
        cos_a = c;
    } else if (j == 1) {
        sin_a = c;
        cos_a = -s;
    } else if (j == -1) {
        sin_a = -c;
        cos_a = s;
    } else {
        sin_a = -s;
        cos_a = -c;
    }
    return sin_a / cos_a;
}
#endif

float tan_fp32(float a) {
#ifdef INTEL_TAN_WORKAROUND
  return tan_taylor_fp32(a);
#else
  return tan(a);
#endif
}

//
// Scaling offsets
//

float project_scale(float meters) {
  if (projectionMode == PROJECT_MERCATOR_OFFSETS) {
    return meters;
  } else {
    return meters * projectionPixelsPerUnit.x;
  }
}

vec2 project_scale(vec2 meters) {
  if (projectionMode == PROJECT_MERCATOR_OFFSETS) {
    return meters;
  } else {
    return vec2(
      meters.x * projectionPixelsPerUnit.x,
      meters.y * projectionPixelsPerUnit.x
    );
  }
}

vec3 project_scale(vec3 meters) {
  if (projectionMode == PROJECT_MERCATOR_OFFSETS) {
    return meters;
  } else {
    return vec3(
      meters.x * projectionPixelsPerUnit.x,
      meters.y * projectionPixelsPerUnit.x,
      meters.z * projectionPixelsPerUnit.x
    );
  }
}

vec4 project_scale(vec4 meters) {
  if (projectionMode == PROJECT_MERCATOR_OFFSETS) {
    return meters;
  } else {
    return vec4(
      meters.x * projectionPixelsPerUnit.x,
      meters.y * projectionPixelsPerUnit.x,
      meters.z * projectionPixelsPerUnit.x,
      meters.w
    );
  }
}

//
// Projecting positions
//

// non-linear projection: lnglats => unit tile [0-1, 0-1]
vec2 project_mercator_(vec2 lnglat) {
  return vec2(
    radians(lnglat.x) + PI,
    PI - log(tan_fp32(PI * 0.25 + radians(lnglat.y) * 0.5))
  );
}

vec2 project_position(vec2 position) {
  if (projectionMode == PROJECT_IDENTITY) {
    return position;
  }
  if (projectionMode == PROJECT_MERCATOR_OFFSETS) {
    return position;
    return project_scale(position);
  }
  // Covers projectionMode == PROJECT_MERCATOR
  return project_mercator_(position) * WORLD_SCALE * projectionScale;
}

vec3 project_position(vec3 position) {
  return vec3(project_position(position.xy), project_scale(position.z));
}

vec4 project_position(vec4 position) {
  return vec4(project_position(position.xyz), position.w);
}

//

vec4 project_to_viewspace(vec4 position) {
  return modelViewMatrix * position;
}

vec4 project_to_clipspace(vec4 position) {
  if (projectionMode == PROJECT_MERCATOR_OFFSETS) {
    position = position * projectionPixelsPerUnit.x;
  }
  return projectionMatrix * position + projectionCenter;
}

// Backwards compatibility

float scale(float position) {
  return project_scale(position);
}

vec2 scale(vec2 position) {
  return project_scale(position);
}

vec3 scale(vec3 position) {
  return project_scale(position);
}

vec4 scale(vec4 position) {
  return project_scale(position);
}

vec2 preproject(vec2 position) {
  return project_position(position);
}

vec3 preproject(vec3 position) {
  return project_position(position);
}

vec4 preproject(vec4 position) {
  return project_position(position);
}

vec4 project(vec4 position) {
  return project_to_clipspace(position);
}
