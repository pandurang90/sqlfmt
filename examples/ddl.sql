create table orders (id bigserial primary key, user_id bigint not null references users(id) on delete cascade, total numeric(12,2) not null default 0, status varchar(20) check (status in ('new','paid','cancelled')), created_at timestamp default now());
create or replace view paid_orders as select id, user_id, total from orders where status = 'paid';
