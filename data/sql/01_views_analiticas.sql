-- ============================================================
--  Projeto Prisma | ÍconeLab — 01_views_analiticas.sql
--  Lufi Data Consulting · Mai/2026
-- ============================================================
--  9 views analíticas — uma por pergunta de negócio
--  Conexão Power BI: via views (não tabelas brutas)
--  Pré-requisito: 00_schema.sql executado + CSVs ingeridos
-- ============================================================


-- ============================================================
--  VW_RESUMO_EXECUTIVO
--  Pergunta: como evoluíram receita, margem e volume YoY?
--  Uso: Executive Summary — página 1 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_resumo_executivo AS
SELECT
    t.ano,
    t.trimestre,
    t.ano_mes,
    -- Volume
    COUNT(DISTINCT fv.id_pedido)            AS total_pedidos,
    SUM(fv.qtd)                             AS total_itens,
    COUNT(DISTINCT fv.id_cliente)           AS clientes_ativos,
    -- Receita
    SUM(fv.receita_bruta)                   AS receita_bruta,
    SUM(fv.receita_liquida)                 AS receita_liquida,
    SUM(fv.desconto_valor)                  AS desconto_total,
    SUM(fv.frete_valor)                     AS frete_total,
    SUM(fv.imposto_valor)                   AS imposto_total,
    -- Margem
    SUM(fv.margem_bruta)                    AS margem_bruta,
    ROUND(
        SUM(fv.margem_bruta) / NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS margem_pct,
    -- Ticket
    ROUND(
        SUM(fv.receita_bruta) / NULLIF(COUNT(DISTINCT fv.id_pedido), 0),
    2)                                      AS ticket_medio,
    -- Devoluções
    SUM(fv.devolvido_flag)                  AS itens_devolvidos,
    ROUND(
        SUM(fv.devolvido_flag)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100,
    2)                                      AS taxa_devolucao_pct
FROM f_vendas fv
JOIN d_tempo t ON fv.data_venda = t.data
GROUP BY t.ano, t.trimestre, t.ano_mes
ORDER BY t.ano_mes;


-- ============================================================
--  VW_CANAL_PERFORMANCE
--  Pergunta: qual canal está destruindo margem? (Leak 1)
--  Uso: Profit Leak — página 2 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_canal_performance AS
SELECT
    t.ano,
    c.canal,
    c.margem_base_pct                       AS margem_base_parametro,
    c.desconto_medio_pct                    AS desconto_parametro,
    -- Volume
    COUNT(DISTINCT fv.id_pedido)            AS total_pedidos,
    -- Receita e custos
    SUM(fv.receita_bruta)                   AS receita_bruta,
    SUM(fv.desconto_valor)                  AS desconto_total,
    SUM(fv.frete_valor)                     AS frete_total,
    -- Desconto efetivo realizado
    ROUND(
        SUM(fv.desconto_valor) /
        NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS desconto_efetivo_pct,
    -- Margem
    SUM(fv.margem_bruta)                    AS margem_bruta,
    ROUND(
        SUM(fv.margem_bruta) /
        NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS margem_pct,
    -- Desvio em relação ao parâmetro base do canal
    ROUND(
        (SUM(fv.margem_bruta) /
        NULLIF(SUM(fv.receita_bruta), 0) - c.margem_base_pct) * 100,
    2)                                      AS desvio_margem_pp,
    -- Share de pedidos
    ROUND(
        COUNT(DISTINCT fv.id_pedido)::NUMERIC /
        SUM(COUNT(DISTINCT fv.id_pedido)) OVER (PARTITION BY t.ano) * 100,
    1)                                      AS share_pedidos_pct
FROM f_vendas fv
JOIN d_tempo t  ON fv.data_venda = t.data
JOIN d_canal c  ON fv.id_canal   = c.id_canal
GROUP BY t.ano, c.canal, c.margem_base_pct, c.desconto_medio_pct
ORDER BY t.ano, margem_pct;


-- ============================================================
--  VW_REGIAO_FRETE
--  Pergunta: onde o frete inviabiliza a operação? (Leak 2)
--  Uso: Operação — página 4 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_regiao_frete AS
SELECT
    t.ano,
    fv.regiao_cliente                       AS regiao,
    c.canal,
    -- Volume
    COUNT(DISTINCT fv.id_pedido)            AS total_pedidos,
    -- Frete
    SUM(fv.frete_valor)                     AS frete_total,
    ROUND(AVG(fv.frete_valor), 2)           AS frete_medio,
    -- Receita e margem
    SUM(fv.receita_bruta)                   AS receita_bruta,
    SUM(fv.margem_bruta)                    AS margem_bruta,
    ROUND(
        SUM(fv.margem_bruta) /
        NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS margem_pct,
    -- Frete como % da receita bruta — o indicador do leak
    ROUND(
        SUM(fv.frete_valor) /
        NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS frete_sobre_receita_pct,
    -- Margem ajustada sem o efeito do frete
    ROUND(
        (SUM(fv.margem_bruta) + SUM(fv.frete_valor)) /
        NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS margem_sem_frete_pct
FROM f_vendas fv
JOIN d_tempo t ON fv.data_venda = t.data
JOIN d_canal c ON fv.id_canal   = c.id_canal
WHERE c.canal <> 'Loja Física'             -- frete não se aplica à loja física
GROUP BY t.ano, fv.regiao_cliente, c.canal
ORDER BY t.ano, frete_medio DESC;


-- ============================================================
--  VW_DEVOLUCAO_CATEGORIA
--  Pergunta: qual o custo real das devoluções? (Leak 3)
--  Uso: Operação — página 4 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_devolucao_categoria AS
SELECT
    t.ano,
    d.categoria,
    c.canal,
    -- Volume de devoluções
    COUNT(*)                                AS total_devolucoes,
    -- Taxa de devolução (base: f_vendas)
    ROUND(
        COUNT(*)::NUMERIC /
        NULLIF(SUM(COUNT(*)) OVER (PARTITION BY t.ano, d.categoria), 0) * 100,
    2)                                      AS share_devolucoes_pct,
    -- Financeiro da devolução
    SUM(d.receita_perdida)                  AS receita_perdida_total,
    SUM(d.custo_logistico_retorno)          AS custo_logistico_total,
    SUM(d.reembolso_valor)                  AS reembolso_total,
    SUM(d.valor_recuperado)                 AS valor_recuperado_total,
    SUM(d.perda_liquida)                    AS perda_liquida_total,
    ROUND(AVG(d.perda_liquida), 2)          AS perda_liquida_media,
    -- Tempo médio até devolução
    ROUND(AVG(d.dias_ate_devolucao), 1)     AS dias_medio_devolucao,
    -- Motivo mais frequente (simplificado)
    MODE() WITHIN GROUP (ORDER BY d.motivo_devolucao) AS motivo_principal
FROM f_devolucoes d
JOIN d_tempo t ON d.data_venda = t.data
JOIN d_canal c ON d.id_canal   = c.id_canal
GROUP BY t.ano, d.categoria, c.canal
ORDER BY t.ano, perda_liquida_total DESC;


-- ============================================================
--  VW_COHORT_RETENCAO
--  Pergunta: clientes novos estão recomprado? (Leak 4)
--  Uso: Clientes — página 3 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_cohort_retencao AS
WITH primeira_compra AS (
    -- Data da primeira compra de cada cliente
    SELECT
        id_cliente,
        MIN(data_venda)                     AS data_primeira_compra,
        DATE_TRUNC('month', MIN(data_venda)) AS mes_cohort
    FROM f_vendas
    GROUP BY id_cliente
),
compras_mensais AS (
    -- Todas as compras com mês de cohort
    SELECT
        fv.id_cliente,
        DATE_TRUNC('month', fv.data_venda)  AS mes_compra,
        pc.mes_cohort,
        -- Meses de distância do cohort (0 = mês de aquisição)
        EXTRACT(YEAR FROM AGE(
            DATE_TRUNC('month', fv.data_venda),
            pc.mes_cohort
        )) * 12 +
        EXTRACT(MONTH FROM AGE(
            DATE_TRUNC('month', fv.data_venda),
            pc.mes_cohort
        ))                                  AS meses_desde_cohort
    FROM f_vendas fv
    JOIN primeira_compra pc ON fv.id_cliente = pc.id_cliente
)
SELECT
    TO_CHAR(mes_cohort, 'YYYY-MM')          AS cohort,
    meses_desde_cohort,
    COUNT(DISTINCT id_cliente)              AS clientes_ativos,
    -- Tamanho do cohort original (mês 0)
    FIRST_VALUE(COUNT(DISTINCT id_cliente))
        OVER (PARTITION BY mes_cohort ORDER BY meses_desde_cohort)
                                            AS tamanho_cohort,
    -- Taxa de retenção
    ROUND(
        COUNT(DISTINCT id_cliente)::NUMERIC /
        NULLIF(
            FIRST_VALUE(COUNT(DISTINCT id_cliente))
            OVER (PARTITION BY mes_cohort ORDER BY meses_desde_cohort),
            0
        ) * 100,
    1)                                      AS taxa_retencao_pct
FROM compras_mensais
WHERE meses_desde_cohort <= 12             -- janela de 12 meses
GROUP BY mes_cohort, meses_desde_cohort
ORDER BY mes_cohort, meses_desde_cohort;


-- ============================================================
--  VW_LTV_VS_CAC
--  Pergunta: o LTV justifica o CAC crescente? (Leak 4)
--  Uso: Clientes — página 3 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_ltv_vs_cac AS
WITH receita_cliente AS (
    SELECT
        fv.id_cliente,
        t.ano,
        SUM(fv.receita_bruta)               AS receita_total,
        SUM(fv.margem_bruta)                AS margem_total,
        COUNT(DISTINCT fv.id_pedido)        AS total_pedidos,
        MIN(fv.data_venda)                  AS primeira_compra,
        MAX(fv.data_venda)                  AS ultima_compra
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    GROUP BY fv.id_cliente, t.ano
),
cac_ano AS (
    SELECT
        ano,
        ROUND(AVG(cac), 2)                  AS cac_medio,
        SUM(investimento)                   AS investimento_total,
        SUM(novos_clientes)                 AS novos_clientes_total
    FROM f_marketing
    GROUP BY ano
)
SELECT
    rc.ano,
    -- LTV proxy — margem média por cliente ativo no ano
    ROUND(AVG(rc.margem_total), 2)          AS ltv_medio,
    ROUND(AVG(rc.receita_total), 2)         AS receita_media_cliente,
    ROUND(AVG(rc.total_pedidos), 2)         AS pedidos_medio_cliente,
    -- CAC
    ca.cac_medio,
    ca.investimento_total,
    ca.novos_clientes_total,
    -- Ratio LTV/CAC — quanto de margem cada R$1 de CAC gera
    ROUND(AVG(rc.margem_total) / NULLIF(ca.cac_medio, 0), 2) AS ltv_cac_ratio,
    -- Payback implícito em meses
    ROUND(ca.cac_medio / NULLIF(AVG(rc.margem_total) / 12, 0), 1) AS payback_meses
FROM receita_cliente rc
JOIN cac_ano ca ON rc.ano = ca.ano
GROUP BY rc.ano, ca.cac_medio, ca.investimento_total, ca.novos_clientes_total
ORDER BY rc.ano;


-- ============================================================
--  VW_ESTOQUE_SAUDE
--  Pergunta: onde o capital está imobilizado? (Leak 5)
--  Uso: Operação — página 4 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_estoque_saude AS
SELECT
    fe.ano,
    fe.mes,
    fe.categoria,
    p.subcategoria,
    -- Estoque
    ROUND(AVG(fe.estoque_final), 0)         AS estoque_medio,
    SUM(fe.saidas)                          AS saidas_totais,
    -- Cobertura média em dias — >90 dias sinaliza Leak 5
    ROUND(AVG(
        CASE WHEN fe.cobertura_dias < 999 THEN fe.cobertura_dias END
    ), 0)                                   AS cobertura_media_dias,
    -- Capital imobilizado
    SUM(fe.custo_carregamento)              AS custo_carregamento_total,
    -- Rupturas — sinaliza Leak 6
    SUM(fe.ruptura_flag)                    AS total_rupturas,
    ROUND(
        SUM(fe.ruptura_flag)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100,
    2)                                      AS taxa_ruptura_pct,
    -- Giro implícito (saídas / estoque médio)
    ROUND(
        SUM(fe.saidas)::NUMERIC /
        NULLIF(AVG(fe.estoque_final), 0),
    2)                                      AS giro_implicito
FROM f_estoque fe
JOIN d_produto p ON fe.id_produto = p.id_produto
GROUP BY fe.ano, fe.mes, fe.categoria, p.subcategoria
ORDER BY fe.ano, fe.mes, custo_carregamento_total DESC;


-- ============================================================
--  VW_SLA_ENTREGA
--  Pergunta: onde e quando o prazo colapsa? (Leak 6)
--  Uso: Operação — página 4 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_sla_entrega AS
SELECT
    t.ano,
    t.mes,
    t.nome_mes,
    fv.regiao_cliente                       AS regiao,
    c.canal,
    -- SLA
    ROUND(AVG(fv.prazo_entrega_dias), 1)    AS prazo_medio_dias,
    MAX(fv.prazo_entrega_dias)              AS prazo_maximo_dias,
    -- Volume para contexto
    COUNT(DISTINCT fv.id_pedido)            AS total_pedidos,
    -- Flag de pico sazonal
    CASE WHEN t.mes IN (11, 12) THEN 1 ELSE 0 END AS pico_sazonal_flag,
    -- Acima de 10 dias = SLA crítico
    SUM(CASE WHEN fv.prazo_entrega_dias > 10 THEN 1 ELSE 0 END) AS pedidos_sla_critico,
    ROUND(
        SUM(CASE WHEN fv.prazo_entrega_dias > 10 THEN 1 ELSE 0 END)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100,
    1)                                      AS pct_sla_critico,
    -- Correlação com avaliação
    ROUND(AVG(fv.avaliacao_cliente), 2)     AS avaliacao_media
FROM f_vendas fv
JOIN d_tempo t ON fv.data_venda = t.data
JOIN d_canal c ON fv.id_canal   = c.id_canal
WHERE c.canal <> 'Loja Física'             -- SLA não se aplica
GROUP BY t.ano, t.mes, t.nome_mes, fv.regiao_cliente, c.canal,
         CASE WHEN t.mes IN (11, 12) THEN 1 ELSE 0 END
ORDER BY t.ano, t.mes, prazo_medio_dias DESC;


-- ============================================================
--  VW_MIX_CATEGORIA
--  Pergunta: o mix explica a queda de margem? (Leak 7)
--  Uso: Profit Leak — página 2 do dashboard
-- ============================================================

CREATE OR REPLACE VIEW vw_mix_categoria AS
SELECT
    t.ano,
    fv.categoria,
    -- Volume e share
    COUNT(DISTINCT fv.id_pedido)            AS total_pedidos,
    ROUND(
        COUNT(DISTINCT fv.id_pedido)::NUMERIC /
        SUM(COUNT(DISTINCT fv.id_pedido)) OVER (PARTITION BY t.ano) * 100,
    1)                                      AS share_pedidos_pct,
    -- Receita e share
    SUM(fv.receita_bruta)                   AS receita_bruta,
    ROUND(
        SUM(fv.receita_bruta) /
        SUM(SUM(fv.receita_bruta)) OVER (PARTITION BY t.ano) * 100,
    1)                                      AS share_receita_pct,
    -- Margem
    SUM(fv.margem_bruta)                    AS margem_bruta,
    ROUND(
        SUM(fv.margem_bruta) /
        NULLIF(SUM(fv.receita_bruta), 0) * 100,
    2)                                      AS margem_pct,
    -- Devolução por categoria
    SUM(fv.devolvido_flag)                  AS itens_devolvidos,
    ROUND(
        SUM(fv.devolvido_flag)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100,
    2)                                      AS taxa_devolucao_pct,
    -- Ticket médio
    ROUND(
        SUM(fv.receita_bruta) /
        NULLIF(COUNT(DISTINCT fv.id_pedido), 0),
    2)                                      AS ticket_medio
FROM f_vendas fv
JOIN d_tempo t ON fv.data_venda = t.data
GROUP BY t.ano, fv.categoria
ORDER BY t.ano, share_receita_pct DESC;


-- ============================================================
--  VERIFICAÇÃO — confirma que as 9 views foram criadas
-- ============================================================

SELECT
    viewname                                AS view,
    'OK'                                    AS status
FROM pg_views
WHERE schemaname = 'public'
  AND viewname IN (
    'vw_resumo_executivo',
    'vw_canal_performance',
    'vw_regiao_frete',
    'vw_devolucao_categoria',
    'vw_cohort_retencao',
    'vw_ltv_vs_cac',
    'vw_estoque_saude',
    'vw_sla_entrega',
    'vw_mix_categoria'
  )
ORDER BY viewname;
