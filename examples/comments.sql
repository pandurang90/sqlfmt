/* Monthly revenue report
   owner: data team */
select
-- the month bucket
date_trunc('month', created_at) as month, -- truncated
sum(total) /* gross */ as revenue
from orders -- only real orders
where status = 'paid' -- exclude refunds
group by 1;
