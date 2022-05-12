module = "lua-widow-control"

testsuppdir = prefix .. "tests/common"
tdsdirs = { [prefix .. "texmf"] = "." }
maxprintline = 10000

test_types = {
    pdftotext = {
        test = ".lvtext",
        generated = ".pdf",
        reference = ".tltext",
        rewrite = function(source, result)
            os.execute(
                "pdftotext -bbox-layout " .. source .. " -" ..
                "| xsltproc --novalid --output " .. result ..
                " " .. prefix .. "tests/transform.xslt -"
            )
        end,
    },
}

test_order = { "pdftotext" }
