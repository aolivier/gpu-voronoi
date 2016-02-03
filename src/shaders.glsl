// TODO(ryan): How slow does this make things on mobile devices?
precision highp float;

uniform sampler2D cellGridTexture;
uniform vec2 gridSize; // Width and height of cellGridTexture
uniform vec2 canvasSize; // Size of HTML canvas element
uniform vec2 viewportOffset; // Viewport offset in grid space
uniform vec2 viewportSize; // Viewport size in grid space
uniform int RELEASE; // Used for debugging
uniform sampler2D seedTexture;
uniform int seedTextureSize;
uniform vec2 cellGridSize;
uniform int stepSize;

// Helpers
////////////////////////////////////////////////////////////////////////

const float EPSILON = 0.0001;

const vec4 RED = vec4(1.0, 0.0, 0.0, 1.0);
const vec4 GREEN = vec4(0.0, 1.0, 0.0, 1.0);
const vec4 BLUE = vec4(0.0, 0.0, 1.0, 1.0);
const vec4 CYAN = vec4(0.0, 1.0, 1.0, 1.0);
const vec4 MAGENTA = vec4(1.0, 0.0, 1.0, 1.0);
const vec4 YELLOW = vec4(1.0, 1.0, 0.0, 1.0);
const vec4 BLACK = vec4(0.0, 0.0, 0.0, 1.0);
const vec4 WHITE = vec4(1.0, 1.0, 1.0, 1.0);

int modInt(int a, int b) {
    return int(mod(float(a), float(b)));
}

bool approxEqual(float a, float b) {
    return abs(a - b) < EPSILON;
}

vec2 gridPositionToUv(vec2 position, vec2 gridSize) {
    return position / gridSize;
}

bool between(vec2 value, vec2 bottom, vec2 top) {
    return value.x > bottom.x && value.x < top.x && value.y > bottom.y && value.y < top.y;
}

vec2 gridPointFromFragCoord(vec2 fragCoord) {
    // UV co-ordinates of the pixel we're drawing in canvas space
    vec2 canvasSpaceUv = gl_FragCoord.xy / canvasSize;

    // Use that to find the grid point that we're drawing
    return viewportOffset + viewportSize * canvasSpaceUv;
}

bool validUv(vec2 uv) {
    return uv.x >= 0.0 && uv.y >= 0.0 && uv.x <= 1.0 && uv.y <= 1.0;
}

// Vertex shader for drawing a quad
////////////////////////////////////////////////////////////////////////

attribute vec2 quad;

export void vCopyPosition() {
    gl_Position = vec4(quad, 0, 1.0);
}

// Each pixel in our grid texture is a cell object. Each cell contains
// the following info (isSeed, seedIndex, locationX, locationY). The
// following functions are an 'object-oriented' set of functions for
// handling cells.
////////////////////////////////////////////////////////////////////////

vec4 createCell(bool isSeed, int seedIndex, vec2 location) {
    return vec4(isSeed ? 1.0 : 0.0, float(seedIndex), location);
}

vec4 createInvalidCell() {
    return vec4(-1.0, -1.0, -1.0, -1.0);
}

int cellSeedIndex(const vec4 obj) {
    return int(obj[1]);
}

vec2 cellSeedLocation(const vec4 obj) {
    return vec2(obj[2], obj[3]);
}

bool cellIsValid(const vec4 obj) {
    return !approxEqual(obj[0], -1.0);
}

// Fragment shader for the Jump Flood algorithm
////////////////////////////////////////////////////////////////////////

vec4 getCellForOffset(const vec4 self, const vec2 offset) {
    vec2 gridUv = gridPositionToUv(gl_FragCoord.xy + offset, cellGridSize);
    vec4 otherCell = validUv(gridUv) ? texture2D(cellGridTexture, gridUv) : createInvalidCell();

    if (!cellIsValid(otherCell)) {
        // Other is invalid. This probably means that `offset` is off the grid.
        return self;
    }

    if (cellSeedIndex(otherCell) < 0) {
        // Other's seed location hasn't been set
        return self;
    }

    else if (cellSeedIndex(self) < 0) {
        // Our seed location hasn't been set
        return createCell(false, cellSeedIndex(otherCell), cellSeedLocation(otherCell));
    }

    else {
        vec2 selfSeed = cellSeedLocation(self);
        vec2 otherSeed = cellSeedLocation(otherCell);
        if (distance(selfSeed, gl_FragCoord.xy) > distance(otherSeed, gl_FragCoord.xy)) {
            return createCell(false, cellSeedIndex(otherCell), otherSeed);
        }
    }

    return self;
}

export void fGameOfLife() {
    // Find the object at this grid position
    vec2 gridUv = gridPositionToUv(gl_FragCoord.xy, cellGridSize);

    // We gridUv should always be valid. We run this once for every
    // cell in the grid.
    if (!validUv(gridUv)) {
        gl_FragColor.x = 1. / 0.;
    }

    vec4 object = texture2D(cellGridTexture, gridUv);

    // Object is always valid, because we
    object = getCellForOffset(object, vec2(0, stepSize));
    object = getCellForOffset(object, vec2(stepSize, stepSize));
    object = getCellForOffset(object, vec2(stepSize, 0));
    object = getCellForOffset(object, vec2(stepSize, - stepSize));
    object = getCellForOffset(object, vec2(0, - stepSize));
    object = getCellForOffset(object, vec2(- stepSize, - stepSize));
    object = getCellForOffset(object, vec2(- stepSize, 0));
    object = getCellForOffset(object, vec2(- stepSize, stepSize));
    gl_FragColor = object;
}

// Fragment shader for drawing the result of the Jump Flood algorithm
////////////////////////////////////////////////////////////////////////

void drawDebugUI(vec2 gridPoint) {
    if (RELEASE == 1) {
        return;
    }

    vec4 lightRed = vec4(1.0, 0.5, 0.5, 1.0);
    vec4 lightBlue = vec4(0.5, 0.5, 1.0, 1.0);
    vec4 lightGreen = vec4(0.5, 1.0, 0.5, 1.0);

    // Show a red 100x100 cell grid
    if (mod(gridPoint.x, 100.0) < 3.0 || mod(gridPoint.y, 100.0) < 3.0) {
        gl_FragColor = (lightRed + gl_FragColor) / 2.0;
    }

    // Show a green marker at (0, 0)
    if (between(gridPoint.xy, vec2(0.0, 0.0), vec2(10.0, 10.0))) {
        gl_FragColor = (lightGreen + gl_FragColor) / 2.0;
    }

    // Show a blue marker at (100, 100)
    if (between(gridPoint.xy, vec2(100.0, 100.0), vec2(110.0, 110.0))) {
        gl_FragColor = (lightBlue + gl_FragColor) / 2.0;
    }
}

export void fDrawGrid() {
    vec2 gridPoint = gridPointFromFragCoord(gl_FragCoord.xy);
    vec2 gridUv = gridPoint / gridSize;

    if (!validUv(gridUv)) {
        gl_FragColor = BLACK;
        drawDebugUI(gridPoint);
        return;
    }

    vec4 object = texture2D(cellGridTexture, gridUv);
    int seedIndex = cellSeedIndex(object);
    int x = modInt(seedIndex, seedTextureSize);
    int y = seedIndex / seedTextureSize;
    vec2 seedTexelCoord = vec2(float(x), float(y));
    vec2 seedUv = seedTexelCoord / float(seedTextureSize);
    gl_FragColor = seedIndex < 0 ? WHITE : texture2D(seedTexture, seedUv);
}