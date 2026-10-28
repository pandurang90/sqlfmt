SELECT
  name
FROM
  (
    SELECT
      u.name,
      (
        SELECT
          COUNT(*)
        FROM
          orders o
        WHERE
          o.user_id = u.id
      ) AS n
    FROM
      users u
  ) counts
WHERE
  n > (
    SELECT
      AVG(n)
    FROM
      (
        SELECT
          COUNT(*) n
        FROM
          orders
        GROUP BY
          user_id
      ) per_user
  )
  AND EXISTS (
    SELECT
      1
    FROM
      reviews r
    WHERE
      r.author = counts.name
  )
UNION
SELECT
  name
FROM
  vip_users
