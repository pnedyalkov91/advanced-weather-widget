// ==========================================================================
// Glue script 2f': the animation's temperature drawn by the graphics chip.
// Far out (the open-data file), drawing tiles on the page's thread costs
// too much once finer regional models lie over the global one: a layer of
// MapLibre's own (type custom) draws one mesh over the world instead, and
// its fragment shader reads the fields from textures. Closer in (the API
// grids) the tiles of TempLayer draw as before; so does everything else
// (legend, readout). Without a working shader, the tiles draw it all.
// The math the shader does is in JavaScript too (fineIdx), for the tests.
// ==========================================================================
WidgetTemp.TempLayerGL = (function () {
  'use strict';
  var Grids = typeof WidgetGrids !== 'undefined' ? WidgetGrids : require('./glue-grids.js');
  var DEG = Math.PI / 180;
  var MESH_X = 256, MESH_Y = 128, MERC_MAX_LAT = 85.0511;
  var ATLAS_MAX_TILES = 36;      // elevation tiles in the view's texture

  // Up to FINE_MAX finer regional models over the temperature, each on its
  // own grid (WidgetGrids): kind 0 latitude/longitude, 1 rotated, 2 Lambert
  // conformal conic, 3 Lambert azimuthal (those two in units of the earth's
  // radius, for the precision of 32-bit floats). Three textures each: the
  // two hours, and the edge weight with the ground height (RG).
  var FINE_MAX = 3, FINE_KIND = { latlon: 0, rotated: 1, lcc: 2, laea: 3 };

  function mercY(lat) { return (1 - Math.log(Math.tan(Math.PI / 4 + lat * DEG / 2)) / Math.PI) / 2; }
  function wrap180(a) { return a - 360 * Math.floor((a + 180) / 360); }

  /** The parameters of a grid's projection for the shader (see fineIdx):
      { kind, P, G } with G the first point and steps, metres over the
      earth's radius for the projected ones. */
  function fineParams(d) {
    var p = d.proj, R = Grids.R, kind = FINE_KIND[d.kind];
    if (kind === 0) return { kind: 0, P: [0, 0, 0, 0], G: [d.x0, d.y0, d.dx, d.dy] };
    if (kind === 1) return { kind: 1, P: [p.ct, p.st, p.cp, p.sp], G: [d.x0, d.y0, d.dx, d.dy] };
    var G = [d.x0 / R, d.y0 / R, d.dx / R, d.dy / R];
    if (kind === 2) return { kind: 2, P: [p.lon0 / DEG, p.n, p.F, p.rho0], G: G };
    return { kind: 3, P: [p.lon0 / DEG, p.s1, p.c1, 0], G: G };
  }

  /** Column and row of lat/lon in grid d as the shader works them out
      (null outside): the same steps, line for line, as fineIdx in FS. */
  function fineIdx(d, lat, lon) {
    var q = fineParams(d), P = q.P, G = q.G, k = q.kind, x, y;
    if (k < 2) {
      x = lon; y = lat;
      if (k === 1) {
        var l = lon * DEG, f = lat * DEG, cx = Math.cos(l) * Math.cos(f), cy = Math.sin(l) * Math.cos(f), cz = Math.sin(f);
        var x2 = P[0] * P[2] * cx + P[0] * P[3] * cy + P[1] * cz;
        var y2 = -P[3] * cx + P[2] * cy;
        var z2 = -P[1] * P[2] * cx - P[1] * P[3] * cy + P[0] * cz;
        x = -Math.atan2(y2, x2) / DEG; y = -Math.asin(Math.max(-1, Math.min(1, z2))) / DEG;
      }
      var mid = G[0] + (d.nx - 1) * G[2] * 0.5;
      x = mid + wrap180(x - mid);
    } else {
      var dl = wrap180(lon - P[0]) * DEG, ff = lat * DEG;
      if (k === 2) {
        var rho = P[2] / Math.pow(Math.tan(Math.PI / 4 + ff / 2), P[1]), th = P[1] * dl;
        x = rho * Math.sin(th); y = P[3] - rho * Math.cos(th);
      } else {
        var sf = Math.sin(ff), cf = Math.cos(ff), cd = Math.cos(dl), kk = Math.sqrt(2 / (1 + P[1] * sf + P[2] * cf * cd));
        x = kk * cf * Math.sin(dl); y = kk * (P[2] * sf - P[1] * cf * cd);
      }
    }
    var c = (x - G[0]) / G[2], r = (y - G[1]) / G[3];
    return c < 0 || r < 0 || c > d.nx - 1 || r > d.ny - 1 ? null : { col: c, row: r };
  }

  var FS_HEAD = [
    '#version 300 es',
    'precision highp float;',
    'in vec2 v_merc;',
    'out vec4 fragColor;',
    'const float PI = 3.141592653589793;',
    'uniform vec2 u_size;',
    // lat/lon of the fragment, and where it falls in a grid of u_size from 90N/180W
    'vec2 gridUv(out float lat) {',
    '  float lon = fract(v_merc.x) * 360.0 - 180.0;',
    '  lat = degrees(atan(sinh(PI * (1.0 - 2.0 * v_merc.y))));',
    '  return vec2((lon + 180.0) / 360.0 * (u_size.x - 1.0) + 0.5, (90.0 - lat) / 180.0 * (u_size.y - 1.0) + 0.5) / u_size;',
    '}'
  ].join('\n') + '\n';

  function fineBlock(k) {
    return [
      '  if (u_fCount > ' + k + '.5) {',
      '    vec2 cr = fineIdx(u_fKind' + k + ', u_fP' + k + ', u_fG' + k + ', u_fS' + k + ', lat, lon);',
      '    if (cr.x >= 0.0) {',
      '      vec2 fuv = (cr + 0.5) / u_fS' + k + ';',
      '      vec2 wz = texture(u_fwz' + k + ', fuv).rg;',
      '      float w = wz.r * u_fFade' + k + ';',
      '      if (w > 0.0) {',
      '        t = mix(t, mix(texture(u_fa' + k + ', fuv).r, texture(u_fb' + k + ', fuv).r, u_fMix' + k + '), w);',
      '        if (u_fHasHs' + k + ' > 0.5) zs = mix(zs, wz.g, w);',
      '      }',
      '    }',
      '  }'
    ].join('\n');
  }
  var fineUniforms = [], fineBlocks = [];
  for (var fk = 0; fk < FINE_MAX; fk++) {
    fineUniforms.push('uniform sampler2D u_fa' + fk + ', u_fb' + fk + ', u_fwz' + fk + ';',
      'uniform float u_fKind' + fk + ', u_fMix' + fk + ', u_fFade' + fk + ', u_fHasHs' + fk + ';',
      'uniform vec4 u_fP' + fk + ', u_fG' + fk + ';', 'uniform vec2 u_fS' + fk + ';');
  }
  // The coarsest of them first, the finest last: each over those before.
  for (fk = FINE_MAX - 1; fk >= 0; fk--) fineBlocks.push(fineBlock(fk));

  // The temperature as the tiles draw it: the field at the model's ground,
  // brought to the height of the place at 6.5 °C per km, then the color of
  // its band from the same table (one color every 0.1 °C).
  var TEMP_FS = FS_HEAD + [
    'uniform sampler2D u_a, u_b, u_hs, u_dem, u_lut;',
    'uniform float u_mix, u_opacity, u_hasHs, u_hasDem, u_lutMin, u_lutStep, u_lutSize, u_fCount;',
    'uniform vec4 u_rect;'
  ].concat(fineUniforms, [
    'float wrap180(float a) { return a - 360.0 * floor((a + 180.0) / 360.0); }',
    // Column and row of lat/lon in a grid of kind k, its projection P, its
    // first point and steps G, its size S; (-1, -1) outside it.
    'vec2 fineIdx(float k, vec4 P, vec4 G, vec2 S, float lat, float lon) {',
    '  float x, y;',
    '  if (k < 1.5) {',
    '    x = lon; y = lat;',
    '    if (k > 0.5) {',
    '      float l = radians(lon), f = radians(lat);',
    '      vec3 c = vec3(cos(l) * cos(f), sin(l) * cos(f), sin(f));',
    '      float x2 = P.x * P.z * c.x + P.x * P.w * c.y + P.y * c.z;',
    '      float y2 = -P.w * c.x + P.z * c.y;',
    '      float z2 = -P.y * P.z * c.x - P.y * P.w * c.y + P.x * c.z;',
    '      x = -degrees(atan(y2, x2)); y = -degrees(asin(clamp(z2, -1.0, 1.0)));',
    '    }',
    '    float mid = G.x + (S.x - 1.0) * G.z * 0.5;',
    '    x = mid + wrap180(x - mid);',
    '  } else {',
    '    float dl = radians(wrap180(lon - P.x)), f = radians(lat);',
    '    if (k < 2.5) {',
    '      float rho = P.z / pow(tan(PI / 4.0 + f / 2.0), P.y), th = P.y * dl;',
    '      x = rho * sin(th); y = P.w - rho * cos(th);',
    '    } else {',
    '      float sf = sin(f), cf = cos(f), cd = cos(dl);',
    '      float kk = sqrt(2.0 / (1.0 + P.y * sf + P.z * cf * cd));',
    '      x = kk * cf * sin(dl); y = kk * (P.z * sf - P.y * cf * cd);',
    '    }',
    '  }',
    '  vec2 cr = vec2((x - G.x) / G.z, (y - G.y) / G.w);',
    '  if (cr.x < 0.0 || cr.y < 0.0 || cr.x > S.x - 1.0 || cr.y > S.y - 1.0) return vec2(-1.0);',
    '  return cr;',
    '}',
    'void main() {',
    '  float lat; vec2 uv = gridUv(lat);',
    '  float lon = fract(v_merc.x) * 360.0 - 180.0;',
    '  float t = mix(texture(u_a, uv).r, texture(u_b, uv).r, u_mix);',
    '  float zs = u_hasHs > 0.5 ? texture(u_hs, uv).r : 0.0;'
  ], fineBlocks, [
    '  if (u_hasHs > 0.5 && u_hasDem > 0.5) {',
    '    float ax = v_merc.x;',
    '    if (ax < u_rect.x) ax += 1.0; else if (ax >= u_rect.z) ax -= 1.0;',
    '    vec2 duv = vec2((ax - u_rect.x) / (u_rect.z - u_rect.x), (v_merc.y - u_rect.y) / (u_rect.w - u_rect.y));',
    '    if (duv.x >= 0.0 && duv.x <= 1.0 && duv.y >= 0.0 && duv.y <= 1.0) {',
    '      float zp = texture(u_dem, duv).r;',
    '      if (zp > -1000.0) t += 0.0065 * (zs - max(0.0, zp));',
    '    }',
    '  }',
    '  float i = clamp(floor((t - u_lutMin) / u_lutStep + 0.5), 0.0, u_lutSize - 1.0);',
    '  fragColor = vec4(texelFetch(u_lut, ivec2(int(i), 0), 0).rgb * u_opacity, u_opacity);',
    '}'
  ]).join('\n');

  /** A custom layer drawing one mesh over the world, Mercator 0..1, fine
      enough to follow the globe, with a row on each side reaching the
      pole, colored by fragment shader fs; draw(gl, u, layer) binds its
      textures and uniforms and says whether there is anything to draw.
      Textures are uploaded in render(), where MapLibre expects the GL
      state to change, and kept while in use. onFail() is called once if
      the shader does not build. timings: { upload: [], render: [] } to
      keep the last times in ms (the pressure's window.presStats).
      Shared by every layer drawn by the chip (WidgetPressure.GLLayer). */
  function GLLayer(id, fs, draw) {
    this.id = id;
    this.type = 'custom';
    this.renderingMode = '2d';
    this.fs = fs;
    this.draw = draw;
    this.programs = {};
    this.drawn = -1;
    this.fade = 1;                    // 0..1 over the opacity (fading in or out)
    this.textures = new Map();        // data array -> { tex, used }
    this.frame = 0;
    this.failed = false;
    this.onFail = null;
    this.timings = null;
  }
  function note(list, ms) { list.push(ms); if (list.length > 40) list.shift(); }
  GLLayer.prototype = {
    onAdd: function (map, gl) {
      this.map = map;
      // x, y in Mercator (0..1) and the pole flag: the rows past the edges
      // reach the poles on the globe (as MapLibre's own tiles do) with the
      // colors of the edge; flat they are not drawn.
      var v = [];
      for (var j = -1; j <= MESH_Y + 1; j++) {
        var jj = Math.max(0, Math.min(MESH_Y, j));
        var y = mercY(MERC_MAX_LAT) + (mercY(-MERC_MAX_LAT) - mercY(MERC_MAX_LAT)) * jj / MESH_Y;
        for (var i = 0; i <= MESH_X; i++) v.push(i / MESH_X, y, j < 0 ? -1 : j > MESH_Y ? 1 : 0);
      }
      var idx = [];
      for (j = 0; j < MESH_Y + 2; j++) {
        for (i = 0; i < MESH_X; i++) {
          var k = j * (MESH_X + 1) + i;
          idx.push(k, k + 1, k + MESH_X + 1, k + 1, k + MESH_X + 2, k + MESH_X + 1);
        }
      }
      this.vbo = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(v), gl.STATIC_DRAW);
      this.ibo = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint32Array(idx), gl.STATIC_DRAW);
      this.count = idx.length;
    },
    onRemove: function (map, gl) {
      var self = this;
      this.textures.forEach(function (t) { gl.deleteTexture(t.tex); });
      this.textures.clear();
      Object.keys(this.programs).forEach(function (k) {
        var pr = self.programs[k];
        if (pr) { gl.deleteProgram(pr.p); gl.deleteVertexArray(pr.vao); }
      });
      gl.deleteBuffer(this.vbo);
      gl.deleteBuffer(this.ibo);
      // Made again by onAdd and program() if the layer is put back (new base map).
      this.programs = {};
      this.drawn = -1;
    },
    /** The program for MapLibre's projection variant (flat or globe), made
        once; null when it does not build. */
    program: function (gl, sd) {
      if (sd.variantName in this.programs) return this.programs[sd.variantName];
      var vs = '#version 300 es\n' + sd.vertexShaderPrelude + '\n' + sd.define + '\n' +
        'in vec3 a_pos;\nuniform float u_shift;\nout vec2 v_merc;\n' +
        'void main() {\n' +
        '  v_merc = vec2(a_pos.x + u_shift, a_pos.y);\n' +
        '  vec2 raw = vec2(0.0, a_pos.z < -0.5 ? -32768.0 : (a_pos.z > 0.5 ? 32767.0 : 0.0));\n' +
        '  gl_Position = projectTile(v_merc, raw);\n' +
        '}';
      var ok = true, self = this;
      function sh(type, src) {
        var s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { ok = false; console.warn('[gl] ' + self.id + ' shader: ' + gl.getShaderInfoLog(s)); }
        return s;
      }
      var p = gl.createProgram(), v = sh(gl.VERTEX_SHADER, vs), f = sh(gl.FRAGMENT_SHADER, this.fs);
      gl.attachShader(p, v);
      gl.attachShader(p, f);
      gl.linkProgram(p);
      gl.deleteShader(v);
      gl.deleteShader(f);
      if (!ok || !gl.getProgramParameter(p, gl.LINK_STATUS)) {
        console.warn('[gl] ' + self.id + ' link: ' + gl.getProgramInfoLog(p));
        gl.deleteProgram(p);
        return (this.programs[sd.variantName] = null);
      }
      var loc = {}, n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
      for (var i = 0; i < n; i++) {
        var name = gl.getActiveUniform(p, i).name.replace(/\[0\]$/, '');
        loc[name] = gl.getUniformLocation(p, name);
      }
      var vao = gl.createVertexArray();
      gl.bindVertexArray(vao);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.vbo);
      var ap = gl.getAttribLocation(p, 'a_pos');
      gl.enableVertexAttribArray(ap);
      gl.vertexAttribPointer(ap, 3, gl.FLOAT, false, 0, 0);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, this.ibo);
      gl.bindVertexArray(null);
      return (this.programs[sd.variantName] = { p: p, loc: loc, vao: vao });
    },
    /** The texture of a data array (made once): R16F floats, RG16F pairs
        ('rg'), R8 bytes ('r8'), or RGBA8 bytes ('rgba', 'rgba-nearest').
        unit: the texture unit it is bound to. */
    texture: function (gl, unit, data, w, h, kind) {
      var hit = this.textures.get(data);
      // The unit first: a new texture is bound to make it, and bound on the
      // unit still active it would take the place of the one before.
      gl.activeTexture(gl.TEXTURE0 + unit);
      if (!hit) {
        var t0 = this.timings ? performance.now() : 0, tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
        gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
        var filter = kind === 'rgba-nearest' ? gl.NEAREST : gl.LINEAR;
        if (kind === 'rgba' || kind === 'rgba-nearest') gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, w, h, 0, gl.RGBA, gl.UNSIGNED_BYTE, data);
        else if (kind === 'r8') gl.texImage2D(gl.TEXTURE_2D, 0, gl.R8, w, h, 0, gl.RED, gl.UNSIGNED_BYTE, data);
        else if (kind === 'rg') gl.texImage2D(gl.TEXTURE_2D, 0, gl.RG16F, w, h, 0, gl.RG, gl.FLOAT, data);
        else gl.texImage2D(gl.TEXTURE_2D, 0, gl.R16F, w, h, 0, gl.RED, gl.FLOAT, data);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        hit = { tex: tex, used: 0 };
        this.textures.set(data, hit);
        if (this.timings) note(this.timings.upload, performance.now() - t0);
      }
      hit.used = this.frame;
      gl.bindTexture(gl.TEXTURE_2D, hit.tex);
      return hit.tex;
    },
    /** Drop the textures no draw has used for a few frames. */
    _sweep: function (gl) {
      var self = this;
      if (this.textures.size <= 6) return;
      this.textures.forEach(function (t, key) {
        if (self.frame - t.used > 2) { gl.deleteTexture(t.tex); self.textures.delete(key); }
      });
    },
    render: function (gl, args) {
      if (this.failed) return;
      var t0 = this.timings ? performance.now() : 0, sd = args.shaderData, pr = this.program(gl, sd), d = args.defaultProjectionData;
      if (!pr) {
        this.failed = true;
        if (this.onFail) this.onFail();
        return;
      }
      var u = pr.loc;
      this.frame++;
      gl.useProgram(pr.p);
      if (!this.draw(gl, u, this)) return;
      gl.uniformMatrix4fv(u.u_projection_matrix, false, d.mainMatrix);
      if (u.u_projection_fallback_matrix) gl.uniformMatrix4fv(u.u_projection_fallback_matrix, false, d.fallbackMatrix);
      if (u.u_projection_tile_mercator_coords) gl.uniform4fv(u.u_projection_tile_mercator_coords, d.tileMercatorCoords);
      if (u.u_projection_clipping_plane) gl.uniform4fv(u.u_projection_clipping_plane, d.clippingPlane);
      if (u.u_projection_transition) gl.uniform1f(u.u_projection_transition, d.projectionTransition);
      gl.enable(gl.BLEND);
      gl.blendFunc(gl.ONE, gl.ONE_MINUS_SRC_ALPHA);
      gl.disable(gl.DEPTH_TEST);
      gl.disable(gl.STENCIL_TEST);
      gl.disable(gl.CULL_FACE);
      gl.bindVertexArray(pr.vao);
      // Flat, the copies of the world on either side; on the globe one is all.
      var shifts = sd.variantName === 'globe' ? [0] : [-1, 0, 1];
      for (var k = 0; k < shifts.length; k++) {
        gl.uniform1f(u.u_shift, shifts[k]);
        gl.drawElements(gl.TRIANGLES, this.count, gl.UNSIGNED_INT, 0);
      }
      gl.bindVertexArray(null);
      this._sweep(gl);
      if (this.timings) note(this.timings.render, performance.now() - t0);
    }
  };

  /** A palette of RGB triplets as RGBA bytes, made once per palette. */
  var rgbaOf = new WeakMap();
  function rgba(rgb) {
    var hit = rgbaOf.get(rgb);
    if (hit) return hit;
    var n = rgb.length / 3, out = new Uint8Array(n * 4);
    for (var i = 0; i < n; i++) { out[i * 4] = rgb[i * 3]; out[i * 4 + 1] = rgb[i * 3 + 1]; out[i * 4 + 2] = rgb[i * 3 + 2]; out[i * 4 + 3] = 255; }
    rgbaOf.set(rgb, out);
    return out;
  }

  // Missing values as 0 for the chip (its linear filter would spread NaN);
  // the weights are 0 there, so they count for nothing. One copy per array.
  var noNaN = new WeakMap();
  function clean(a) {
    var c = noNaN.get(a);
    if (!c) {
      c = new Float32Array(a.length);
      for (var i = 0; i < a.length; i++) c[i] = a[i] === a[i] ? a[i] : 0;
      noNaN.set(a, c);
    }
    return c;
  }

  // A model's edge weights and ground height in one two-channel texture,
  // made once per weights (again when the height comes in).
  var weightsZ = new WeakMap();
  function packWZ(weights, elev) {
    var hit = weightsZ.get(weights);
    if (hit && hit.elev === elev) return hit.data;
    var data = new Float32Array(weights.length * 2);
    for (var i = 0; i < weights.length; i++) {
      var w = weights[i], z = elev ? elev[i] : 0;
      data[2 * i] = w === w ? w : 0;
      data[2 * i + 1] = z === z ? z : 0;
    }
    weightsZ.set(weights, { elev: elev, data: data });
    return data;
  }

  /** Whether the chip can draw these fields: the file last, before it at
      most FINE_MAX finer models on a grid it knows. */
  function drawable(fields) {
    var f = fields[fields.length - 1], fines = fields.slice(0, -1);
    return !!(f && f.grid && f.grid.lats && f.values) && fines.length <= FINE_MAX && fines.every(function (x) {
      return x.weights && x.grid && x.grid.desc && FINE_KIND[x.grid.desc.kind] != null;
    });
  }

  function tempDraw(gl, u, layer) {
    var o = layer.owner, fields = o._gpuOn && o._shown && o._shown.fields;
    if (!fields) return false;
    var f = fields[fields.length - 1], fines = fields.slice(0, -1);
    gl.uniform1f(u.u_fCount, fines.length);
    fines.forEach(function (fine, k) {
      var fd = fine.grid.desc, fc = fd.nx, fr = fd.ny, q = fineParams(fd), unit = 5 + 3 * k;
      layer.texture(gl, unit, clean(fine.values), fc, fr); gl.uniform1i(u['u_fa' + k], unit);
      layer.texture(gl, unit + 1, clean(fine.valuesB || fine.values), fc, fr); gl.uniform1i(u['u_fb' + k], unit + 1);
      layer.texture(gl, unit + 2, packWZ(fine.weights, fine.elev), fc, fr, 'rg'); gl.uniform1i(u['u_fwz' + k], unit + 2);
      gl.uniform1f(u['u_fKind' + k], q.kind);
      gl.uniform4fv(u['u_fP' + k], q.P);
      gl.uniform4fv(u['u_fG' + k], q.G);
      gl.uniform2f(u['u_fS' + k], fc, fr);
      gl.uniform1f(u['u_fHasHs' + k], fine.elev ? 1 : 0);
      gl.uniform1f(u['u_fMix' + k], fine.valuesB ? fine.mix || 0 : 0);
      gl.uniform1f(u['u_fFade' + k], fine.fade == null ? 1 : fine.fade);
    });
    var cols = f.grid.lons.length, rows = f.grid.lats.length;
    layer.texture(gl, 0, f.values, cols, rows); gl.uniform1i(u.u_a, 0);
    layer.texture(gl, 1, f.valuesB || f.values, cols, rows); gl.uniform1i(u.u_b, 1);
    layer.texture(gl, 2, rgba(o._lut), WidgetTemp.LUT_SIZE, 1, 'rgba-nearest'); gl.uniform1i(u.u_lut, 2);
    var at = o._atlas;
    gl.uniform1f(u.u_hasHs, f.elev ? 1 : 0);
    gl.uniform1f(u.u_hasDem, at ? 1 : 0);
    if (f.elev) { layer.texture(gl, 3, f.elev, cols, rows); gl.uniform1i(u.u_hs, 3); }
    if (at) {
      layer.texture(gl, 4, at.data, at.w, at.h); gl.uniform1i(u.u_dem, 4);
      gl.uniform4fv(u.u_rect, at.rect);
    }
    gl.uniform2f(u.u_size, cols, rows);
    gl.uniform1f(u.u_mix, f.valuesB ? f.mix || 0 : 0);
    gl.uniform1f(u.u_opacity, o.options.opacity / 100 * layer.fade);
    gl.uniform1f(u.u_lutMin, WidgetTemp.LUT_MIN - o._shift);   // the colors read at t + shift
    gl.uniform1f(u.u_lutStep, WidgetTemp.LUT_STEP);
    gl.uniform1f(u.u_lutSize, WidgetTemp.LUT_SIZE);
    layer.drawn = o._gpuVersion;
    return true;
  }

  var TempLayer = WidgetTemp.TempLayer;

  function TempLayerGL(adapter, source, open, dem, options) {
    TempLayer.call(this, adapter, source, open, dem, options);
    var self = this;
    this._gl = new GLLayer('lv-temp-gl', TEMP_FS, tempDraw);
    this._gl.owner = this;
    // No shader: the tiles draw the file too, from now on.
    this._gl.onFail = function () {
      setTimeout(function () {
        if (!self._gpuOn || !self._shown) return;
        var fields = self._shown.fields;
        self._gpuOn = false;
        self._shown = null;
        self._adapter.setLines('temperature-gl', false);
        TempLayer.prototype._show.call(self, fields, true);
      }, 0);
    };
    this._gpuOn = false;
    this._gpuVersion = 0;
    this._atlas = null;
    this._atlasToken = 0;
  }
  TempLayerGL.prototype = Object.create(TempLayer.prototype);
  TempLayerGL.prototype.constructor = TempLayerGL;

  TempLayerGL.prototype.addTo = function (map) {
    var self = this;
    TempLayer.prototype.addTo.call(this, map);
    this._adapter.addLayer(this._gl);
    this._onAtlas = function () { self._buildAtlas(); };
    map.on('moveend', this._onAtlas);
    this._buildAtlas();
    return this;
  };
  TempLayerGL.prototype.remove = function () {
    var map = this._map;
    if (map) {
      map.off('moveend', this._onAtlas);
      if (map.getLayer('lv-temp-gl')) map.removeLayer('lv-temp-gl');
    }
    if (this._gpuOn) this._adapter.setLines('temperature-gl', false);
    this._gpuOn = false;
    this._atlas = null;
    this._atlasToken++;
    TempLayer.prototype.remove.call(this);
  };
  /** The file far out goes to the chip; anything else to the tiles. */
  TempLayerGL.prototype._show = function (fields, force) {
    if (this._mode === 'file' && !this._gl.failed && drawable(fields)) {
      this._shown = { fields: fields, lut: this._lut, step: 1 };
      if (!this._gpuOn) {
        // The chip's own claim on the coasts and borders: clearing the
        // tiles drops theirs.
        this._adapter.clearTemp();
        this._adapter.setLines('temperature-gl', true);
        this._gpuOn = true;
      }
      this._gpuVersion++;
      this._map.triggerRepaint();
      return;
    }
    if (this._gpuOn) {
      this._gpuOn = false;
      this._shown = null;
      this._adapter.setLines('temperature-gl', false);
      this._map.triggerRepaint();
    }
    TempLayer.prototype._show.call(this, fields, force);
  };
  /** Put back after a new base map, at its place. */
  TempLayerGL.prototype.restyle = function () {
    if (this._map && !this._map.getLayer(this._gl.id)) this._adapter.addLayer(this._gl);
  };
  TempLayerGL.prototype.settled = function () {
    return this._gpuOn ? this._gl.drawn === this._gpuVersion : TempLayer.prototype.settled.call(this);
  };
  /** The elevation of the view in one texture, at the zoom the tiles would
      read it at (fewer tiles when the view needs more than 36). */
  TempLayerGL.prototype._buildAtlas = function () {
    var self = this, map = this._map, dem = this._dem;
    if (!map || !dem) return;
    var token = ++this._atlasToken;
    var z = Math.max(0, Math.min(12, Math.round(map.getZoom())));
    var b = map.getBounds(), w = b.getWest(), e = b.getEast();
    var n = Math.min(MERC_MAX_LAT, b.getNorth()), s = Math.max(-MERC_MAX_LAT, b.getSouth());
    var x0, x1, y0, y1, N;
    for (;;) {
      N = Math.pow(2, z);
      if (e - w >= 360) { x0 = 0; x1 = N - 1; } else { x0 = Math.floor((w + 180) / 360 * N); x1 = Math.floor((e + 180) / 360 * N); }
      y0 = Math.max(0, Math.floor(mercY(n) * N)); y1 = Math.min(N - 1, Math.floor(mercY(s) * N));
      if ((x1 - x0 + 1) * (y1 - y0 + 1) <= ATLAS_MAX_TILES || z === 0) break;
      z--;
    }
    var wrap = function (x) { return ((x % N) + N) % N; }, jobs = [];
    for (var ty = y0; ty <= y1; ty++) for (var tx = x0; tx <= x1; tx++) jobs.push(dem.ensureTile(z, wrap(tx), ty));
    Promise.all(jobs).then(function () {
      if (token !== self._atlasToken || !self._map) return;
      var cols = x1 - x0 + 1, rows = y1 - y0 + 1, W = cols * 256, data = new Float32Array(W * rows * 256);
      for (var ty = y0; ty <= y1; ty++) {
        for (var tx = x0; tx <= x1; tx++) {
          var t = dem.tileData(z, wrap(tx), ty), ox = (tx - x0) * 256, oy = (ty - y0) * 256;
          for (var r = 0; r < 256; r++) {
            var dst = (oy + r) * W + ox;
            if (t) data.set(t.subarray(r * 256, r * 256 + 256), dst);
            else data.fill(-9999, dst, dst + 256);       // unknown: no correction there
          }
        }
      }
      self._atlas = { data: data, w: W, h: rows * 256, rect: [x0 / N, y0 / N, (x1 + 1) / N, (y1 + 1) / N], z: z };
      if (self._gpuOn) { self._gpuVersion++; self._map.triggerRepaint(); }
    });
  };
  TempLayerGL.prototype.setFade = function (f) {
    TempLayer.prototype.setFade.call(this, f);
    this._gl.fade = this._fade;
    if (this._map) this._map.triggerRepaint();
  };
  TempLayerGL.prototype.setOpacity = function (percent) {
    TempLayer.prototype.setOpacity.call(this, percent);
    if (this._map) this._map.triggerRepaint();
  };

  TempLayerGL.FINE_MAX = FINE_MAX;
  TempLayerGL.fineParams = fineParams;
  TempLayerGL.fineIdx = fineIdx;
  TempLayerGL.drawable = drawable;
  TempLayerGL.packWZ = packWZ;
  TempLayerGL.clean = clean;
  TempLayerGL.GLLayer = GLLayer;
  TempLayerGL.FS_HEAD = FS_HEAD;
  TempLayerGL.rgba = rgba;
  return TempLayerGL;
})();
