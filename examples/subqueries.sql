select name from (select u.name, (select count(*) from orders o where o.user_id = u.id) as n from users u) counts where n > (select avg(n) from (select count(*) n from orders group by user_id) per_user) and exists (select 1 from reviews r where r.author = counts.name)
union
select name from vip_users
