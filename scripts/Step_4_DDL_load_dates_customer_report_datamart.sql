DROP TABLE IF EXISTS dwh.load_dates_customer_report_datamart;

CREATE TABLE IF NOT EXISTS dwh.load_dates_customer_report_datamart (
id BIGINT GENERATED ALWAYS AS IDENTITY NOT NULL,
load_dttm date not null,
constraint load_dates_customer_report_datamart_pk primary key  (id)
);