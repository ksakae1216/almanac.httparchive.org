# standardSQL
# Count JSON-LD sameAs values
CREATE TEMP FUNCTION getJSONLDSameAses(rendered STRING)
RETURNS ARRAY<STRING>
LANGUAGE js AS """
  try {
    const arrayify = (value) => Array.isArray(value) ? value : [value];

    const getDeep = (key, o) => {
      if (Array.isArray(o)) return o.map(child => getDeep(key, child)).flat();

      if (o instanceof Object) {
        return Object.entries(o).map(([k, value]) => {
          if (k === key) return [...arrayify(value), ...getDeep(value)];
          return getDeep(value);
        }).flat();
      }

      return [];
    }

    rendered = JSON.parse(rendered);
    const jsonld_scripts = rendered.jsonld_scripts;
    return jsonld_scripts.map(jsonld_script => {
      jsonld_script = JSON.parse(jsonld_script);
      return getDeep('sameAs', jsonld_script);
    }).flat();
  } catch (e) {
    return [];
  }
""";

WITH
rendered_data AS (
  SELECT
    _TABLE_SUFFIX AS client,
    url,
    getJSONLDSameAses(JSON_EXTRACT(JSON_VALUE(JSON_EXTRACT(payload, '$._structured-data')), '$.structured_data.rendered')) AS jsonld_sameases
  FROM
    `httparchive.pages.2022_06_01_*`
),

page_totals AS (
  SELECT
    _TABLE_SUFFIX AS client,
    COUNT(0) AS total_pages
  FROM
    `httparchive.pages.2022_06_01_*`
  GROUP BY
    _TABLE_SUFFIX
)

SELECT
  client,
  NET.REG_DOMAIN(jsonld_sameas) AS jsonld_sameas,
  COUNT(0) AS freq_jsonld_sameas,
  SUM(COUNT(0)) OVER (PARTITION BY client) AS total_jsonld_sameas,
  COUNT(0) / SUM(COUNT(0)) OVER (PARTITION BY client) AS pct_jsonld_sameas,
  COUNT(DISTINCT url) AS freq_pages,
  total_pages,
  COUNT(DISTINCT url) / total_pages AS pct_pages
FROM
  rendered_data,
  UNNEST(jsonld_sameases) AS jsonld_sameas
JOIN
  page_totals
USING (client)
GROUP BY
  client,
  jsonld_sameas,
  total_pages
ORDER BY
  pct_jsonld_sameas DESC,
  client
LIMIT 1000
