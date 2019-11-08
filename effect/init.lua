local folder = (...):gsub("%.init$", "")
return require(folder..".effect")