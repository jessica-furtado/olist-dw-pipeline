# Documentação da Arquitetura de Dados (Pentaho + PostgreSQL)

Projeto: Olist E-commerce — Data Warehouse, EDA e Dashboard
Ferramentas: Pentaho Data Integration (PDI) Community 9.4, PostgreSQL 16, pgAdmin 4

---

## 1. Visão geral

```
                 ┌──────────────────────────── PENTAHO (PDI) ────────────────────────────┐
CSVs da Olist ──▶│ trf_dim_vendedor   trf_dim_produto   trf_dim_cliente   trf_staging     │
                 └───────┬──────────────────┬────────────────┬────────────────┬──────────┘
                         ▼                  ▼                ▼                ▼
                 ┌──────────────── PostgreSQL: banco dw_olist ───────────────────────────┐
                 │  schema dw: dim_vendedor, dim_produto, dim_cliente, dim_tempo         │
                 │  schema stg: customers, orders, order_items, order_reviews            │
                 │                         │                                             │
                 │         03_carga_fato_vendas.sql (SQL)                                │
                 │                         ▼                                             │
                 │  schema dw: fato_vendas  (esquema estrela)                            │
                 └──────────────┬──────────────────────────────┬─────────────────────────┘
                                ▼                              ▼
                        Python (EDA, notebook)          Power BI (dashboard)
```

**Abordagem:** o Pentaho faz a extração e a carga (ETL das dimensões e da staging), e a montagem da tabela fato é feita em SQL dentro do banco (ELT). A escolha é justificada na seção 5.

## 2. Ambiente e conexão

| Item | Valor |
|---|---|
| Banco | `dw_olist` (PostgreSQL 16, localhost:5432) |
| Schemas | `dw` (modelo dimensional) e `stg` (staging) |
| Conexão no PDI | `dw_olist`, tipo PostgreSQL, acesso Native (JDBC) |
| Fonte dos dados | CSVs da Olist em `C:\olist\archive` |
| Codificação dos CSVs | UTF-8, delimitador `,`, enclosure `"`, com cabeçalho |

## 3. Ordem de execução

1. `dw/01_modelo_dw_olist.sql`: cria o schema `dw`, as dimensões, a fato e a `dim_tempo` (populada por SQL).
2. `dw/02_staging_olist.sql`: cria o schema `stg` com as tabelas de staging.
3. Pentaho: `trf_dim_vendedor`, `trf_dim_produto` e `trf_dim_cliente`.
4. Pentaho: `trf_staging`.
5. `dw/03_carga_fato_vendas.sql`: carrega a `fato_vendas`.

As dimensões precisam ser carregadas **antes** da fato, porque a fato referencia as chaves substitutas (`sk_*`).

## 4. Descrição de cada transformação

### 4.1 `trf_dim_vendedor`
`CSV file input` → `Table output`
- **Entrada:** `olist_sellers_dataset.csv` (`seller_id`, `seller_zip_code_prefix`, `seller_city`, `seller_state`).
- **Destino:** `dw.dim_vendedor`.
- **Mapeamento:** `seller_id` → `seller_id`; `seller_city` → `cidade`; `seller_state` → `estado`. O CEP não é carregado, e a chave `sk_vendedor` é gerada pelo banco (SERIAL).
- **Conferência:** 3.095 linhas.

### 4.2 `trf_dim_produto`
`CSV produtos` e `CSV traducao` → `Stream lookup` → `Select values` → `Table output`
- **Entradas:** `olist_products_dataset.csv` e `product_category_name_translation.csv`.
- **Stream lookup:** junta a tradução pela chave `product_category_name` e traz `product_category_name_english`. Equivale a um *left join*: produtos sem categoria, ou com categoria fora da tabela de tradução, ficam com `categoria_en` vazio.
- **Select values:** mantém e renomeia 7 campos: `product_id`; `product_category_name` → `categoria`; `product_category_name_english` → `categoria_en`; `product_weight_g` → `peso_g`; `product_length_cm` → `comprimento_cm`; `product_height_cm` → `altura_cm`; `product_width_cm` → `largura_cm`. Os campos de tamanho do nome, da descrição e de quantidade de fotos são descartados, por não terem uso analítico.
- **Destino:** `dw.dim_produto`.
- **Conferência:** 32.951 linhas.

### 4.3 `trf_dim_cliente`
`CSV file input` → `Unique rows (HashSet)` → `Table output`
- **Entrada:** `olist_customers_dataset.csv`.
- **Unique rows (HashSet):** remove repetições pelo campo `customer_unique_id`. Na Olist, o `customer_id` muda a cada pedido, então a mesma pessoa aparece várias vezes. A dimensão deve ter uma linha por pessoa.
- **Mapeamento:** `customer_unique_id` → `customer_unique_id`; `customer_city` → `cidade`; `customer_state` → `estado`.
- **Destino:** `dw.dim_cliente` (cerca de 96 mil clientes únicos, a partir de 99.441 linhas no arquivo).

### 4.4 `trf_staging`
Quatro pares independentes `CSV file input` → `Table output`:

| CSV | Tabela de destino |
|---|---|
| `olist_customers_dataset.csv` | `stg.customers` |
| `olist_orders_dataset.csv` | `stg.orders` |
| `olist_order_items_dataset.csv` | `stg.order_items` |
| `olist_order_reviews_dataset.csv` | `stg.order_reviews` |

- As tabelas de staging têm todas as colunas em texto. A conversão de tipos (datas e decimais) é feita no SQL da fato, evitando divergências de formato entre o Pentaho (configurado em padrão brasileiro) e o PostgreSQL.
- No CSV de avaliações, a opção *New line possible in fields?* trata comentários com quebra de linha.

### 4.5 Carga da fato (`dw/03_carga_fato_vendas.sql`)
- **Granularidade:** 1 linha por item de pedido (`order_id` + `order_item_id`).
- **Junções:** itens → pedidos → clientes (staging) → `dim_cliente`, `dim_produto` e `dim_vendedor` pelas chaves naturais, convertidas em chaves substitutas. As avaliações entram por `LEFT JOIN`, usando a média arredondada quando um pedido tem mais de uma nota.
- **Métricas calculadas:** `valor_total` (preço + frete), `dias_entrega` (entrega real − compra), `dias_atraso` (entrega real − prevista) e `atrasou` (1 se `dias_atraso` > 0, 0 se no prazo, nulo se não entregue).
- **Dimensão tempo (role-playing):** a mesma `dim_tempo` é usada três vezes: `sk_tempo_compra`, `sk_tempo_entrega_prev` e `sk_tempo_entrega_real`.
- **Conferência:** 112.650 linhas, igual ao total de itens de pedido da Olist, o que indica que nenhuma linha se perdeu nas junções.

## 5. Decisões de arquitetura

| Decisão | Justificativa |
|---|---|
| Esquema estrela | Simples de consultar e eficiente no Power BI; cada dimensão se liga à fato por uma chave. |
| Granularidade em item de pedido | É o nível mais detalhado e permite análise por produto, vendedor e cliente sem perda de informação. |
| Chaves substitutas (`sk_*`) | Isolam o DW das chaves dos sistemas de origem, que são textos longos e, no caso do cliente, instáveis. |
| Cliente por `customer_unique_id` | Identifica a pessoa, e não o pedido. |
| `dim_tempo` gerada por SQL | Não depende de arquivo de origem e cobre todo o período com todos os atributos de calendário. |
| ELT para a fato | A fato exige junções de quatro fontes e cálculos de datas. Em SQL, ficam mais legíveis e mais rápidos do que em vários passos do Pentaho. |
| Staging em texto | Evita erros de tipo e de formato na carga, e a conversão fica concentrada em um só ponto. |
| Pagamentos fora do modelo | São por pedido, e colocá-los no nível de item duplicaria valores. |
| Sem `TRUNCATE` nas dimensões | A `fato_vendas` referencia as dimensões por chave estrangeira, e o banco bloqueia o truncamento. Para recarregar: `TRUNCATE dw.dim_x RESTART IDENTITY CASCADE`, e depois recarregar a fato. |

## 6. Problemas encontrados e soluções

| Problema | Causa | Solução |
|---|---|---|
| Campos do CSV vinham colados em um só | Aspa tipográfica no campo *Enclosure* | Digitar a aspa reta `"` pelo teclado e usar *Obtem campos* de novo. |
| `Unable to find field [product_category_name]` | Caractere invisível (BOM) no início da primeira coluna do CSV de tradução | Redigitar o nome do campo na tabela de campos do `CSV file input`. |
| `não é possível truncar uma tabela referenciada em uma restrição de chave estrangeira` | Opção *Truncate table* marcada em uma dimensão referenciada pela fato | Desmarcar a opção; usar `TRUNCATE ... CASCADE` só quando for recarregar tudo. |
| `coluna "order_id" da relação "customers" não existe` | Ao copiar os pares de entrada e saída, o *Target table* foi copiado junto | Ajustar a tabela de destino de cada *Table output*. |
| *Enter field mapping* não achava a tabela | Script do modelo executado no banco `postgres`, e não no `dw_olist` | Reexecutar o script na aba conectada ao `dw_olist`. |

## 7. Validações realizadas

| Tabela | Resultado |
|---|---|
| `dw.dim_tempo` | 1.096 linhas (2016-01-01 a 2018-12-31) |
| `dw.dim_vendedor` | 3.095 linhas |
| `dw.dim_produto` | 32.951 linhas |
| `dw.dim_cliente` | cerca de 96 mil linhas (um registro por `customer_unique_id`) |
| `dw.fato_vendas` | 112.650 linhas |

## 8. Arquivos do projeto

| Arquivo | Conteúdo |
|---|---|
| `dw/01_modelo_dw_olist.sql` | DDL do modelo estrela e carga da `dim_tempo` |
| `dw/02_staging_olist.sql` | DDL das tabelas de staging |
| `dw/03_carga_fato_vendas.sql` | Carga da `fato_vendas` |
| `pentaho/trf_dim_vendedor.ktr` | ETL da dimensão vendedor |
| `pentaho/trf_dim_produto.ktr` | ETL da dimensão produto |
| `pentaho/trf_dim_cliente.ktr` | ETL da dimensão cliente |
| `pentaho/trf_staging.ktr` | Carga da staging |
