WITH
-- Формируем дельту: новые и изменённые записи DWH, которые требуют вставки либо пересчёта витрины в разрезе customer_id + report_period.
dwh_delta AS (
SELECT     
            dcs.customer_id AS customer_id,
            dcs.customer_name AS customer_name,
            dcs.customer_address AS customer_address,
            dcs.customer_birthday AS customer_birthday,
            dcs.customer_email AS customer_email,
            fo.order_id AS order_id,
            dp.product_id AS product_id,
            dp.product_price AS product_price,
            dp.product_type AS product_type,
            fo.order_completion_date - fo.order_created_date AS diff_order_date, 
            fo.order_status AS order_status,
            TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period,
            dc.craftsman_id  AS craftsman_id,
            dc.craftsman_name  AS craftsman_name,
            crd.customer_id AS exist_customer_id,
            dc.load_dttm AS craftsman_load_dttm,
            dcs.load_dttm AS customers_load_dttm,
            dp.load_dttm AS products_load_dttm,
            fo.load_dttm as order_load_dttm
            FROM dwh.f_order fo 
                INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
                INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
                INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id 
                LEFT JOIN dwh.customer_report_datamart crd ON dcs.customer_id = crd.customer_id and TO_CHAR(fo.order_created_date, 'yyyy-mm') = crd.report_period
                    WHERE (fo.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                            (dc.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                            (dcs.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                            (dp.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) 
), 
--выборка клиентов по которым надо будет сделать update
dwh_update_delta AS (
SELECT     distinct
            dd.exist_customer_id AS customer_id,
            dd.report_period
            FROM dwh_delta dd 
                WHERE dd.exist_customer_id IS NOT NULL     
),
--расчет самого популярного мастера для каждого клиента по всей витрине заказов
dwh_craftsman_id_update as (
select distinct on (customer_id) customer_id, craftsman_id from (
SELECT 
			customer_id,
			craftsman_id,
			count(order_id) as count_order
				from dwh.f_order f
					group by customer_id, craftsman_id
					) t order by customer_id, count_order desc, craftsman_id
),
--расчет витрины по новым данным
dwh_delta_insert_result AS (
SELECT 
			T1.customer_id,
			T1.customer_name,
			T1.customer_address,
			T1.customer_birthday,
			T1.customer_email,
			T1.customer_money,
			T1.platform_money,
			T1.count_order,
			T1.avg_price_order,
			T1.median_time_order_completed,
			T5.product_type as top_product_category,
			T4.craftsman_id as most_popular_craftsman_id,
			T1.count_order_created,
			T1.count_order_in_progress,
			T1.count_order_delivery,
			T1.count_order_done,
			T1.count_order_not_done,
			T1.report_period
			FROM (
                    --считаем основную часть столбцов 
					SELECT 
							a.customer_id,
							a.customer_name,
							a.customer_address,
							a.customer_birthday,
							a.customer_email,
							SUM(a.product_price) AS customer_money,
							SUM(a.product_price) * 0.1 AS platform_money,
							count(a.order_id) as count_order,
							AVG(a.product_price) AS avg_price_order,
							PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY a.diff_order_date) AS median_time_order_completed,
							SUM(CASE WHEN a.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created,
							SUM(CASE WHEN a.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress, 
							SUM(CASE WHEN a.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery, 
							SUM(CASE WHEN a.order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done, 
							SUM(CASE WHEN a.order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
							a.report_period AS report_period
					FROM dwh_delta a
						WHERE a.exist_customer_id is null
								GROUP BY 
									a.customer_id,
									a.customer_name,
									a.customer_address,
									a.customer_birthday,
									a.customer_email,
									a.report_period
) T1

JOIN 

----определяем самы популярный товар у клиента
(
SELECT 
			DISTINCT ON (customer_id, report_period)
    		customer_id AS customer_id_for_product_type,
   			product_type,
    		count_product, 
    		report_period
					FROM
		(SELECT    
					dd.customer_id AS customer_id, 
					dd.product_type, 
					COUNT(dd.product_id) AS count_product,
					report_period
						FROM dwh_delta AS dd
							WHERE dd.exist_customer_id is null
								GROUP BY dd.customer_id, dd.product_type, dd.report_period
) T2
			ORDER BY customer_id, report_period, count_product desc, product_type

)T5

ON T1.customer_id = T5.customer_id_for_product_type
AND T1.report_period = T5.report_period

---определяем самого популярного мастера у клиента
JOIN dwh_craftsman_id_update T4 ON T1.customer_id = T4.customer_id
),
---пересчет для существующих записей в витрине в разрезе customer_id + report_period
dwh_delta_update_result AS ( 
SELECT 
			T1.customer_id,
			T1.customer_name,
			T1.customer_address,
			T1.customer_birthday,
			T1.customer_email,
			T1.customer_money,
			T1.platform_money,
			T1.count_order,
			T1.avg_price_order,
			T1.median_time_order_completed,
			T5.product_type as top_product_category,
			T4.craftsman_id as most_popular_craftsman_id,
			T1.count_order_created,
			T1.count_order_in_progress,
			T1.count_order_delivery,
			T1.count_order_done,
			T1.count_order_not_done,
			T1.report_period
                        FROM (
                             --считаем основную часть столбцов 
                            SELECT 
                                a.customer_id AS customer_id,
                                a.customer_name AS customer_name,
                                a.customer_address AS customer_address,
                                a.customer_birthday AS customer_birthday,
                                a.customer_email AS customer_email,
                                SUM(a.product_price) AS customer_money,
                                SUM(a.product_price) * 0.1 AS platform_money,
                                COUNT(order_id) AS count_order,
                                AVG(a.product_price) AS avg_price_order,
                                PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY diff_order_date) AS median_time_order_completed,
                                SUM(CASE WHEN a.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created, 
                                SUM(CASE WHEN a.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress, 
                                SUM(CASE WHEN a.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery, 
                                SUM(CASE WHEN a.order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done, 
                                SUM(CASE WHEN a.order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
                                a.report_period AS report_period
                                	FROM (
                                    	SELECT     
                                        		    dcs.customer_id AS customer_id,
                                            		dcs.customer_name AS customer_name,
		                                            dcs.customer_address AS customer_address,
		                                            dcs.customer_birthday AS customer_birthday,
		                                            dcs.customer_email AS customer_email,
		                                            fo.order_id AS order_id,
		                                            dp.product_id AS product_id,
		                                            dp.product_price AS product_price,
		                                            dp.product_type AS product_type,
		                                            fo.order_completion_date - fo.order_created_date AS diff_order_date,
		                                            fo.order_status AS order_status, 
		                                            TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period
		                                            	FROM dwh.f_order fo 
		                                                		INNER JOIN dwh.d_craftsman dc ON fo.craftsman_id = dc.craftsman_id 
		                                                		INNER JOIN dwh.d_customer dcs ON fo.customer_id = dcs.customer_id 
		                                                		INNER JOIN dwh.d_product dp ON fo.product_id = dp.product_id
		                                                		INNER JOIN dwh_update_delta ud ON fo.customer_id = ud.customer_id and TO_CHAR(fo.order_created_date, 'yyyy-mm') = ud.report_period
		                                ) AS a
                                    GROUP BY a.customer_id, a.customer_name, a.customer_address, a.customer_birthday, a.customer_email, a.report_period
                            ) AS T1 
                            
JOIN
---определяем самый популярный товар у клиента
(SELECT 
					DISTINCT ON (customer_id, report_period)
    				customer_id AS customer_id_for_product_type,
    				product_type,
    				count_product, 
    				report_period
							FROM
									(SELECT     
												fo.customer_id AS customer_id, 
												dp.product_type, 
												COUNT(fo.order_id) AS count_product,
												ud.report_period
													FROM dwh.f_order fo 
													       INNER JOIN dwh_update_delta ud ON fo.customer_id = ud.customer_id and TO_CHAR(fo.order_created_date, 'yyyy-mm') = ud.report_period
													       INNER JOIN dwh.d_product dp on fo.product_id = dp.product_id
															GROUP BY fo.customer_id, dp.product_type, ud.report_period
									) T2
					ORDER BY customer_id, report_period,count_product desc, product_type
) T5
ON T1.customer_id = T5.customer_id_for_product_type
AND T1.report_period = T5.report_period

---определяем самого популярного мастера у клиента
JOIN dwh_craftsman_id_update T4 ON T1.customer_id = T4.customer_id
),
---выполняем insert новых расчитанных данных для витрины
insert_delta AS ( 
    INSERT INTO dwh.customer_report_datamart (
         customer_id,
         customer_name,
         customer_address,
         customer_birthday, 
         customer_email, 
         customer_money, 
         platform_money, 
         count_order, 
         avg_price_order, 
         median_time_order_completed,
         top_product_category, 
         most_popular_craftsman_id,
         count_order_created, 
         count_order_in_progress, 
         count_order_delivery, 
         count_order_done, 
         count_order_not_done, 
         report_period
    ) SELECT 
         customer_id,
         customer_name,
         customer_address,
         customer_birthday, 
         customer_email, 
         customer_money, 
         platform_money, 
         count_order, 
         avg_price_order, 
         median_time_order_completed,
         top_product_category, 
         most_popular_craftsman_id,
         count_order_created, 
         count_order_in_progress, 
         count_order_delivery, 
         count_order_done, 
         count_order_not_done, 
         report_period
            FROM dwh_delta_insert_result
),
-- выполняем обновление показателей в отчёте по уже существующим мастерам
update_delta AS ( 
    UPDATE dwh.customer_report_datamart SET
        customer_name = updates.customer_name, 
        customer_address = updates.customer_address, 
        customer_birthday = updates.customer_birthday, 
        customer_email = updates.customer_email, 
        customer_money = updates.customer_money, 
        platform_money = updates.platform_money, 
        count_order = updates.count_order, 
        avg_price_order = updates.avg_price_order, 
        median_time_order_completed = updates.median_time_order_completed, 
        top_product_category = updates.top_product_category, 
        most_popular_craftsman_id = updates.most_popular_craftsman_id,
        count_order_created = updates.count_order_created, 
        count_order_in_progress = updates.count_order_in_progress, 
        count_order_delivery = updates.count_order_delivery, 
        count_order_done = updates.count_order_done,
        count_order_not_done = updates.count_order_not_done
    FROM (
        SELECT 
          customer_id,
         customer_name,
         customer_address,
         customer_birthday, 
         customer_email, 
         customer_money, 
         platform_money, 
         count_order, 
         avg_price_order, 
         median_time_order_completed,
         top_product_category, 
         most_popular_craftsman_id,
         count_order_created, 
         count_order_in_progress, 
         count_order_delivery, 
         count_order_done, 
         count_order_not_done, 
         report_period
            FROM dwh_delta_update_result) AS updates
   				 WHERE dwh.customer_report_datamart.customer_id = updates.customer_id
        		 AND dwh.customer_report_datamart.report_period = updates.report_period
),
insert_load_date AS ( 
-- делаем запись в таблицу загрузок о том, когда была совершена загрузка
    INSERT INTO dwh.load_dates_customer_report_datamart (
        load_dttm
    )
    SELECT GREATEST(coalesce(MAX(order_load_dttm), TIMESTAMP '1900-01-01'),
    				coalesce(MAX(craftsman_load_dttm), TIMESTAMP '1900-01-01'), 
                    coalesce(MAX(customers_load_dttm), TIMESTAMP '1900-01-01'), 
                    coalesce(MAX(products_load_dttm), TIMESTAMP '1900-01-01')) 
        FROM dwh_delta
        HAVING COUNT(*) > 0
)
SELECT 'increment datamart'; -- инициализируем запрос CTE 