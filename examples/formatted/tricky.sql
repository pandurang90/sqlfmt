SELECT
  'select * from where',
  "order",
  t."group",
  [from],
  `limit`,
  t.select,
  count,
  COUNT(*),
  a::text,
  data ->> 'name',
  -1 * x,
  arr[2],
  .5,
  1e-3,
  $$it's a $tag$ string$$,
  E'line\n',
  N'naïve'
FROM
  t
WHERE
  id = $1
  AND slug = :slug
  AND a IS DISTINCT FROM b
  AND created_at at time zone 'UTC' > NOW()
