#include <flutter/runtime_effect.glsl>

// Uniform layout (setFloat indices):
//  0,1    : uDstOrigin       (vec2 — destination rect top-left in canvas space)
//  2,3    : uImgSize0        (vec2 — texture 0 dimensions in pixels)
//  4,5    : uImgSize1        (vec2 — texture 1 dimensions in pixels)
//  6,7    : uImgSize2        (vec2 — texture 2 dimensions in pixels)
//  8,9    : uImgSize3        (vec2 — texture 3 dimensions in pixels)
//  10-15  : uXDst[6]         (cumulative x offsets within dest rect; [0]=0, [cols]=total width)
//  16-21  : uYDst[6]         (cumulative y offsets within dest rect)
//  22-27  : uXSrc[6]         (cumulative column widths in source pixels)
//  28-33  : uYSrc[6]         (cumulative row heights in source pixels)
//  34     : uColCount         (number of columns, 1–5)
//  35     : uRowCount         (number of rows, 1–5)
//  36-60  : uCellModes[25]    (per-cell mode, row-major; see modes below)
//  61-85  : uCellAlignX[25]   (per-cell alignment.x in [-1, 1])
//  86-110 : uCellAlignY[25]   (per-cell alignment.y in [-1, 1])
//  111-135: uCellSrcX[25]     (per-cell absolute srcRect.left in texture pixels)
//  136-160: uCellSrcY[25]     (per-cell absolute srcRect.top in texture pixels)
//  161-185: uCellTex[25]      (per-cell texture index 0–3)
// Samplers (setImageSampler index):
//  0: uTexture0
//  1: uTexture1
//  2: uTexture2
//  3: uTexture3
//
// Cell modes:
//  0 = Stretch  — non-uniform scale to fill the cell exactly
//  1 = Tile     — repeat the src cell pattern across the dst cell
//  2 = Cover    — uniform scale to fill, crop src if aspect ratios differ
//  3 = Contain  — uniform scale to fit inside, letterbox outside
//  4 = Fixed    — draw at original pixel size, aligned; transparent outside

uniform sampler2D uTexture0;
uniform sampler2D uTexture1;
uniform sampler2D uTexture2;
uniform sampler2D uTexture3;
uniform vec2 uDstOrigin;
uniform vec2 uImgSize0;
uniform vec2 uImgSize1;
uniform vec2 uImgSize2;
uniform vec2 uImgSize3;
uniform float uXDst[6];
uniform float uYDst[6];
uniform float uXSrc[6];
uniform float uYSrc[6];
uniform float uColCount;
uniform float uRowCount;
uniform float uCellModes[25];
uniform float uCellAlignX[25];
uniform float uCellAlignY[25];
uniform float uCellSrcX[25];
uniform float uCellSrcY[25];
uniform float uCellTex[25];

out vec4 fragColor;

// SkSL requires constant array indices. These helpers simulate dynamic access
// via if-else chains so every actual bracket index is a compile-time constant.

float _get6(float a0, float a1, float a2, float a3, float a4, float a5, int i) {
    if (i == 1) return a1;
    if (i == 2) return a2;
    if (i == 3) return a3;
    if (i == 4) return a4;
    if (i == 5) return a5;
    return a0;
}

float _xDst(int i) { return _get6(uXDst[0], uXDst[1], uXDst[2], uXDst[3], uXDst[4], uXDst[5], i); }
float _yDst(int i) { return _get6(uYDst[0], uYDst[1], uYDst[2], uYDst[3], uYDst[4], uYDst[5], i); }
float _xSrc(int i) { return _get6(uXSrc[0], uXSrc[1], uXSrc[2], uXSrc[3], uXSrc[4], uXSrc[5], i); }
float _ySrc(int i) { return _get6(uYSrc[0], uYSrc[1], uYSrc[2], uYSrc[3], uYSrc[4], uYSrc[5], i); }

float _get5(float a0, float a1, float a2, float a3, float a4, int col) {
    if (col == 1) return a1;
    if (col == 2) return a2;
    if (col == 3) return a3;
    if (col == 4) return a4;
    return a0;
}

float _cellMode(int row, int col) {
    if (row == 1) return _get5(uCellModes[5],  uCellModes[6],  uCellModes[7],  uCellModes[8],  uCellModes[9],  col);
    if (row == 2) return _get5(uCellModes[10], uCellModes[11], uCellModes[12], uCellModes[13], uCellModes[14], col);
    if (row == 3) return _get5(uCellModes[15], uCellModes[16], uCellModes[17], uCellModes[18], uCellModes[19], col);
    if (row == 4) return _get5(uCellModes[20], uCellModes[21], uCellModes[22], uCellModes[23], uCellModes[24], col);
    return             _get5(uCellModes[0],  uCellModes[1],  uCellModes[2],  uCellModes[3],  uCellModes[4],  col);
}

float _cellAlignX(int row, int col) {
    if (row == 1) return _get5(uCellAlignX[5],  uCellAlignX[6],  uCellAlignX[7],  uCellAlignX[8],  uCellAlignX[9],  col);
    if (row == 2) return _get5(uCellAlignX[10], uCellAlignX[11], uCellAlignX[12], uCellAlignX[13], uCellAlignX[14], col);
    if (row == 3) return _get5(uCellAlignX[15], uCellAlignX[16], uCellAlignX[17], uCellAlignX[18], uCellAlignX[19], col);
    if (row == 4) return _get5(uCellAlignX[20], uCellAlignX[21], uCellAlignX[22], uCellAlignX[23], uCellAlignX[24], col);
    return              _get5(uCellAlignX[0],  uCellAlignX[1],  uCellAlignX[2],  uCellAlignX[3],  uCellAlignX[4],  col);
}

float _cellAlignY(int row, int col) {
    if (row == 1) return _get5(uCellAlignY[5],  uCellAlignY[6],  uCellAlignY[7],  uCellAlignY[8],  uCellAlignY[9],  col);
    if (row == 2) return _get5(uCellAlignY[10], uCellAlignY[11], uCellAlignY[12], uCellAlignY[13], uCellAlignY[14], col);
    if (row == 3) return _get5(uCellAlignY[15], uCellAlignY[16], uCellAlignY[17], uCellAlignY[18], uCellAlignY[19], col);
    if (row == 4) return _get5(uCellAlignY[20], uCellAlignY[21], uCellAlignY[22], uCellAlignY[23], uCellAlignY[24], col);
    return              _get5(uCellAlignY[0],  uCellAlignY[1],  uCellAlignY[2],  uCellAlignY[3],  uCellAlignY[4],  col);
}

float _cellSrcX(int row, int col) {
    if (row == 1) return _get5(uCellSrcX[5],  uCellSrcX[6],  uCellSrcX[7],  uCellSrcX[8],  uCellSrcX[9],  col);
    if (row == 2) return _get5(uCellSrcX[10], uCellSrcX[11], uCellSrcX[12], uCellSrcX[13], uCellSrcX[14], col);
    if (row == 3) return _get5(uCellSrcX[15], uCellSrcX[16], uCellSrcX[17], uCellSrcX[18], uCellSrcX[19], col);
    if (row == 4) return _get5(uCellSrcX[20], uCellSrcX[21], uCellSrcX[22], uCellSrcX[23], uCellSrcX[24], col);
    return              _get5(uCellSrcX[0],  uCellSrcX[1],  uCellSrcX[2],  uCellSrcX[3],  uCellSrcX[4],  col);
}

float _cellSrcY(int row, int col) {
    if (row == 1) return _get5(uCellSrcY[5],  uCellSrcY[6],  uCellSrcY[7],  uCellSrcY[8],  uCellSrcY[9],  col);
    if (row == 2) return _get5(uCellSrcY[10], uCellSrcY[11], uCellSrcY[12], uCellSrcY[13], uCellSrcY[14], col);
    if (row == 3) return _get5(uCellSrcY[15], uCellSrcY[16], uCellSrcY[17], uCellSrcY[18], uCellSrcY[19], col);
    if (row == 4) return _get5(uCellSrcY[20], uCellSrcY[21], uCellSrcY[22], uCellSrcY[23], uCellSrcY[24], col);
    return              _get5(uCellSrcY[0],  uCellSrcY[1],  uCellSrcY[2],  uCellSrcY[3],  uCellSrcY[4],  col);
}

float _cellTex(int row, int col) {
    if (row == 1) return _get5(uCellTex[5],  uCellTex[6],  uCellTex[7],  uCellTex[8],  uCellTex[9],  col);
    if (row == 2) return _get5(uCellTex[10], uCellTex[11], uCellTex[12], uCellTex[13], uCellTex[14], col);
    if (row == 3) return _get5(uCellTex[15], uCellTex[16], uCellTex[17], uCellTex[18], uCellTex[19], col);
    if (row == 4) return _get5(uCellTex[20], uCellTex[21], uCellTex[22], uCellTex[23], uCellTex[24], col);
    return              _get5(uCellTex[0],  uCellTex[1],  uCellTex[2],  uCellTex[3],  uCellTex[4],  col);
}

vec2 _imgSize(int idx) {
    if (idx == 1) return uImgSize1;
    if (idx == 2) return uImgSize2;
    if (idx == 3) return uImgSize3;
    return uImgSize0;
}

vec4 sampleTex(int idx, vec2 uv) {
    if (idx == 1) return texture(uTexture1, uv);
    if (idx == 2) return texture(uTexture2, uv);
    if (idx == 3) return texture(uTexture3, uv);
    return texture(uTexture0, uv);
}

void main() {
    vec2 pos = FlutterFragCoord().xy - uDstOrigin;

    int cols = int(uColCount);
    int rows = int(uRowCount);

    int col = cols - 1;
    for (int c = 0; c < 5; c++) {
        if (c >= cols) break;
        if (pos.x < _xDst(c + 1)) { col = c; break; }
    }

    int row = rows - 1;
    for (int r = 0; r < 5; r++) {
        if (r >= rows) break;
        if (pos.y < _yDst(r + 1)) { row = r; break; }
    }

    float localX   = pos.x - _xDst(col);
    float localY   = pos.y - _yDst(row);
    float dstCellW = _xDst(col + 1) - _xDst(col);
    float dstCellH = _yDst(row + 1) - _yDst(row);
    float srcCellW = _xSrc(col + 1) - _xSrc(col);
    float srcCellH = _ySrc(row + 1) - _ySrc(row);

    // Per-cell texture info.
    int   texIdx  = int(_cellTex(row, col));
    vec2  imgSize = _imgSize(texIdx);
    float sampleX = _cellSrcX(row, col);
    float sampleY = _cellSrcY(row, col);

    if (dstCellW > 0.0 && dstCellH > 0.0 && srcCellW > 0.0 && srcCellH > 0.0) {
        float mode   = _cellMode(row, col);
        float alignX = _cellAlignX(row, col);
        float alignY = _cellAlignY(row, col);

        if (mode < 0.5) {
            // Stretch: non-uniform scale to fill dst cell exactly.
            sampleX += (localX / dstCellW) * srcCellW;
            sampleY += (localY / dstCellH) * srcCellH;

        } else if (mode < 1.5) {
            // Tile: repeat the src cell pattern across the dst cell.
            sampleX += mod(localX, srcCellW);
            sampleY += mod(localY, srcCellH);

        } else if (mode < 2.5) {
            // Cover: uniform scale to fill dst, aligning the cropped src region.
            float scale    = max(dstCellW / srcCellW, dstCellH / srcCellH);
            float visibleW = dstCellW / scale;
            float visibleH = dstCellH / scale;
            float srcOffX  = (srcCellW - visibleW) * (alignX + 1.0) * 0.5;
            float srcOffY  = (srcCellH - visibleH) * (alignY + 1.0) * 0.5;
            sampleX += srcOffX + (localX / dstCellW) * visibleW;
            sampleY += srcOffY + (localY / dstCellH) * visibleH;

        } else if (mode < 3.5) {
            // Contain: uniform scale to fit inside dst, transparent in the letterbox.
            float scale      = min(dstCellW / srcCellW, dstCellH / srcCellH);
            float fittedDstW = srcCellW * scale;
            float fittedDstH = srcCellH * scale;
            float dstOffX    = (dstCellW - fittedDstW) * (alignX + 1.0) * 0.5;
            float dstOffY    = (dstCellH - fittedDstH) * (alignY + 1.0) * 0.5;
            float adjX = localX - dstOffX;
            float adjY = localY - dstOffY;
            if (adjX < 0.0 || adjX >= fittedDstW || adjY < 0.0 || adjY >= fittedDstH) {
                fragColor = vec4(0.0);
                return;
            }
            sampleX += (adjX / fittedDstW) * srcCellW;
            sampleY += (adjY / fittedDstH) * srcCellH;

        } else {
            // Fixed: draw at original pixel size, aligned in the cell.
            float dstOffX = (dstCellW - srcCellW) * (alignX + 1.0) * 0.5;
            float dstOffY = (dstCellH - srcCellH) * (alignY + 1.0) * 0.5;
            float adjX = localX - dstOffX;
            float adjY = localY - dstOffY;
            if (adjX < 0.0 || adjX >= srcCellW || adjY < 0.0 || adjY >= srcCellH) {
                fragColor = vec4(0.0);
                return;
            }
            sampleX += adjX;
            sampleY += adjY;
        }
    }

    fragColor = sampleTex(texIdx, vec2(sampleX / imgSize.x, sampleY / imgSize.y));
}
