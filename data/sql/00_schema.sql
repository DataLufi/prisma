-- ============================================================
--  Projeto Prisma | ÍconeLab — 00_schema.sql
--  Lufi Data Consulting · Mai/2026
-- ============================================================
--  Execução: DBeaver conectado ao banco prisma (PostgreSQL)
--  Ordem obrigatória: dimensões primeiro, fatos depois (FK)
--  Após executar: rodar a query de verificação no final
-- ============================================================


-- ============================================================
--  LIMPEZA — drop na ordem inversa de dependência
-- ============================================================

DROP TABLE IF EXISTS f_devolucoes  CASCADE;
DROP TABLE IF EXISTS f_estoque     CASCADE;
DROP TABLE IF EXISTS f_marketing   CASCADE;
DROP TABLE IF EXISTS f_vendas      CASCADE;
DROP TABLE IF EXISTS d_produto     CASCADE;
DROP TABLE IF EXISTS d_cliente     CASCADE;
DROP TABLE IF EXISTS d_loja        CASCADE;
DROP TABLE IF EXISTS d_canal       CASCADE;
DROP TABLE IF EXISTS d_tempo       CASCADE;


-- ============================================================
--  DIMENSÕES
-- ============================================================

-- ------------------------------------------------------------
--  d_tempo — calendário analítico 2023-2025
-- ------------------------------------------------------------
CREATE TABLE d_tempo (
    data            DATE        PRIMARY KEY,
    ano             SMALLINT    NOT NULL,
    trimestre       SMALLINT    NOT NULL CHECK (trimestre BETWEEN 1 AND 4),
    mes             SMALLINT    NOT NULL CHECK (mes BETWEEN 1 AND 12),
    nome_mes        VARCHAR(20) NOT NULL,
    semana          SMALLINT    NOT NULL,
    dia_semana      SMALLINT    NOT NULL CHECK (dia_semana BETWEEN 1 AND 7),
    fim_de_semana   SMALLINT    NOT NULL CHECK (fim_de_semana IN (0,1)),
    ano_mes         VARCHAR(7)  NOT NULL   -- formato: '2023-01'
);

-- ------------------------------------------------------------
--  d_canal — 4 canais de venda com parâmetros de margem
-- ------------------------------------------------------------
CREATE TABLE d_canal (
    id_canal            SMALLINT    PRIMARY KEY,
    canal               VARCHAR(30) NOT NULL,
    margem_base_pct     NUMERIC(5,4) NOT NULL,
    desconto_medio_pct  NUMERIC(5,4) NOT NULL
);

-- ------------------------------------------------------------
--  d_loja — 12 unidades físicas e CDs com região
-- ------------------------------------------------------------
CREATE TABLE d_loja (
    id_loja         SMALLINT    PRIMARY KEY,
    tipo_unidade    VARCHAR(10) NOT NULL CHECK (tipo_unidade IN ('CD','Loja')),
    cidade          VARCHAR(50) NOT NULL,
    estado          CHAR(2)     NOT NULL,
    regiao          VARCHAR(20) NOT NULL
);

-- ------------------------------------------------------------
--  d_cliente — 40.000 clientes com perfil e tipo
-- ------------------------------------------------------------
CREATE TABLE d_cliente (
    id_cliente          INTEGER     PRIMARY KEY,
    tipo_cliente        VARCHAR(20) NOT NULL,   -- B2C Individual / B2C Premium / B2B Corporativo
    sexo                CHAR(1)     NOT NULL,
    faixa_etaria        VARCHAR(10) NOT NULL,
    cidade              VARCHAR(50) NOT NULL,
    estado              CHAR(2)     NOT NULL,
    regiao              VARCHAR(20) NOT NULL,
    data_cadastro       DATE        NOT NULL,
    segmento_cliente    VARCHAR(20) NOT NULL,
    canal_origem        VARCHAR(20) NOT NULL
);

-- ------------------------------------------------------------
--  d_produto — 700 produtos com custo e taxas por categoria
-- ------------------------------------------------------------
CREATE TABLE d_produto (
    id_produto                  INTEGER         PRIMARY KEY,
    categoria                   VARCHAR(30)     NOT NULL,
    subcategoria                VARCHAR(40)     NOT NULL,
    marca                       VARCHAR(30)     NOT NULL,
    nome_produto                VARCHAR(100)    NOT NULL,
    preco_lista                 NUMERIC(10,2)   NOT NULL CHECK (preco_lista > 0),
    faixa_preco                 VARCHAR(15)     NOT NULL CHECK (faixa_preco IN ('Essencial','Signature','Icon')),
    fornecedor                  VARCHAR(30)     NOT NULL,
    custo_unitario              NUMERIC(10,2)   NOT NULL CHECK (custo_unitario > 0),
    taxa_devolucao_esperada     NUMERIC(6,4)    NOT NULL,
    giro_esperado               NUMERIC(6,2)    NOT NULL
);


-- ============================================================
--  FATOS
-- ============================================================

-- ------------------------------------------------------------
--  f_vendas — fato principal: item de pedido (~228.800 linhas)
--  Campos calculados pré-gerados: receita, margem
-- ------------------------------------------------------------
CREATE TABLE f_vendas (
    id_item             INTEGER         PRIMARY KEY,
    id_pedido           INTEGER         NOT NULL,
    data_venda          DATE            NOT NULL REFERENCES d_tempo(data),
    id_cliente          INTEGER         NOT NULL REFERENCES d_cliente(id_cliente),
    id_produto          INTEGER         NOT NULL REFERENCES d_produto(id_produto),
    id_canal            SMALLINT        NOT NULL REFERENCES d_canal(id_canal),
    id_loja             SMALLINT        NOT NULL REFERENCES d_loja(id_loja),
    categoria           VARCHAR(30)     NOT NULL,
    tipo_cliente        VARCHAR(20)     NOT NULL,
    regiao_cliente      VARCHAR(20)     NOT NULL,
    qtd                 SMALLINT        NOT NULL CHECK (qtd > 0),
    preco_unitario      NUMERIC(10,2)   NOT NULL,
    desconto_valor      NUMERIC(10,2)   NOT NULL DEFAULT 0,
    frete_valor         NUMERIC(10,2)   NOT NULL DEFAULT 0,
    custo_produto       NUMERIC(10,2)   NOT NULL,
    imposto_valor       NUMERIC(10,2)   NOT NULL DEFAULT 0,
    receita_bruta       NUMERIC(12,2)   NOT NULL,
    receita_liquida     NUMERIC(12,2)   NOT NULL,
    margem_bruta        NUMERIC(12,2)   NOT NULL,
    margem_pct          NUMERIC(8,4)    NOT NULL,
    devolvido_flag      SMALLINT        NOT NULL DEFAULT 0 CHECK (devolvido_flag IN (0,1)),
    prazo_entrega_dias  SMALLINT        NOT NULL DEFAULT 0,
    avaliacao_cliente   SMALLINT        NOT NULL CHECK (avaliacao_cliente BETWEEN 1 AND 5)
);

-- ------------------------------------------------------------
--  f_marketing — campanha × dia × canal (~15.000 linhas)
-- ------------------------------------------------------------
CREATE TABLE f_marketing (
    id_campanha         INTEGER         NOT NULL,
    campanha            VARCHAR(50)     NOT NULL,
    data                DATE            NOT NULL REFERENCES d_tempo(data),
    ano                 SMALLINT        NOT NULL,
    mes                 SMALLINT        NOT NULL,
    id_canal            SMALLINT        NOT NULL REFERENCES d_canal(id_canal),
    investimento        NUMERIC(12,2)   NOT NULL,
    leads               INTEGER         NOT NULL DEFAULT 0,
    novos_clientes      INTEGER         NOT NULL DEFAULT 0,
    cac                 NUMERIC(10,2)   NOT NULL,
    eficiencia_pct      NUMERIC(6,1)    NOT NULL,
    PRIMARY KEY (id_campanha, data)
);

-- ------------------------------------------------------------
--  f_estoque — snapshot semanal por produto (~109.000 linhas)
-- ------------------------------------------------------------
CREATE TABLE f_estoque (
    data                DATE            NOT NULL REFERENCES d_tempo(data),
    ano                 SMALLINT        NOT NULL,
    mes                 SMALLINT        NOT NULL,
    id_produto          INTEGER         NOT NULL REFERENCES d_produto(id_produto),
    categoria           VARCHAR(30)     NOT NULL,
    estoque_inicial     INTEGER         NOT NULL DEFAULT 0,
    entradas            INTEGER         NOT NULL DEFAULT 0,
    saidas              INTEGER         NOT NULL DEFAULT 0,
    estoque_final       INTEGER         NOT NULL DEFAULT 0,
    ruptura_flag        SMALLINT        NOT NULL DEFAULT 0 CHECK (ruptura_flag IN (0,1)),
    custo_carregamento  NUMERIC(12,2)   NOT NULL DEFAULT 0,
    cobertura_dias      NUMERIC(8,1)    NOT NULL DEFAULT 0,
    PRIMARY KEY (data, id_produto)
);

-- ------------------------------------------------------------
--  f_devolucoes — 1 linha por item devolvido (~19.000 linhas)
-- ------------------------------------------------------------
CREATE TABLE f_devolucoes (
    id_item                     INTEGER         PRIMARY KEY REFERENCES f_vendas(id_item),
    id_pedido                   INTEGER         NOT NULL,
    data_venda                  DATE            NOT NULL,
    id_produto                  INTEGER         NOT NULL REFERENCES d_produto(id_produto),
    id_canal                    SMALLINT        NOT NULL REFERENCES d_canal(id_canal),
    categoria                   VARCHAR(30)     NOT NULL,
    regiao_cliente              VARCHAR(20)     NOT NULL,
    motivo_devolucao            VARCHAR(60)     NOT NULL,
    dias_ate_devolucao          SMALLINT        NOT NULL DEFAULT 0,
    receita_perdida             NUMERIC(12,2)   NOT NULL,
    custo_logistico_retorno     NUMERIC(10,2)   NOT NULL,
    reembolso_valor             NUMERIC(12,2)   NOT NULL,
    destino_produto             VARCHAR(30)     NOT NULL,
    valor_recuperado            NUMERIC(12,2)   NOT NULL DEFAULT 0,
    perda_liquida               NUMERIC(12,2)   NOT NULL
);


-- ============================================================
--  ÍNDICES ANALÍTICOS
--  Criados após as tabelas para não impactar a ingestão
-- ============================================================

-- f_vendas — os mais consultados nas views e queries
CREATE INDEX idx_fv_data_venda    ON f_vendas (data_venda);
CREATE INDEX idx_fv_canal         ON f_vendas (id_canal);
CREATE INDEX idx_fv_cliente       ON f_vendas (id_cliente);
CREATE INDEX idx_fv_produto       ON f_vendas (id_produto);
CREATE INDEX idx_fv_categoria     ON f_vendas (categoria);
CREATE INDEX idx_fv_regiao        ON f_vendas (regiao_cliente);
CREATE INDEX idx_fv_devolvido     ON f_vendas (devolvido_flag) WHERE devolvido_flag = 1;

-- f_estoque — consultas por produto e período
CREATE INDEX idx_fe_produto       ON f_estoque (id_produto);
CREATE INDEX idx_fe_categoria     ON f_estoque (categoria);

-- f_marketing — consultas por campanha e período
CREATE INDEX idx_fm_campanha      ON f_marketing (id_campanha);
CREATE INDEX idx_fm_canal         ON f_marketing (id_canal);

-- f_devolucoes — consultas por canal e categoria
CREATE INDEX idx_fd_canal         ON f_devolucoes (id_canal);
CREATE INDEX idx_fd_categoria     ON f_devolucoes (categoria);


-- ============================================================
--  \COPY — ingestão dos CSVs
--  Ajuste o caminho antes de executar
--  Atenção: ordem de dependência de FK deve ser respeitada
-- ============================================================

/*
-- 1. DIMENSÕES (sem FK entre si)
\COPY d_tempo     FROM 'C:/caminho/para/prisma/data/dataset/d_tempo.csv'     CSV HEADER ENCODING 'UTF8';
\COPY d_canal     FROM 'C:/caminho/para/prisma/data/dataset/d_canal.csv'     CSV HEADER ENCODING 'UTF8';
\COPY d_loja      FROM 'C:/caminho/para/prisma/data/dataset/d_loja.csv'      CSV HEADER ENCODING 'UTF8';
\COPY d_cliente   FROM 'C:/caminho/para/prisma/data/dataset/d_cliente.csv'   CSV HEADER ENCODING 'UTF8';
\COPY d_produto   FROM 'C:/caminho/para/prisma/data/dataset/d_produto.csv'   CSV HEADER ENCODING 'UTF8';

-- 2. FATO PRINCIPAL (referencia todas as dimensões)
\COPY f_vendas    FROM 'C:/caminho/para/prisma/data/dataset/f_vendas.csv'    CSV HEADER ENCODING 'UTF8';

-- 3. COMPLEMENTARES (referenciam f_vendas e dimensões)
\COPY f_marketing FROM 'C:/caminho/para/prisma/data/dataset/f_marketing.csv' CSV HEADER ENCODING 'UTF8';
\COPY f_estoque   FROM 'C:/caminho/para/prisma/data/dataset/f_estoque.csv'   CSV HEADER ENCODING 'UTF8';
\COPY f_devolucoes FROM 'C:/caminho/para/prisma/data/dataset/f_devolucoes.csv' CSV HEADER ENCODING 'UTF8';
*/


-- ============================================================
--  VERIFICAÇÃO DE INTEGRIDADE PÓS-INGESTÃO
--  Execute após carregar todos os CSVs
-- ============================================================

SELECT
    'd_tempo'      AS tabela, COUNT(*) AS linhas, 1096   AS esperado FROM d_tempo
UNION ALL SELECT
    'd_canal',                COUNT(*),            4              FROM d_canal
UNION ALL SELECT
    'd_loja',                 COUNT(*),            12             FROM d_loja
UNION ALL SELECT
    'd_cliente',              COUNT(*),            40000          FROM d_cliente
UNION ALL SELECT
    'd_produto',              COUNT(*),            700            FROM d_produto
UNION ALL SELECT
    'f_vendas',               COUNT(*),            228808         FROM f_vendas
UNION ALL SELECT
    'f_marketing',            COUNT(*),            3383           FROM f_marketing
UNION ALL SELECT
    'f_estoque',              COUNT(*),            109900         FROM f_estoque
UNION ALL SELECT
    'f_devolucoes',           COUNT(*),            19060          FROM f_devolucoes
ORDER BY tabela;
