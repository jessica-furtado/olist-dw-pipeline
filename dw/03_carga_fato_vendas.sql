-- =====================================================================
-- CARGA DA FATO_VENDAS
-- Pré-requisitos: dim_cliente, dim_produto, dim_vendedor carregadas
-- (Pentaho) e tabelas stg.* carregadas (Pentaho).
-- Granularidade: 1 linha = 1 item de pedido.
-- Pode ser executado várias vezes: o script limpa a fato antes.
-- =====================================================================

TRUNCATE dw.fato_vendas RESTART IDENTITY;

INSERT INTO dw.fato_vendas (
    order_id, order_item_id,
    sk_cliente, sk_produto, sk_vendedor,
    sk_tempo_compra, sk_tempo_entrega_prev, sk_tempo_entrega_real,
    status_pedido,
    preco, valor_frete, valor_total,
    dias_entrega, dias_atraso, atrasou,
    nota_avaliacao
)
WITH pedidos AS (
    SELECT
        order_id,
        customer_id,
        order_status,
        NULLIF(order_purchase_timestamp, '')::timestamp      AS dt_compra,
        NULLIF(order_estimated_delivery_date, '')::timestamp AS dt_prevista,
        NULLIF(order_delivered_customer_date, '')::timestamp AS dt_entrega
    FROM stg.orders
),
notas AS (
    -- Alguns pedidos têm mais de uma avaliação: usamos a média arredondada.
    -- O filtro ignora linhas quebradas por comentários com quebra de linha.
    SELECT
        order_id,
        ROUND(AVG(review_score::numeric))::smallint AS nota
    FROM stg.order_reviews
    WHERE review_score ~ '^[1-5]$'
    GROUP BY order_id
)
SELECT
    i.order_id,
    i.order_item_id::smallint,
    c.sk_cliente,
    p.sk_produto,
    v.sk_vendedor,
    TO_CHAR(o.dt_compra,   'YYYYMMDD')::int,
    TO_CHAR(o.dt_prevista, 'YYYYMMDD')::int,
    TO_CHAR(o.dt_entrega,  'YYYYMMDD')::int,
    o.order_status,
    i.price::numeric(10,2),
    i.freight_value::numeric(10,2),
    (i.price::numeric + i.freight_value::numeric)::numeric(10,2),
    (o.dt_entrega::date - o.dt_compra::date),
    (o.dt_entrega::date - o.dt_prevista::date),
    CASE
        WHEN o.dt_entrega IS NULL THEN NULL
        WHEN o.dt_entrega::date > o.dt_prevista::date THEN 1
        ELSE 0
    END,
    n.nota
FROM stg.order_items i
JOIN pedidos          o  ON o.order_id = i.order_id
JOIN stg.customers    sc ON sc.customer_id = o.customer_id
JOIN dw.dim_cliente   c  ON c.customer_unique_id = sc.customer_unique_id
JOIN dw.dim_produto   p  ON p.product_id = i.product_id
JOIN dw.dim_vendedor  v  ON v.seller_id = i.seller_id
LEFT JOIN notas       n  ON n.order_id = i.order_id;

-- Conferências:
-- SELECT COUNT(*) FROM dw.fato_vendas;                 -- esperado: 112650
-- SELECT COUNT(*) FROM dw.fato_vendas WHERE nota_avaliacao IS NULL;
-- SELECT status_pedido, COUNT(*) FROM dw.fato_vendas GROUP BY 1 ORDER BY 2 DESC;
-- SELECT ROUND(AVG(atrasou)*100,1) AS pct_atraso FROM dw.fato_vendas;
