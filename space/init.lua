local folder = (...):gsub("%.init$", "")

return {
    vec2 = require(folder..".vec2")
}