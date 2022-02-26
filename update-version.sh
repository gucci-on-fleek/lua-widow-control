#!/bin/sh

# lua-widow-control
# https://github.com/gucci-on-fleek/lua-widow-control
# SPDX-License-Identifier: MPL-2.0+
# SPDX-FileCopyrightText: 2022 Max Chernoff

grep --exclude-dir=.git/ -Erl '%%[v]ersion' | xargs sed -i "/%%[v]ersion/ s/[[:digit:]]\.[[:digit:]]\.[[:digit:]]/$1/"

grep --exclude-dir=.git/ -Erl '%%[d]ashdate' | xargs sed -Ei "/%%[d]ashdate/ s/[[:digit:]]{4}.[[:digit:]]{2}.[[:digit:]]{2}/$(date -I)/"

grep --exclude-dir=.git/ -Erl '%%[s]lashdate' | xargs sed -Ei "/%%[s]lashdate/ s|[[:digit:]]{4}.[[:digit:]]{2}.[[:digit:]]{2}|$(date +%Y/%m/%d)|"
