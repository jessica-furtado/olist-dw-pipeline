# Olist E-commerce: Data Warehouse, EDA e Dashboard

Pipeline de dados ponta a ponta: **Pentaho (ETL / Data Warehouse) → Python (Análise Exploratória) → Power BI (Dashboard e Storytelling)**.

**Autora:** Jéssica Furtado de Sousa
**Curso:** MBA em Engenharia e Ciência de Dados

---

## 1. Visão geral

- **Problema de negócio:** atrasos na entrega afetam a satisfação do cliente e a receita?
- **Base de dados:** *Brazilian E-Commerce Public Dataset by Olist* (Kaggle), com pedidos, itens, clientes, produtos, vendedores e avaliações.
- **Fluxo do pipeline:**

```
CSVs (Olist) → Pentaho (ETL) → PostgreSQL (DW em modelo estrela) → Python (EDA) → Power BI (dashboard)
```

## 2. Estrutura do repositório

```
/
├── docs/        # documentação da arquitetura do Pentaho
├── dw/          # scripts SQL: modelo estrela, staging e carga da fato
├── pentaho/     # transformações do Pentaho (.ktr)
├── python/      # notebook da análise exploratória
├── powerbi/     # dashboard (.pbix)
└── README.md
```

Os CSVs originais não estão no repositório (tamanho). Baixar em: Kaggle, "Brazilian E-Commerce Public Dataset by Olist".

## 3. Arquitetura de Data Warehouse (Pentaho + PostgreSQL)

Documentação detalhada: [`docs/arquitetura_pentaho.md`](docs/arquitetura_pentaho.md).

### 3.1 Extração, transformação e carga
- **Dimensões carregadas pelo Pentaho** (`trf_dim_vendedor`, `trf_dim_produto`, `trf_dim_cliente`):
  - `dim_vendedor`: leitura direta do CSV de vendedores.
  - `dim_produto`: *Stream lookup* que junta a tradução das categorias (português → inglês) e *Select values* que renomeia as colunas.
  - `dim_cliente`: *Unique rows (HashSet)* por `customer_unique_id`, pois o `customer_id` muda a cada pedido e a mesma pessoa aparece várias vezes.
- **Staging** (`trf_staging`): o Pentaho carrega os CSVs de clientes, pedidos, itens e avaliações, crus, no schema `stg`.
- **Fato:** o script `dw/03_carga_fato_vendas.sql` monta a `fato_vendas` a partir da staging e das dimensões, convertendo tipos e calculando as métricas. Essa etapa é um **ELT**: o Pentaho carrega e o banco transforma.
- **`dim_tempo`:** gerada por SQL (`generate_series`), de 2016 a 2018, sem necessidade de ETL.
- **Ordem de carga:** dimensões → staging → fato.

### 3.2 Modelo dimensional (esquema estrela)
- **Tabela fato:** `fato_vendas`
- **Granularidade:** 1 linha = 1 item de pedido (`order_id` + `order_item_id`). Resultado: 112.650 linhas.
- **Métricas:** preço, frete, valor total, dias de entrega, dias de atraso, indicador de atraso e nota de avaliação.
- **Dimensões:** `dim_cliente`, `dim_produto`, `dim_vendedor` e `dim_tempo`.

### 3.3 Justificativa das escolhas
- **Granularidade em item de pedido:** é o nível mais detalhado disponível e permite analisar por produto, vendedor e cliente sem perder informação.
- **`dim_tempo` usada três vezes (role-playing):** compra, entrega prevista e entrega real, o que permite medir o atraso.
- **Cliente por `customer_unique_id`:** identifica a pessoa, e não o pedido.
- **Pagamentos fora do modelo:** são por pedido, e colocá-los no nível de item duplicaria valores.
- **Staging em texto:** os tipos são convertidos no SQL da fato, evitando erros de formato de data e de decimal entre o Pentaho e o banco.

## 4. Análise Exploratória de Dados (Python)

- **Notebook:** `python/eda_olist.ipynb`, que lê o modelo estrela diretamente do PostgreSQL.
- **Tratamento de dados:** verificação de duplicatas na granularidade, de itens sem data de entrega, de notas ausentes e de valores inconsistentes.
  - Pedidos cancelados e indisponíveis ficam fora da receita.
  - Itens sem data de entrega ficam fora das métricas de prazo.
  - Notas ausentes não foram preenchidas, para não distorcer a satisfação.
- **Distribuições:** preço, frete, prazo de entrega, notas e status dos pedidos.
- **Outliers:** identificados pelo método IQR e **mantidos**, porque preços altos e entregas longas são valores reais do negócio. Os outliers de preço foram sinalizados em uma coluna, e não removidos.
- **Métricas construídas:** receita, pedidos, ticket médio, % de atraso, tempo médio de entrega e nota média.

## 5. Dashboard e Storytelling (Power BI)

- **Arquivo:** `powerbi/dashboard_olist.pbix`
- **Fonte de dados:** PostgreSQL (`dw_olist`, schema `dw`), em modo Importar.
- **Indicadores:** Receita, Pedidos, Ticket Médio, % de Atraso, Tempo Médio de Entrega e Nota Média.
- **Medidas DAX:** `Receita`, `Pedidos`, `Ticket Medio`, `Pedidos Entregues`, `Pedidos Atrasados`, `% Atraso`, `Tempo Medio Entrega` e `Nota Media` (calculada por pedido, e não por item).
- **Achado central:** pedidos entregues no prazo têm nota média de 4,29. Com 1 a 3 dias de atraso, a nota cai para 3,29, e entre 8 e 14 dias chega a cerca de 1,7. Só cerca de 6,7% dos pedidos entregues chegam atrasados, mas o impacto na satisfação é forte, o que indica que reduzir atrasos deve ser prioridade logística.
- **Ressalva:** a análise mostra associação entre atraso e nota baixa, e não prova causa única.

## 6. Como reproduzir

1. Criar o banco `dw_olist` no PostgreSQL e executar `dw/01_modelo_dw_olist.sql`.
2. Executar `dw/02_staging_olist.sql`.
3. No Pentaho (PDI 9.4), ajustar a conexão `dw_olist` e executar as transformações de `pentaho/`: dimensões e depois `trf_staging`.
4. Executar `dw/03_carga_fato_vendas.sql`.
5. Rodar `python/eda_olist.ipynb`, informando a senha do banco na primeira célula (requisitos: `pandas numpy sqlalchemy psycopg2-binary matplotlib seaborn jupyter`).
6. Abrir `powerbi/dashboard_olist.pbix` e atualizar a fonte de dados.
