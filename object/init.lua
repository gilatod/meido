local folder = (...):gsub("%.init$", "")
return require(folder..".object")