-- =====================================================================
-- DATA WAREHOUSE OLIST (E-COMMERCE) - MODELO ESTRELA - PostgreSQL
-- Como usar: no pgAdmin, crie um banco chamado "dw_olist",
-- abra o Query Tool nele e execute este script inteiro.
-- =====================================================================

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;
SET search_path TO dw;

-- ---------------------------------------------------------------------
-- DIMENSÃO TEMPO (populada aqui mesmo, não precisa de ETL)
-- Chave: sk_tempo no formato AAAAMMDD (ex.: 20180315)
-- ---------------------------------------------------------------------
CREATE TABLE dim_tempo (
    sk_tempo        INTEGER PRIMARY KEY,
    data            DATE NOT NULL UNIQUE,
    ano             SMALLINT NOT NULL,
    trimestre       SMALLINT NOT NULL,
    mes             SMALLINT NOT NULL,
    nome_mes        VARCHAR(15) NOT NULL,
    ano_mes         CHAR(7) NOT NULL,          -- ex.: 2018-03
    dia             SMALLINT NOT NULL,
    dia_semana      SMALLINT NOT NULL,         -- 1=segunda ... 7=domingo
    nome_dia_semana VARCHAR(15) NOT NULL,
    fim_de_semana   BOOLEAN NOT NULL
);

INSERT INTO dim_tempo
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INTEGER,
    d::DATE,
    EXTRACT(YEAR FROM d),
    EXTRACT(QUARTER FROM d),
    EXTRACT(MONTH FROM d),
    (ARRAY['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho',
           'Agosto','Setembro','Outubro','Novembro','Dezembro'])[EXTRACT(MONTH FROM d)::INT],
    TO_CHAR(d, 'YYYY-MM'),
    EXTRACT(DAY FROM d),
    EXTRACT(ISODOW FROM d),
    (ARRAY['Segunda','Terça','Quarta','Quinta','Sexta','Sábado','Domingo'])[EXTRACT(ISODOW FROM d)::INT],
    EXTRACT(ISODOW FROM d) IN (6, 7)
FROM generate_series('2016-01-01'::DATE, '2018-12-31'::DATE, INTERVAL '1 day') AS d;

-- ---------------------------------------------------------------------
-- DIMENSÃO CLIENTE
-- Chave natural: customer_unique_id (a pessoa), e não customer_id,
-- que na Olist muda a cada pedido.
-- ---------------------------------------------------------------------
CREATE TABLE dim_cliente (
    sk_cliente          SERIAL PRIMARY KEY,
    customer_unique_id  VARCHAR(50) NOT NULL UNIQUE,
    cidade              VARCHAR(100),
    estado              CHAR(2)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO PRODUTO
-- ---------------------------------------------------------------------
CREATE TABLE dim_produto (
    sk_produto      SERIAL PRIMARY KEY,
    product_id      VARCHAR(50) NOT NULL UNIQUE,
    categoria       VARCHAR(100),               -- em português (original)
    categoria_en    VARCHAR(100),               -- tradução (tabela de tradução)
    peso_g          NUMERIC(10,2),
    comprimento_cm  NUMERIC(10,2),
    altura_cm       NUMERIC(10,2),
    largura_cm      NUMERIC(10,2)
);

-- ---------------------------------------------------------------------
-- DIMENSÃO VENDEDOR
-- ---------------------------------------------------------------------
CREATE TABLE dim_vendedor (
    sk_vendedor  SERIAL PRIMARY KEY,
    seller_id    VARCHAR(50) NOT NULL UNIQUE,
    cidade       VARCHAR(100),
    estado       CHAR(2)
);

-- ---------------------------------------------------------------------
-- TABELA FATO VENDAS
-- Granularidade: 1 linha = 1 ITEM de pedido (order_id + order_item_id)
-- Dimensão tempo usada 3 vezes (role-playing): compra, entrega
-- estimada e entrega real.
-- ---------------------------------------------------------------------
CREATE TABLE fato_vendas (
    sk_venda                 BIGSERIAL PRIMARY KEY,
    order_id                 VARCHAR(50) NOT NULL,
    order_item_id            SMALLINT NOT NULL,
    sk_cliente               INTEGER NOT NULL REFERENCES dim_cliente(sk_cliente),
    sk_produto               INTEGER NOT NULL REFERENCES dim_produto(sk_produto),
    sk_vendedor              INTEGER NOT NULL REFERENCES dim_vendedor(sk_vendedor),
    sk_tempo_compra          INTEGER NOT NULL REFERENCES dim_tempo(sk_tempo),
    sk_tempo_entrega_prev    INTEGER REFERENCES dim_tempo(sk_tempo),
    sk_tempo_entrega_real    INTEGER REFERENCES dim_tempo(sk_tempo),  -- nulo se não entregue
    status_pedido            VARCHAR(20),
    -- Métricas
    preco                    NUMERIC(10,2),
    valor_frete              NUMERIC(10,2),
    valor_total              NUMERIC(10,2),     -- preco + valor_frete
    dias_entrega             INTEGER,           -- entrega real - compra
    dias_atraso              INTEGER,           -- entrega real - prevista (>0 = atrasou)
    atrasou                  SMALLINT,          -- 1 = atrasou, 0 = no prazo
    nota_avaliacao           SMALLINT,          -- 1 a 5 (nota do pedido)
    UNIQUE (order_id, order_item_id)
);

CREATE INDEX idx_fato_cliente  ON fato_vendas(sk_cliente);
CREATE INDEX idx_fato_produto  ON fato_vendas(sk_produto);
CREATE INDEX idx_fato_vendedor ON fato_vendas(sk_vendedor);
CREATE INDEX idx_fato_compra   ON fato_vendas(sk_tempo_compra);

-- Conferência rápida:
-- SELECT COUNT(*) FROM dw.dim_tempo;   -- deve retornar 1096
