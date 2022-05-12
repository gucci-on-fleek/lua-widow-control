<?xml version="1.0" encoding="utf-8"?>
<!-- lua-widow-control
     https://github.com/gucci-on-fleek/lua-widow-control
     SPDX-License-Identifier: MPL-2.0+
     SPDX-FileCopyrightText: 2022 Max Chernoff
 -->
<xsl:stylesheet
    xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:html="http://www.w3.org/1999/xhtml"
    version="1.0"
>
    <xsl:output method="text" encoding="utf-8"/>

    <xsl:variable name="row_sep" select="'&#10;'"/>
    <xsl:variable name="col_sep" select="' '"/>

    <xsl:template match="/html:html/html:body/html:doc">
        <xsl:for-each select="html:page">
            <xsl:for-each select=".//html:line">
                <xsl:value-of select="concat(
                    format-number(@xMin, '000.0'),
                    $col_sep,
                    format-number(@xMax, '000.0'),
                    $col_sep,
                    format-number(@yMin, '000.0'),
                    $col_sep,
                    format-number(@yMax, '000.0'),
                    $col_sep,
                    html:word[1],
                    $col_sep,
                    html:word[last()],
                    $row_sep
                )"/>
            </xsl:for-each>
            <xsl:value-of select="$row_sep"/>
        </xsl:for-each>
    </xsl:template>

    <xsl:template match="text()|@*"/>

</xsl:stylesheet>
