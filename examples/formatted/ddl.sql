CREATE TABLE orders (
  id bigserial PRIMARY KEY,
  user_id bigint NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total numeric(12, 2) NOT NULL DEFAULT 0,
  status varchar(20) CHECK (status IN ('new', 'paid', 'cancelled')),
  created_at timestamp DEFAULT NOW()
);

CREATE OR REPLACE VIEW paid_orders AS
SELECT
  id,
  user_id,
  total
FROM
  orders
WHERE
  status = 'paid';
