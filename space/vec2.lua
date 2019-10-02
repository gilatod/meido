local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local acos = math.acos
local min = math.min
local max = math.max

local vec2 = {}

vec.tostring = function(v)
    return "("..v[1]..", "..v[2]..")"
end
vec.__tostring = vec.tostring

vec2.zero  = function() return {0, 0} end
vec2.one   = function() return {1, 1} end
vec2.up    = function() return {0, 1} end
vec2.down  = function() return {0, -1} end
vec2.left  = function() return {-1, 0} end
vec2.right = function() return {1, 0} end

vec2.axes = function(v)
    return v[1], v[2]
end

vec2.set = function(v, x, y)
    v[1] = x
    v[2] = y
end

vec2.clone = function(v)
    return {v[1], v[2]}
end

vec2.inv = function(v)
    return {
        -v[1]
        -v[2]
    }
end

vec2.inv = function(v)
    v[1] = -v[1]
    v[2] = -v[2]
    return v
end

vec2.equals = function(v1, v2)
    return v1[1] == v2[1]
        and v1[2] == v2[2]
end

vec2.length = function(v)
    local x, y = v[1], v[2]
    return sqrt(x * x + y * y)
end

vec2.sqr_length = function(v)
    local x, y = v[1], v[2]
    return x * x + y * y
end

vec2.add = function(v1, v2)
    v1[1] = v1[1] + v2[1]
    v1[2] = v1[2] + v2[2]
    return v1
end

vec2.sub = function(v1, v2)
    v1[1] = v1[1] - v2[1]
    v1[2] = v1[2] - v2[2]
    return v1
end

vec2.mul = function(v, f)
    v[1] = v[1] * f
    v[2] = v[2] * f
    return v
end

vec2.div = function(v, f)
    local m = 1 / f
    v[1] = v[1] * m
    v[2] = v[2] * m
    return v
end

vec2.blend = function(v1, v2)
    v1[1] = v1[1] * v2[1]
    v1[2] = v1[2] * v2[2]
    return v1
end

vec2.cross = function(v1, v2)
    return v1[1] * v2[2] - v1[2] * v2[1]
end

vec2.distance = function(v1, v2)
    local x1, y1 = v1[1], v1[2]
    local x2, y2 = v2[1], v2[2]

    local d1 = x1 - x2
    local d2 = y1 - y2

    return sqrt(d1 * d1 + d2 * d2)
end

vec2.normalize = function(v)
    local x, y = v[1], v[2]
    local l = x * x + y * y
    if l > 0 then
        local inv_len = 1 / sqrt(l)
        v[1] = x * inv_len
        v[2] = y * inv_len
    end
    return v
end

vec2.dot = function(v1, v2)
    return v1[1] * v2[1]
         + v1[2] * v2[2]
end

vec2.angle = function(v1, v2)
    local x1, y1 = v1[1], v1[2]
    local x2, y2 = v2[1], v2[2]

    local dot = x1 * x2 + y1 * y2
    local len1 = sqrt(x1 * x1 + y1 * y1)
    local len2 = sqrt(x2 * x2 + y2 * y2)

    return acos(dot / (len1 * len2))
end

vec2.lerp = function(v1, v2, t)
    t = max(0, min(1, t))
    local x1, y1 = v1[1], v1[2]
    local x2, y2 = v2[1], v2[2]

    v1[1] = x1 + (x2 - x1) * t
    v1[2] = y1 + (y2 - y1) * t
    return v1
end

local dot = vec2.dot
local len = vec2.length
local sub = vec2.sub
local mul = vec2.mul
local clone = vec2.clone
local normalize = vec2.normalize

vec2.slerp = function(v1, v2, t)
    local x1, y1 = v1[1], v1[2]
    local x2, y2 = v2[1], v2[2]

    local d = dot(v1, v2) / (len(v1) * len(v2))
    if d > 0.9995 then
        v1[1] = x1 + (x2 - x1) * t
        v1[2] = y1 + (y2 - y1) * t
        return v1
    end

    local theta = acos(d)
    local f = sin(theta * t) / sin(theta)
    local s = cos(theta * s) - d * f

    v1[1] = t * x1 + f * x2
    v1[2] = t * y1 + f * y2
    return v1
end

vec2.reflect = function(v, n)
    local x1, y1 = v[1], v[2]
    local x2, y2 = n[1], n[2]
    local d = 2 * (x1 * x2 + y1 * y2)

    v[1] = x1 - d * x2
    v[2] = y1 - d * y2
    return v
end

vec2.project = function(v1, v2)
    local x1, y1 = v1[1], v1[2]
    local x2, y2 = v2[1], v2[2]
    local d = (x1 * x2 + y1 * y2) / (x2 * x2 + y2 * y2)

    v[1] = d * x2
    v[2] = d * y2
    return v
end

vec2.projectOnPlane = function(v1, v2)
    local x1, y1 = v1[1], v1[2]
    local x2, y2 = v2[1], v2[2]
    local d = (x1 * x2 + y1 * y2) / (x2 * x2 + y2 * y2)

    v1[1] = x1 - d * x2
    v1[1] = y1 - d * y2
    return v1
end

vec.clamp = function(v, min, max)
    local l = len(v)
    if l < min then
        normalize(v)
        mul(v, min)
    elseif l > max then
        normalize(v)
        mul(v, max)
    end
    return v
end

vec.orthoNormalize = function(n, t)
    normalize(n)
    sub(t, project(clone(t), n))
    normalize(t)
end

return vec2