-- Normalize a family name. Used in FAMILY_INNER.
CREATE TEMPORARY FUNCTION FAMILY_INNER_INNER(name STRING) AS (
  CASE
    WHEN REGEXP_CONTAINS(name, r'(?i)font\s?awesome') THEN 'Font Awesome'
    ELSE IF(LENGTH(TRIM(name)) < 3, NULL, NULLIF(TRIM(name), ''))
  END
);

-- Normalize a family name. Used in FAMILY.
CREATE TEMPORARY FUNCTION FAMILY_INNER(name STRING) AS (
  FAMILY_INNER_INNER(
    REGEXP_REPLACE(
      name,
      r'(?i)([\s-]?(black|bold|book|cond(ensed)?|demi|ex(tra)?|heavy|italic|light|medium|narrow|regular|semi|thin|ultra|wide|\d00|\d+pt))+$',
      ''
    )
  )
);

-- Extract the family name from a payload.
CREATE TEMPORARY FUNCTION FAMILY(payload STRING) AS (
  FAMILY_INNER(
    COALESCE(
      JSON_EXTRACT_SCALAR(payload, '$._font_details.names[16]'),
      JSON_EXTRACT_SCALAR(payload, '$._font_details.names[1]')
    )
  )
);

-- Extract the file format from an extension and a MIME type.
CREATE TEMPORARY FUNCTION FILE_FORMAT(extension STRING, type STRING) AS (
  LOWER(IFNULL(REGEXP_EXTRACT(type, '/(?:x-)?(?:font-)?(.*)'), extension))
);

-- Normalize a foundry name. Used in FOUNDRY.
CREATE TEMPORARY FUNCTION FOUNDRY_INNER(name STRING) AS (
  CASE UPPER(name)
    WHEN 'ADBO' THEN 'ADBE'
    WHEN 'PFED' THEN 'AWSM'
    ELSE NULLIF(TRIM(REGEXP_REPLACE(name, r'[[:cntrl:]]+', '')), '')
  END
);

-- Extract the foundry name from a payload.
CREATE TEMPORARY FUNCTION FOUNDRY(payload STRING) AS (
  FOUNDRY_INNER(JSON_EXTRACT_SCALAR(payload, '$._font_details.OS2.achVendID'))
);

-- Infer scripts from codepoints. Used in SCRIPTS.
CREATE TEMPORARY FUNCTION SCRIPTS_INNER(codepoints ARRAY<STRING>)
RETURNS ARRAY<STRING>
LANGUAGE js
OPTIONS (library = ["gs://httparchive/lib/text-utils.js"])
AS r"""
if (codepoints && codepoints.length) {
  return detectWritingScript(codepoints.map((character) => parseInt(character, 10)), 0.05);
} else {
  return [];
}
""";

-- Infer scripts from a payload.
CREATE TEMPORARY FUNCTION SCRIPTS(payload STRING) AS (
  SCRIPTS_INNER(JSON_EXTRACT_STRING_ARRAY(payload, '$._font_details.cmap.codepoints'))
);

-- Infer the service from a URL.
CREATE TEMPORARY FUNCTION SERVICE(url STRING) AS (
  CASE
    WHEN REGEXP_CONTAINS(url, r'(fonts|use)\.typekit\.(net|com)') THEN 'Adobe'
    WHEN REGEXP_CONTAINS(url, r'cloud\.typenetwork\.com') THEN 'typenetwork.com'
    WHEN REGEXP_CONTAINS(url, r'cloud\.typography\.com') THEN 'typography.com'
    WHEN REGEXP_CONTAINS(url, r'cloud\.webtype\.com') THEN 'webtype.com'
    WHEN REGEXP_CONTAINS(url, r'f\.fontdeck\.com') THEN 'fontdeck.com'
    WHEN REGEXP_CONTAINS(url, r'fast\.fonts\.(com|net)\/(jsapi|cssapi)') THEN 'fonts.com'
    WHEN REGEXP_CONTAINS(url, r'fnt\.webink\.com') THEN 'webink.com'
    WHEN REGEXP_CONTAINS(url, r'fontawesome\.com') THEN 'fontawesome.com'
    WHEN REGEXP_CONTAINS(url, r'fonts\.(gstatic|googleapis)\.com|themes.googleusercontent.com/static/fonts|ssl.gstatic.com/fonts') THEN 'Google'
    WHEN REGEXP_CONTAINS(url, r'fonts\.typonine\.com') THEN 'typonine.com'
    WHEN REGEXP_CONTAINS(url, r'fonts\.typotheque\.com') THEN 'typotheque.com'
    WHEN REGEXP_CONTAINS(url, r'kernest\.com') THEN 'kernest.com'
    WHEN REGEXP_CONTAINS(url, r'typefront\.com') THEN 'typefront.com'
    WHEN REGEXP_CONTAINS(url, r'typesquare\.com') THEN 'typesquare.com'
    WHEN REGEXP_CONTAINS(url, r'use\.edgefonts\.net|webfonts\.creativecloud\.com') THEN 'edgefonts.net'
    WHEN REGEXP_CONTAINS(url, r'webfont\.fontplus\.jp') THEN 'fontplus.jp'
    WHEN REGEXP_CONTAINS(url, r'webfonts\.fontslive\.com') THEN 'fontslive.com'
    WHEN REGEXP_CONTAINS(url, r'webfonts\.fontstand\.com') THEN 'fontstand.com'
    WHEN REGEXP_CONTAINS(url, r'webfonts\.justanotherfoundry\.com') THEN 'justanotherfoundry.com'
    ELSE 'self-hosted'
  END
);

-- Extract the color formats from a formats payload and remove spurious entries
-- via a table-sizes payload.
--
-- When nonempty, it is expected that
--
-- * `CBDT` is larger than 2 + 2 bytes,
-- * `COLR` is larger than 2 + 2 + 4 + 4 + 2 (+ 4 + 4 + 4 + 4 + 4) bytes,
-- * `SVG ` is larger than 2 + 4 + 4 + 2 bytes, and
-- * `sbix` is larger than 2 + 2 + 4 + 4 bytes.
--
-- For simplicity, the threshold is set to 50 bytes.
CREATE TEMPORARY FUNCTION COLOR_FORMATS_INNER(jsonFormats STRING, jsonSizes STRING)
RETURNS ARRAY<STRING>
LANGUAGE js AS '''
try {
  const formats = JSON.parse(jsonFormats);
  const sizes = JSON.parse(jsonSizes);
  return formats.filter((format) => {
    const table = `${format}    `.slice(0, 4);
    return sizes[table] > 50;
  });
} catch (e) {
  return [];
}
''';

-- Extract the color formats from a payload.
CREATE TEMPORARY FUNCTION COLOR_FORMATS(payload STRING) AS (
  COLOR_FORMATS_INNER(
    JSON_EXTRACT(payload, '$._font_details.color.formats'),
    JSON_EXTRACT(payload, '$._font_details.table_sizes')
  )
);

-- Check if the font is a color font given its payload.
CREATE TEMPORARY FUNCTION IS_COLOR(payload STRING) AS (
  ARRAY_LENGTH(COLOR_FORMATS(payload)) > 0
);

-- Check if the font was successfully parsed given its payload.
CREATE TEMPORARY FUNCTION IS_PARSED(payload STRING) AS (
  JSON_EXTRACT(payload, '$._font_details.table_sizes') IS NOT NULL
);

-- Check if the font is a variable font given its payload.
CREATE TEMPORARY FUNCTION IS_VARIABLE(payload STRING) AS (
  REGEXP_CONTAINS(
    JSON_EXTRACT(payload, '$._font_details.table_sizes'),
    '(?i)gvar|CFF2'
  )
);

-- Extract the variable formats from a payload.
CREATE TEMPORARY FUNCTION VARIABLE_FORMATS(payload STRING) AS (
  REGEXP_EXTRACT_ALL(
    JSON_EXTRACT(payload, '$._font_details.table_sizes'),
    '(?i)glyf|CFF2'
  )
);
