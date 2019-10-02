local folder = (...):gsub("%.[^%.]+$", "")
local pat = require(folder..".pattern")

local my_pat = pat.table {
    test = pat.tuple(
        pat.intersect(
            pat.NUMBER,
            pat.range(1, 10),
            pat.collect("a")
        ),
        pat.intersect(pat.STRING, pat.collect("b"))
    ),
    another = pat.array(
        pat.union(
            pat.intersect(pat.CALLABLE, pat.collect("c")),
            pat.intersect(pat.FALSY, pat.collect("d")),
            pat.intersect(
                pat.enum { "A", "B", "C" },
                pat.collect("e")
            )
        )
    ),
    recursive_tree = pat.recurse("tree", function(rec)
        return pat.union(
            pat.tuple(
                pat.value("leaf"),
                pat.collect("f")
            ),
            pat.tuple(
                pat.value("node"),
                pat.array(rec) -- recurse here
            )
        )
    end)
}

local value = {
    test = {5, "hello", "world"},
    another = {
        "A",
        function() return 42 end,
        false
    },
    recursive_tree = {
        "node", {
            {"leaf", "leaf_1"},
            {
                "node", {
                    {"leaf", "leaf_2"}
                }
            }
        }
    }
}

local collection = {}
local success = my_pat:match(value, collection)

assert(success)
assert(collection.a == 5)
assert(collection.b == "hello")
assert(collection.c() == 42)
assert(collection.d == false)
assert(collection.e == "A")
assert(collection.f == "leaf_2")

print("[meido.pattern] all tests passed")