-- =====================================================================
-- STAGING OLIST - tabelas temporárias que recebem os CSVs crus
-- Executar no Query Tool do banco dw_olist.
-- Tudo é TEXT de propósito: a conversão de tipos é feita no script
-- da fato (03_carga_fato_vendas.sql), evitando problemas de formato
-- de data e de decimal (o Pentaho está configurado com vírgula decimal).
-- =====================================================================

DROP SCHEMA IF EXISTS stg CASCADE;
CREATE SCHEMA stg;

CREATE TABLE stg.customers (
    customer_id              TEXT,
    customer_unique_id       TEXT,
    customer_zip_code_prefix TEXT,
    customer_city            TEXT,
    customer_state           TEXT
);

CREATE TABLE stg.orders (
    order_id                       TEXT,
    customer_id                    TEXT,
    order_status                   TEXT,
    order_purchase_timestamp       TEXT,
    order_approved_at              TEXT,
    order_delivered_carrier_date   TEXT,
    order_delivered_customer_date  TEXT,
    order_estimated_delivery_date  TEXT
);

CREATE TABLE stg.order_items (
    order_id             TEXT,
    order_item_id        TEXT,
    product_id           TEXT,
    seller_id            TEXT,
    shipping_limit_date  TEXT,
    price                TEXT,
    freight_value        TEXT
);

CREATE TABLE stg.order_reviews (
    review_id                TEXT,
    order_id                 TEXT,
    review_score             TEXT,
    review_comment_title     TEXT,
    review_comment_message   TEXT,
    review_creation_date     TEXT,
    review_answer_timestamp  TEXT
);

-- Conferência (após carregar pelo Pentaho):
-- SELECT 'customers' t, COUNT(*) FROM stg.customers      -- ~99441
-- UNION ALL SELECT 'orders', COUNT(*) FROM stg.orders    -- ~99441
-- UNION ALL SELECT 'order_items', COUNT(*) FROM stg.order_items   -- ~112650
-- UNION ALL SELECT 'order_reviews', COUNT(*) FROM stg.order_reviews; -- ~99224
