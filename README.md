<!-- lua-widow-control
     https://github.com/gucci-on-fleek/lua-widow-control
     SPDX-License-Identifier: MPL-2.0+ OR CC-BY-SA-4.0+
     SPDX-FileCopyrightText: 2022 Max Chernoff
-->

lua-widow-control
=================

Lua-widow-control is a Plain TeX/LaTeX/ConTeXt/OpTeX package that removes widows and orphans without any user intervention. Using the power of LuaTeX, it does so _without_ stretching any glue or shortening any pages or columns. Instead, lua-widow-control automatically lengthens a paragraph on a page or column where a widow or orphan would otherwise occur.

Please see the [**package manual**](https://github.com/gucci-on-fleek/lua-widow-control/releases/latest/download/lua-widow-control.pdf) for usage details or the [***TUGboat***](https://github.com/gucci-on-fleek/lua-widow-control/releases/latest/download/tb133chernoff-widows.pdf) or [***Zpravodaj* articles**](https://github.com/gucci-on-fleek/lua-widow-control/releases/latest/download/lwc-zpravodaj.pdf) for background information and discussion.

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
|OpTeX        |`\load[lua-widow-control]`      |


Contributing
------------

Please see [`CONTRIBUTING.md`](https://github.com/gucci-on-fleek/lua-widow-control/blob/master/CONTRIBUTING.md).

Licence
-------

Lua-widow-control is licensed under the [_Mozilla Public License_, version 2.0](https://www.mozilla.org/en-US/MPL/2.0/) or greater. The documentation is additionally licensed under [CC-BY-SA, version 4.0](https://creativecommons.org/licenses/by-sa/4.0/legalcode) or greater.

Please note that a compiled document is absolutely **not** considered to be an "Executable Form" as defined by the MPL. The use of lua-widow-control in a document does not place **any** obligations on the document's author or distributors. The MPL and CC-BY-SA licenses **only** apply to you if you distribute the lua-widow-control source code or documentation.

---
_v3.0.0 (2022-11-22)_ <!--%%version %%dashdate-->
