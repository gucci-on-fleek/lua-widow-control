<!-- lua-widow-control
     https://github.com/gucci-on-fleek/lua-widow-control
     SPDX-License-Identifier: MPL-2.0+ OR CC-BY-SA-4.0+
     SPDX-FileCopyrightText: 2021 Max Chernoff
-->

lua-widow-control
=================

Lua-widow-control is a Plain TeX/LaTeX/ConTeXt package that removes widows and orphans without any user intervention. Using the power of LuaTeX, it does so _without_ stretching any glue or shortening any pages or columns. Instead, lua-widow-control automatically lengthens a paragraph on a page or column where a widow or orphan would otherwise occur. 

Please see the [**full documentation**](https://github.com/gucci-on-fleek/lua-widow-control/releases/latest/download/lua-widow-control.pdf) for more.

Usage
-----
### Installation
Lua-widow-control is included in TeX&nbsp;Live and MikTeX. Provided that you have an up-to-date installation, you should not need to explicitly install the package.

If you are using ConTeXt or want to manually install the package, you may download it from one of the below links:

|Latest Release|Other Releases|
|--------------|--------------|
|[GitHub](https://github.com/gucci-on-fleek/lua-widow-control/releases/latest/)|[GitHub](https://github.com/gucci-on-fleek/lua-widow-control/releases)|
|[CTAN](https://www.ctan.org/pkg/lua-widow-control)||
|[ConTeXt Garden](https://modules.contextgarden.net/cgi-bin/module.cgi/action=view/id=127)||

### Usage
To load the package, add the relevant line to your preamble:

|Macro Package|Code                            |
|-------------|--------------------------------|
|LaTeX        |`\usepackage{lua-widow-control}`|
|ConTeXt      |`\usemodule[lua-widow-control]` |
|Plain TeX    |`\input lua-widow-control`      |


Licence
-------

Lua-widow-control is licensed under the [_Mozilla Public License_, version 2.0](https://www.mozilla.org/en-US/MPL/2.0/) or greater. The documentation is additionally licensed under [CC-BY-SA, version 4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode) or greater.

Please note that a compiled document is absolutely **not** considered to be an "Executable Form" as defined by the MPL. The use of lua-widow-control in a document does not place **any** obligations on the document's author or distributors. The MPL and CC-BY-SA licenses **only** apply to you if you distribute the lua-widow-control source code or documentation. 
