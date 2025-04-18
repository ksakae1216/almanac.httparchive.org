#standardSQL
# 13_09: Requests and weight of third party content on ecom pages
SELECT
  percentile,
  client,
  APPROX_QUANTILES(requests, 1000)[OFFSET(percentile * 10)] AS requests,
  APPROX_QUANTILES(bytes, 1000)[OFFSET(percentile * 10)] / 1024 AS kbytes
FROM (
  SELECT
    client,
    COUNT(0) AS requests,
    SUM(respSize) AS bytes
  FROM
    `httparchive.almanac.requests`
  JOIN (
    SELECT DISTINCT _TABLE_SUFFIX AS client, url AS page
    FROM `httparchive.technologies.2021_07_01_*`
    WHERE category = 'Ecommerce' AND (app != 'Cart Functionality' AND app != 'Google Analytics Enhanced eCommerce')
  )
  USING (client, page)
  WHERE
    date = '2021-07-01' AND
    NET.HOST(url) IN (
      SELECT domain
      FROM `httparchive.almanac.third_parties`
      WHERE category != 'hosting'
    )
  GROUP BY
    client,
    page
),
  UNNEST([10, 25, 50, 75, 90, 100]) AS percentile
GROUP BY
  percentile,
  client
ORDER BY
  percentile,
  client
