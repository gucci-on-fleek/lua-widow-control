<!-- lua-widow-control
     https://github.com/gucci-on-fleek/lua-widow-control
     SPDX-License-Identifier: MPL-2.0+ OR CC-BY-SA-4.0+
     SPDX-FileCopyrightText: 2022 Max Chernoff
-->

Changelog
=========

All notable changes to lua-widow-control will be listed here, in reverse chronological order. **Changes listed in bold** are important changes: they either remove options or commands, or may change the location of page breaks.

## v3.0.0 (2022-11-22)

- Add the new _TUGboat_ and _Zpravodaj_ articles.

- Add and document the public Lua interfaces.

- Change `\parfillskip` settings for lengthened paragraphs to more strongly prevent short last lines. **May affect page breaks.**

- Add the ability to configure the horizontal offset for the paragraph costs printed in draft mode.

- Add support for [LuaMetaLaTeX and LuaMetaPlain](https://github.com/zauguin/luametalatex). All features should work identically to the LuaTeX-based version, although there are a few minor bugs. ([#40](https://github.com/gucci-on-fleek/lua-widow-control/pull/40))

- Fully support inserts/footnotes in LuaMetaTeX ([#38](https://github.com/gucci-on-fleek/lua-widow-control/issues/38)).

- Add support for presets in ConTeXt.

- Add support for node colouring in ConTeXt and OpTeX  ([#39](https://github.com/gucci-on-fleek/lua-widow-control/issues/39)).

## [v2.2.2 (2022-08-23)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-6c91837c205572a78a0bcaf9c80b8e475ef71689)

- Add preliminary support for inserts/footnotes in LuaMetaTeX ([#38](https://github.com/gucci-on-fleek/lua-widow-control/issues/38)).

- Use the built-in LaTeX key–value interface where available.

  This means that lua-widow-control now also reads the global class options.

- Add support for split footnotes ([#37](https://github.com/gucci-on-fleek/lua-widow-control/issues/37)).

## [v2.2.1 (2022-07-28)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-45c3146d5fc5a86606a931212395a28ffb48f925)

- Fix crashes with recent LuaMetaTeX (ConTeXt MkXL). See also [this thread](https://mailman.ntg.nl/pipermail/ntg-context/2022/106331.html).
- No longer show "left parfill skip" warnings with ConTeXt LMTX/MkXL ([#7](https://github.com/gucci-on-fleek/lua-widow-control/issues/7)).

## [v2.2.0 (2022-06-17)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-9a5deba53545adc5ab25a5caa0b8ebf4104843f9)

- Fix paragraphs not being properly saved for potential expansion. **May affect page breaks.**
- Add a new `draft` option ([#36](https://github.com/gucci-on-fleek/lua-widow-control/issues/36)).
- Fix a node memory leak ([#29](https://github.com/gucci-on-fleek/lua-widow-control/issues/29)). You should now be able to use lua-widow-control on documents with > 10 000 pages.
- Use `\lua_load_module:n` when available.
- Add additional metadata to the documentation.


## [v2.1.2 (2022-05-27)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-3744f3e78bdf02fc63d508a0f80595260191607c)

- Fully-support footnotes/inserts: lua-widow-control now moves the "footnote text" with the "footnote mark" when it moves a line to the next page.
- No longer attempt to expand paragraphs in `\vbox`es
- Minor documentation updates


## [v2.1.1 (2022-05-20)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-980f24ac64816bd0d453754f8f1af676f0f7ee99)

- Prevent spurious `under/overfull \vbox` warnings when widows/orphans are removed
- Add TUGboat article to the distributed documentation
- Rewrite many portions of the manual
- Add support for `luahbtex` and `mmoptex` ([#35](https://github.com/gucci-on-fleek/lua-widow-control/pull/35) [@vlasakm](https://github.com/vlasakm))
- Fix the (undocumented) `microtype` LaTeX option


## [v2.1.0 (2022-05-14)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-82563aa0396805008059e3a96c2bf30b59c58026)

- Fully support grid snapping in ConTeXt
- New warnings when a new widow/orphan is inadvertently created
- Significant internal rewrites
- Add Plain and OpTeX interfaces to `\nobreak` behaviour and debug mode


## [v2.0.6 (2022-04-23)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-2aa9269b33a03f66d2ece634c3dcba6b258fddf0)

- Emergency fix for renamed LMTX engine Lua functions
- Internal LaTeX refactoring


## [v2.0.5 (2022-04-13)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-e3234ac7dfb31118d08fcb5ed0fe03f394df2b57)

- Support nested `\lwcdisablecmd` macros
- Fix `\lwcdisablecmd` in Plain TeX
- Support command patching in OpTeX
- Patch memoir to prevent spurious asterisks at broken two-line paragraphs ([#32](https://github.com/gucci-on-fleek/lua-widow-control/issues/32))


## [v2.0.4 (2022-04-07)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-8a0e97e448976280a38d41f92c2781320b1a91f0)

- Don't expand paragraphs typeset during output routines ([#31](https://github.com/gucci-on-fleek/lua-widow-control/issues/31))


## [v2.0.3 (2022-03-28)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-d6622dd9fd04a4bc7678ff18420c1b4bdf077844)

- Automatically patch section commands provided by memoir, KOMA-Script, and titlesec.


## [v2.0.2 (2022-03-20)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-7e79189406a2318c33dcaceb85d9d1021b357a3f)

_Final release present in TeX Live 2021_

- Add `balanced` mode preset.


## [v2.0.1 (2022-03-18)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-f3048dbcbfaf4d7d6f6a57e236cdb9684ff5d18d)

- Documentation updates ([#25](https://github.com/gucci-on-fleek/lua-widow-control/issues/25))
- Bug fixes ([#28](https://github.com/gucci-on-fleek/lua-widow-control/issues/28))


## [v2.0.0 (2022-03-07)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-cea06ddad8dfcf15fa9ba2a86c6640648b9df523)

- **Page breaks may be slightly different**
- **Removed `\lwcemergencystretch` and `\lwcdisablecmd` in LaTeX. Please use the new key–value interface**
- Use expl3 for the LaTeX files ([#20](https://github.com/gucci-on-fleek/lua-widow-control/pull/20))
- Use a key–value interface for configuration with LaTeX ([#11](https://github.com/gucci-on-fleek/lua-widow-control/issues/11))
- Silence some extraneous `luatexbase` info messages
- Add a "debug mode" to print extra information ([#12](https://github.com/gucci-on-fleek/lua-widow-control/issues/12))
- Fix error message line wrapping
- Don't reset `\interlinepenalty` and `\brokenpenalty`
- Set and analyze `\displaywidowpenalty`
- Keep section headings with moved orphans ([#17](https://github.com/gucci-on-fleek/lua-widow-control/issues/17))
- Add the ability to configure the maximum paragraph cost ([#22](https://github.com/gucci-on-fleek/lua-widow-control/issues/22))
- Add a "strict" mode
- Use an improved cost function to select the best paragraph to lengthen ([#23](https://github.com/gucci-on-fleek/lua-widow-control/issues/23))
- Dozens of bug fixes
- Miscellaneous documentation updates


## [v1.1.6 (2022-02-22)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-2c7201854d89535ef7c02f6c38486205677f1aa1)

- Add support for the OpTeX format/macro package.
- Add support for the LuaTeX/MKIV version of ConTeXt.
- Ensure compatibility with the new `linebreaker` package.
- Fix a small bug with `\lwcdisablecmd`.
- Test the `\outputpenalty` for the specific values that indicate a widow or orphan.


## [v1.1.5 (2022-02-15)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-5cc95212c8141006ae3a600d26a4e0cd63b368c0)

- Improve the appearance of the demo table in the documentation ([#4](https://github.com/gucci-on-fleek/lua-widow-control/issues/4))
- Improve compatibility with microtype
- Block loading the package without LuaTeX
- Improve logging
- Bug fix to prevent crashing


## [v1.1.4 (2022-02-04)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-a8caba8e689ce5c743a88dcf1dcd8e4a0db67fb2)

- Enable protrusion/expansion in the demo table in the documentation ([#3](https://github.com/gucci-on-fleek/lua-widow-control/issues/3))
- Fix `\prevdepth` bug


## [v1.1.3 (2022-01-30)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-8d1228bf1697e2720062b0c2a40f306005da72e8)

- Fix bug when used with the LaTeX `calc` package. ([#2](https://github.com/gucci-on-fleek/lua-widow-control/issues/2))


## [v1.1.2 (2021-12-14)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-61a684d92f1a38ecf0ff53c6da22b2a973fae530)

- Fix crash under ConTeXt LMTX


## [v1.1.1 (2021-11-26)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/v1.1.1)

- Minor documentation updates


## [v1.1.0 (2021-11-08)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-8c958011bb4bd7f6e4ad843321c0d2643645a08f)

- Extensive documentation updates
- Clarify that lua-widow-control *does* in fact support columns
- Add `\lwcdisablecmd` macro to disable lua-widow-control for certain commands
- Automatically disable lua-widow-control inside section headings (uses `\lwcdisablecmd`)
- Add automated tests to prevent regressions
- Fix a rare issue that would cause indefinite hangs



## [v1.0.0 (2021-10-09)](https://github.com/gucci-on-fleek/lua-widow-control/releases/tag/release-bae44a6858432e095597521bf1ef7df2104b6b9c)

Initial release
