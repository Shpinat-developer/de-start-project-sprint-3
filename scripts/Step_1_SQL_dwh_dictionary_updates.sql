/* создание таблицы tmp_sources с данными из всех источников */
DROP TABLE IF EXISTS tmp_sources;

CREATE TEMP TABLE tmp_sources AS 
/* скрипт для сборки датасета */
(
select 
order_id, order_created_date, order_completion_date, order_status, craftsman_id, craftsman_name, craftsman_address,
craftsman_birthday, craftsman_email, product_id, product_name, product_description, product_type, product_price,
customer_id, customer_name, customer_address, customer_birthday, customer_email
from source1.craft_market_wide
union 
select
order_id, order_created_date, order_completion_date, order_status, a.craftsman_id, craftsman_name, craftsman_address,
craftsman_birthday, craftsman_email, a.product_id, product_name, product_description, product_type, product_price,
customer_id, customer_name, customer_address, customer_birthday, customer_email
from source2.craft_market_orders_customers a
join source2.craft_market_masters_products b
on a.craftsman_id = b.craftsman_id
and a.product_id=b.product_id
union 
select 
order_id, order_created_date, order_completion_date, order_status, a.craftsman_id, craftsman_name, craftsman_address,
craftsman_birthday, craftsman_email, product_id, product_name, product_description, product_type, product_price,
a.customer_id, customer_name, customer_address, customer_birthday, customer_email
from source3.craft_market_orders a
join source3.craft_market_craftsmans b
on a.craftsman_id = b.craftsman_id
join  source3.craft_market_customers c
on c.customer_id = a.customer_id
union
select 
order_id, order_created_date, order_completion_date, order_status, a.craftsman_id, craftsman_name, craftsman_address,
craftsman_birthday, craftsman_email, product_id, product_name, product_description, product_type, product_price,
a.customer_id, customer_name, customer_address, customer_birthday, customer_email
from external_source.craft_products_orders a
join external_source.customers b
on a.customer_id = b.customer_id
) ;

/* обновление существующих записей и добавление новых в dwh.d_craftsmans */
MERGE INTO dwh.d_craftsman d
USING (SELECT DISTINCT craftsman_name, craftsman_address, craftsman_birthday, craftsman_email FROM tmp_sources) t
ON d.craftsman_name = t.craftsman_name
and d.craftsman_email = t.craftsman_email
WHEN MATCHED THEN
  UPDATE SET craftsman_address = t.craftsman_address, 
craftsman_birthday = t.craftsman_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (craftsman_name, craftsman_address, craftsman_birthday, craftsman_email, load_dttm)
  VALUES (t.craftsman_name, t.craftsman_address, t.craftsman_birthday, t.craftsman_email, current_timestamp);
/* обновление существующих записей и добавление новых в dwh.d_products*/
MERGE INTO dwh.d_product d
USING (SELECT DISTINCT product_name, product_description, product_type, product_price from tmp_sources) t
ON d.product_name = t.product_name
and d.product_description = t.product_description
and d.product_price = t.product_price
WHEN MATCHED THEN
  UPDATE SET product_type = t.product_type, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (product_name, product_description, product_type, product_price, load_dttm)
  VALUES (t.product_name, t.product_description, t.product_type, t.product_price, current_timestamp);
/* обновление существующих записей и добавление новых в dwh.d_customer*/
MERGE INTO dwh.d_customer d
USING (SELECT DISTINCT customer_name, customer_address, customer_birthday, customer_email from tmp_sources) t
ON d.customer_name = t.customer_name
and d.customer_email = t.customer_email
WHEN MATCHED THEN
  UPDATE SET customer_address = t.customer_address, customer_birthday = t.customer_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  insert (customer_name, customer_address, customer_birthday, customer_email, load_dttm)
  values (t.customer_name, t.customer_address, t.customer_birthday, t.customer_email, current_timestamp );
