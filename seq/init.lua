local folder = (...):gsub("%.init$", "")
return require(folder..".seq")