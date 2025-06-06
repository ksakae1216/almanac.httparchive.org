#standardSQL
CREATE TEMPORARY FUNCTION getResourceHintAttrs(payload STRING)
RETURNS ARRAY<STRUCT<name STRING, attribute STRING, value STRING>>
LANGUAGE js AS '''
var hints = new Set(['preload', 'prefetch', 'modulepreload']);
var attributes = ['as'];
try {
  var $ = JSON.parse(payload);
  var almanac = JSON.parse($._almanac);
  return almanac['link-nodes'].nodes.reduce((results, link) => {
    var hint = link.rel.toLowerCase();
    if (!hints.has(hint)) {
      return results;
    }
    attributes.forEach(attribute => {
      var value = link[attribute];
      results.push({
        name: hint,
        attribute: attribute,
        // Support empty strings.
        value: typeof value == 'string' ? value : null
      });
    });
    return results;
  }, []);
} catch (e) {
  return [];
}
''';

SELECT
  percentile,
  client,
  APPROX_QUANTILES(prefetch_hint, 1000)[OFFSET(percentile * 10)] AS prefetch_hints_per_page,
  APPROX_QUANTILES(IF(prefetch_hint = 0, NULL, prefetch_hint), 1000 IGNORE NULLS)[OFFSET(percentile * 10)] AS prefetch_hints_per_page_with_hints,
  APPROX_QUANTILES(preload_hint, 1000)[OFFSET(percentile * 10)] AS preload_hints_per_page,
  APPROX_QUANTILES(IF(preload_hint = 0, NULL, preload_hint), 1000 IGNORE NULLS)[OFFSET(percentile * 10)] AS preload_hints_per_page_with_hints,
  APPROX_QUANTILES(modulepreload_hint, 1000)[OFFSET(percentile * 10)] AS modulepreload_hints_per_page,
  APPROX_QUANTILES(IF(modulepreload_hint = 0, NULL, modulepreload_hint), 1000 IGNORE NULLS)[OFFSET(percentile * 10)] AS modulepreload_hints_per_page_with_hints
FROM (
  SELECT
    client,
    page,
    COUNTIF(hint.name = 'prefetch' AND hint.value = 'script') AS prefetch_hint,
    COUNTIF(hint.name = 'preload' AND hint.value = 'script') AS preload_hint,
    COUNTIF(hint.name = 'modulepreload' AND hint.value = 'script') AS modulepreload_hint
  FROM
    `httparchive.all.pages`
  LEFT JOIN
    UNNEST(getResourceHintAttrs(payload)) AS hint
  WHERE
    date = '2024-06-01'
  GROUP BY
    client,
    page
),
  UNNEST([10, 25, 50, 75, 90, 100]) AS percentile
GROUP BY
  percentile,
  client
ORDER BY
  client,
  percentile
