-- Top customers in the last 30 days
WITH
  recent AS (
    SELECT
      *
    FROM
      orders
    WHERE
      created_at > NOW() - INTERVAL '30 days'
      AND status <> 'cancelled'
  )
SELECT
  u.id,
  u.name,
  COUNT(o.id) AS order_count,
  SUM(o.total) total,
  CASE
    WHEN SUM(o.total) > 1000 THEN 'gold'
    WHEN SUM(o.total) > 100 THEN 'silver'
    ELSE 'bronze'
  END AS tier
FROM
  users u
  LEFT JOIN recent o ON o.user_id = u.id
WHERE
  u.active = 1
  AND u.age BETWEEN 18 AND 65
GROUP BY
  u.id,
  u.name
HAVING
  COUNT(o.id) > 5
ORDER BY
  total DESC
LIMIT 10;
