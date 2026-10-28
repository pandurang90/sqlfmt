-- Top customers in the last 30 days
with recent as (select * from orders where created_at > now() - interval '30 days' and status <> 'cancelled')
select u.id, u.name, count(o.id) as order_count, sum(o.total) total,
case when sum(o.total) > 1000 then 'gold' when sum(o.total) > 100 then 'silver' else 'bronze' end as tier
from users u left join recent o on o.user_id = u.id where u.active = 1 and u.age between 18 and 65
group by u.id, u.name having count(o.id) > 5 order by total desc limit 10;
