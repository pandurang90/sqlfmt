/* Monthly revenue report
   owner: data team */
SELECT
  -- the month bucket
  DATE_TRUNC('month', created_at) AS month, -- truncated
  SUM(total) /* gross */ AS revenue
FROM
  orders -- only real orders
WHERE
  status = 'paid' -- exclude refunds
GROUP BY
  1;
