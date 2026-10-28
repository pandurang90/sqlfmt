SELECT
  department,
  employee,
  salary,
  RANK() OVER (PARTITION BY department ORDER BY salary DESC) AS dept_rank,
  SUM(salary) OVER (PARTITION BY department) dept_total,
  LAG(salary, 1) OVER (ORDER BY hired_at ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) prev_salary
FROM
  employees
WHERE
  salary BETWEEN 50000 AND 200000 qualify dept_rank <= 3
