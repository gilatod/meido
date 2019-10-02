local folder = (...):gsub("%.init$", "")
return require(folder..".spec")