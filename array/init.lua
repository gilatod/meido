local folder = (...):gsub("%.init$", "")
return require(folder..".array")