-- ============================================================
--  Projeto Prisma | ÍconeLab — 02_queries_negocio.sql
--  Lufi Data Consulting · Mai/2026
-- ============================================================
--  8 diagnósticos de negócio — 7 profit leaks + 1 ROI
--  Técnicas: window functions, CTEs encadeadas, efeito mix
--  Pré-requisito: 01_views_analiticas.sql executado
-- ============================================================


-- ============================================================
--  DIAGNÓSTICO 1 — LEAK 1: Desconto Estrutural no Marketplace
--  Pergunta: o desconto do Marketplace está crescendo?
--  Quanto ele custou em margem perdida por ano?
-- ============================================================

WITH desconto_por_canal_ano AS (
    SELECT
        t.ano,
        c.canal,
        SUM(fv.receita_bruta)               AS receita_bruta,
        SUM(fv.desconto_valor)              AS desconto_total,
        SUM(fv.margem_bruta)                AS margem_bruta,
        ROUND(
            SUM(fv.desconto_valor) /
            NULLIF(SUM(fv.receita_bruta), 0) * 100,
        2)                                  AS desconto_efetivo_pct,
        COUNT(DISTINCT fv.id_pedido)        AS total_pedidos
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    JOIN d_canal c ON fv.id_canal   = c.id_canal
    GROUP BY t.ano, c.canal
),
baseline AS (
    -- Desconto de 2023 como referência (antes do crescimento)
    SELECT canal, desconto_efetivo_pct AS desconto_base_2023
    FROM desconto_por_canal_ano
    WHERE ano = 2023
)
SELECT
    d.ano,
    d.canal,
    d.total_pedidos,
    d.receita_bruta,
    d.desconto_total,
    d.desconto_efetivo_pct,
    b.desconto_base_2023,
    -- Crescimento do desconto vs base 2023
    ROUND(d.desconto_efetivo_pct - b.desconto_base_2023, 2)    AS crescimento_desconto_pp,
    d.margem_bruta,
    -- Custo do desconto extra vs cenário sem crescimento
    ROUND(
        (d.desconto_efetivo_pct - b.desconto_base_2023) / 100 *
        d.receita_bruta,
    2)                                      AS custo_desconto_extra
FROM desconto_por_canal_ano d
JOIN baseline b ON d.canal = b.canal
ORDER BY d.ano, d.canal;


-- ============================================================
--  DIAGNÓSTICO 2 — LEAK 2: Frete Inviável no Norte e Nordeste
--  Pergunta: o frete está consumindo a margem nas regiões críticas?
--  Qual o diferencial de custo Norte vs Sudeste?
-- ============================================================

WITH frete_regional AS (
    SELECT
        t.ano,
        fv.regiao_cliente                   AS regiao,
        COUNT(DISTINCT fv.id_pedido)        AS total_pedidos,
        SUM(fv.receita_bruta)               AS receita_bruta,
        SUM(fv.frete_valor)                 AS frete_total,
        ROUND(AVG(fv.frete_valor), 2)       AS frete_medio,
        SUM(fv.margem_bruta)                AS margem_bruta,
        ROUND(
            SUM(fv.frete_valor) /
            NULLIF(SUM(fv.receita_bruta), 0) * 100,
        2)                                  AS frete_sobre_receita_pct,
        ROUND(
            SUM(fv.margem_bruta) /
            NULLIF(SUM(fv.receita_bruta), 0) * 100,
        2)                                  AS margem_pct
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    JOIN d_canal c ON fv.id_canal   = c.id_canal
    WHERE c.canal <> 'Loja Física'
    GROUP BY t.ano, fv.regiao_cliente
),
sudeste AS (
    SELECT ano, frete_medio AS frete_sudeste
    FROM frete_regional
    WHERE regiao = 'Sudeste'
)
SELECT
    fr.ano,
    fr.regiao,
    fr.total_pedidos,
    fr.frete_medio,
    s.frete_sudeste,
    -- Múltiplo vs Sudeste — mostra a desproporção
    ROUND(fr.frete_medio / NULLIF(s.frete_sudeste, 0), 1)  AS multiplo_vs_sudeste,
    fr.frete_sobre_receita_pct,
    fr.margem_pct,
    fr.frete_total,
    fr.receita_bruta
FROM frete_regional fr
JOIN sudeste s ON fr.ano = s.ano
ORDER BY fr.ano, fr.frete_medio DESC;


-- ============================================================
--  DIAGNÓSTICO 3 — LEAK 3: Alta Devolução em Tech & Lifestyle
--  Pergunta: quanto a devolução de Tech custa em perda líquida?
--  O Marketplace amplifica o problema?
-- ============================================================

WITH devolucao_base AS (
    SELECT
        t.ano,
        fv.categoria,
        c.canal,
        COUNT(*)                            AS total_vendas,
        SUM(fv.devolvido_flag)              AS total_devolvidos,
        ROUND(
            SUM(fv.devolvido_flag)::NUMERIC /
            NULLIF(COUNT(*), 0) * 100,
        2)                                  AS taxa_devolucao_pct,
        SUM(fv.receita_bruta)               AS receita_bruta
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    JOIN d_canal c ON fv.id_canal   = c.id_canal
    GROUP BY t.ano, fv.categoria, c.canal
),
perda_por_categoria AS (
    SELECT
        EXTRACT(YEAR FROM d.data_venda)::INT AS ano,
        d.categoria,
        SUM(d.perda_liquida)                AS perda_liquida_total,
        ROUND(AVG(d.perda_liquida), 2)      AS perda_media,
        COUNT(*)                            AS n_devolucoes,
        SUM(d.custo_logistico_retorno)      AS custo_logistico_total
    FROM f_devolucoes d
    GROUP BY EXTRACT(YEAR FROM d.data_venda)::INT, d.categoria
)
SELECT
    db.ano,
    db.categoria,
    db.canal,
    db.total_vendas,
    db.total_devolvidos,
    db.taxa_devolucao_pct,
    db.receita_bruta,
    pc.perda_liquida_total,
    pc.custo_logistico_total,
    -- Perda como % da receita — impacto real na margem
    ROUND(
        pc.perda_liquida_total /
        NULLIF(db.receita_bruta, 0) * 100,
    2)                                      AS perda_sobre_receita_pct
FROM devolucao_base db
LEFT JOIN perda_por_categoria pc
       ON db.ano = pc.ano AND db.categoria = pc.categoria
ORDER BY db.ano, db.taxa_devolucao_pct DESC;


-- ============================================================
--  DIAGNÓSTICO 4 — LEAK 4: Clientes Novos que Não Recompram
--  Pergunta: a taxa de recompra em 6 meses está caindo YoY?
--  O CAC crescente se justifica?
-- ============================================================

WITH primeira_compra AS (
    SELECT
        id_cliente,
        MIN(data_venda)                     AS data_primeira_compra,
        EXTRACT(YEAR FROM MIN(data_venda))::INT AS ano_aquisicao
    FROM f_vendas
    GROUP BY id_cliente
),
recompra_6m AS (
    SELECT
        pc.id_cliente,
        pc.ano_aquisicao,
        pc.data_primeira_compra,
        -- Houve recompra nos 6 meses seguintes?
        MAX(CASE
            WHEN fv.data_venda > pc.data_primeira_compra
             AND fv.data_venda <= pc.data_primeira_compra + INTERVAL '6 months'
            THEN 1 ELSE 0
        END)                                AS recomprou_6m
    FROM primeira_compra pc
    LEFT JOIN f_vendas fv ON pc.id_cliente = fv.id_cliente
    GROUP BY pc.id_cliente, pc.ano_aquisicao, pc.data_primeira_compra
),
cac_ano AS (
    SELECT ano, ROUND(AVG(cac), 2) AS cac_medio
    FROM f_marketing
    GROUP BY ano
)
SELECT
    r.ano_aquisicao                         AS ano,
    COUNT(*)                                AS novos_clientes,
    SUM(r.recomprou_6m)                     AS recompraram_6m,
    ROUND(
        SUM(r.recomprou_6m)::NUMERIC /
        NULLIF(COUNT(*), 0) * 100,
    1)                                      AS taxa_recompra_6m_pct,
    ca.cac_medio,
    -- Custo para adquirir clientes que não voltaram
    ROUND(
        ca.cac_medio *
        (COUNT(*) - SUM(r.recomprou_6m)),
    0)                                      AS investimento_perdido_estimado
FROM recompra_6m r
JOIN cac_ano ca ON r.ano_aquisicao = ca.ano
GROUP BY r.ano_aquisicao, ca.cac_medio
ORDER BY r.ano_aquisicao;


-- ============================================================
--  DIAGNÓSTICO 5 — LEAK 5: Estoque Parado em Gourmet
--  Pergunta: quanto capital está imobilizado em Gourmet?
--  A cobertura de dias está acima do aceitável?
-- ============================================================

WITH estoque_categoria AS (
    SELECT
        fe.ano,
        fe.categoria,
        ROUND(AVG(fe.estoque_final), 0)     AS estoque_medio,
        SUM(fe.saidas)                      AS saidas_totais,
        SUM(fe.custo_carregamento)          AS custo_carregamento_total,
        -- Cobertura média excluindo outliers (999 = sem saída)
        ROUND(AVG(
            CASE WHEN fe.cobertura_dias < 999 THEN fe.cobertura_dias END
        ), 0)                               AS cobertura_media_dias,
        -- % de snapshots com cobertura > 90 dias
        ROUND(
            SUM(CASE WHEN fe.cobertura_dias BETWEEN 1 AND 999
                      AND fe.cobertura_dias > 90
                     THEN 1 ELSE 0 END)::NUMERIC /
            NULLIF(SUM(CASE WHEN fe.cobertura_dias < 999 THEN 1 ELSE 0 END), 0) * 100,
        1)                                  AS pct_snapshots_acima_90d
    FROM f_estoque fe
    GROUP BY fe.ano, fe.categoria
)
SELECT
    ec.ano,
    ec.categoria,
    ec.estoque_medio,
    ec.saidas_totais,
    ec.cobertura_media_dias,
    ec.pct_snapshots_acima_90d,
    ec.custo_carregamento_total,
    -- Ranking por custo de capital imobilizado
    RANK() OVER (
        PARTITION BY ec.ano
        ORDER BY ec.custo_carregamento_total DESC
    )                                       AS rank_capital_imobilizado
FROM estoque_categoria ec
ORDER BY ec.ano, ec.custo_carregamento_total DESC;


-- ============================================================
--  DIAGNÓSTICO 6 — LEAK 6: SLA Colapsando nos Picos Sazonais
--  Pergunta: o prazo de entrega piora em Nov/Dez e YoY?
--  Qual região e categoria sofrem mais?
-- ============================================================

WITH sla_mensal AS (
    SELECT
        t.ano,
        t.mes,
        t.nome_mes,
        fv.regiao_cliente                   AS regiao,
        fv.categoria,
        ROUND(AVG(fv.prazo_entrega_dias), 1) AS prazo_medio,
        COUNT(DISTINCT fv.id_pedido)        AS total_pedidos,
        CASE WHEN t.mes IN (11,12) THEN 'Pico' ELSE 'Normal' END AS periodo
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    JOIN d_canal c ON fv.id_canal   = c.id_canal
    WHERE c.canal <> 'Loja Física'
    GROUP BY t.ano, t.mes, t.nome_mes, fv.regiao_cliente, fv.categoria
),
sla_normal_2023 AS (
    -- Baseline: prazo médio em período normal do primeiro ano
    SELECT regiao, categoria,
           AVG(prazo_medio) AS prazo_base
    FROM sla_mensal
    WHERE ano = 2023 AND periodo = 'Normal'
    GROUP BY regiao, categoria
)
SELECT
    s.ano,
    s.periodo,
    s.regiao,
    s.categoria,
    ROUND(AVG(s.prazo_medio), 1)            AS prazo_medio_dias,
    SUM(s.total_pedidos)                    AS total_pedidos,
    -- Degradação vs baseline 2023 período normal
    ROUND(AVG(s.prazo_medio) - AVG(b.prazo_base), 1) AS degradacao_vs_baseline,
    -- Multiplicador de pico
    ROUND(
        AVG(s.prazo_medio) /
        NULLIF(AVG(b.prazo_base), 0),
    2)                                      AS multiplicador_pico
FROM sla_mensal s
LEFT JOIN sla_normal_2023 b
       ON s.regiao = b.regiao AND s.categoria = b.categoria
GROUP BY s.ano, s.periodo, s.regiao, s.categoria
ORDER BY s.ano, s.periodo DESC, degradacao_vs_baseline DESC;


-- ============================================================
--  DIAGNÓSTICO 7 — LEAK 7: Mix Migrando para Baixa Margem
--  Pergunta: o crescimento de Tech & Lifestyle explica
--  quanto da queda de margem? Efeito mix vs efeito taxa.
-- ============================================================

WITH mix_anual AS (
    SELECT
        t.ano,
        fv.categoria,
        SUM(fv.receita_bruta)               AS receita,
        SUM(fv.margem_bruta)                AS margem,
        ROUND(
            SUM(fv.margem_bruta) /
            NULLIF(SUM(fv.receita_bruta), 0),
        4)                                  AS margem_taxa,
        ROUND(
            SUM(fv.receita_bruta) /
            SUM(SUM(fv.receita_bruta)) OVER (PARTITION BY t.ano),
        4)                                  AS share_receita
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    GROUP BY t.ano, fv.categoria
),
base_2023 AS (
    SELECT categoria, margem_taxa AS taxa_2023, share_receita AS share_2023
    FROM mix_anual
    WHERE ano = 2023
)
SELECT
    m.ano,
    m.categoria,
    ROUND(m.share_receita * 100, 1)         AS share_atual_pct,
    ROUND(b.share_2023 * 100, 1)            AS share_2023_pct,
    ROUND((m.share_receita - b.share_2023) * 100, 1) AS variacao_share_pp,
    ROUND(m.margem_taxa * 100, 2)           AS margem_taxa_atual_pct,
    ROUND(b.taxa_2023 * 100, 2)             AS margem_taxa_2023_pct,
    -- Efeito Mix: quanto a mudança de share impactou a margem total
    -- (variação de share × taxa de margem do período base)
    ROUND(
        (m.share_receita - b.share_2023) * b.taxa_2023 *
        SUM(m.receita) OVER (PARTITION BY m.ano),
    0)                                      AS efeito_mix_R$,
    -- Efeito Taxa: quanto a mudança na taxa de margem impactou
    -- (variação de taxa × share atual)
    ROUND(
        (m.margem_taxa - b.taxa_2023) * m.share_receita *
        SUM(m.receita) OVER (PARTITION BY m.ano),
    0)                                      AS efeito_taxa_R$
FROM mix_anual m
JOIN base_2023 b ON m.categoria = b.categoria
ORDER BY m.ano, m.share_receita DESC;


-- ============================================================
--  DIAGNÓSTICO 8 — ROI DOS LEAKS (upgrade M3 — Issue #30)
--  Pergunta: se corrigirmos os 3 maiores leaks,
--  quanto de margem recuperamos?
-- ============================================================

WITH margem_atual AS (
    SELECT
        t.ano,
        SUM(fv.receita_bruta)               AS receita_bruta,
        SUM(fv.margem_bruta)                AS margem_bruta,
        ROUND(
            SUM(fv.margem_bruta) /
            NULLIF(SUM(fv.receita_bruta), 0) * 100,
        2)                                  AS margem_pct_atual
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    WHERE t.ano = 2025                      -- ano de referência para o diagnóstico
    GROUP BY t.ano
),
-- Leak 1: Marketplace volta ao desconto de 2023
-- Premissa: desconto cai de ~22% para ~15% no Marketplace
cenario_leak1 AS (
    SELECT
        SUM(
            CASE WHEN fv.id_canal = 2
                 THEN fv.desconto_valor * (1 - 0.32)  -- redução de 32% no desconto
                 ELSE 0
            END
        )                                   AS ganho_leak1
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    WHERE t.ano = 2025
),
-- Leak 2: Frete Norte/Nordeste reduzido 20% via renegociação logística
cenario_leak2 AS (
    SELECT
        SUM(
            CASE WHEN fv.regiao_cliente IN ('Norte','Nordeste')
                 THEN fv.frete_valor * 0.20
                 ELSE 0
            END
        )                                   AS ganho_leak2
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    WHERE t.ano = 2025
),
-- Leak 3: Taxa de devolução de Tech cai de ~19% para ~12% (nível de 2023)
-- Premissa: ganho = redução de devoluções × perda líquida média
cenario_leak3 AS (
    SELECT
        COUNT(*) * 0.37 *                   -- 37% dos itens devolvidos a menos
        AVG(d.perda_liquida)                AS ganho_leak3
    FROM f_devolucoes d
    JOIN d_tempo t ON d.data_venda = t.data
    WHERE t.ano = 2025
      AND d.categoria = 'Tech & Lifestyle'
)
SELECT
    ma.ano,
    ma.receita_bruta,
    ma.margem_bruta                         AS margem_atual,
    ma.margem_pct_atual,
    -- Ganhos por cenário
    ROUND(c1.ganho_leak1, 0)                AS ganho_leak1_desconto_R$,
    ROUND(c2.ganho_leak2, 0)                AS ganho_leak2_frete_R$,
    ROUND(c3.ganho_leak3, 0)                AS ganho_leak3_devolucao_R$,
    -- Ganho total combinado
    ROUND(c1.ganho_leak1 + c2.ganho_leak2 + c3.ganho_leak3, 0) AS ganho_total_R$,
    -- Margem projetada pós-correção
    ROUND(ma.margem_bruta + c1.ganho_leak1 + c2.ganho_leak2 + c3.ganho_leak3, 0)
                                            AS margem_projetada_R$,
    -- Margem % projetada
    ROUND(
        (ma.margem_bruta + c1.ganho_leak1 + c2.ganho_leak2 + c3.ganho_leak3) /
        NULLIF(ma.receita_bruta, 0) * 100,
    2)                                      AS margem_projetada_pct,
    -- Ganho em pontos percentuais de margem
    ROUND(
        (ma.margem_bruta + c1.ganho_leak1 + c2.ganho_leak2 + c3.ganho_leak3) /
        NULLIF(ma.receita_bruta, 0) * 100 - ma.margem_pct_atual,
    2)                                      AS ganho_margem_pp
FROM margem_atual ma
CROSS JOIN cenario_leak1 c1
CROSS JOIN cenario_leak2 c2
CROSS JOIN cenario_leak3 c3;


-- ============================================================
--  CONSOLIDADO — Decomposição de Margem (base do Waterfall)
--  Usado na página Profit Leak do Power BI
-- ============================================================

WITH componentes AS (
    SELECT
        t.ano,
        SUM(fv.receita_bruta)               AS receita_bruta,
        SUM(fv.desconto_valor)              AS desconto_total,
        SUM(fv.frete_valor)                 AS frete_total,
        SUM(fv.imposto_valor)               AS imposto_total,
        SUM(fv.custo_produto)               AS custo_total,
        SUM(fv.receita_liquida)             AS receita_liquida,
        SUM(fv.margem_bruta)                AS margem_bruta
    FROM f_vendas fv
    JOIN d_tempo t ON fv.data_venda = t.data
    GROUP BY t.ano
),
perda_devolucao AS (
    SELECT
        EXTRACT(YEAR FROM d.data_venda)::INT AS ano,
        SUM(d.perda_liquida)                AS perda_total_devolucoes
    FROM f_devolucoes d
    GROUP BY EXTRACT(YEAR FROM d.data_venda)::INT
)
SELECT
    c.ano,
    c.receita_bruta,
    -- Deduções da receita
    -c.desconto_total                       AS menos_desconto,
    -c.frete_total                          AS menos_frete,
    -c.imposto_total                        AS menos_imposto,
    c.receita_liquida,
    -- Custo e margem
    -c.custo_total                          AS menos_custo_produto,
    c.margem_bruta,
    -- Perda oculta com devoluções
    -COALESCE(pd.perda_total_devolucoes, 0) AS menos_perda_devolucoes,
    -- Margem ajustada (considerando perda real de devoluções)
    c.margem_bruta - COALESCE(pd.perda_total_devolucoes, 0)
                                            AS margem_ajustada,
    -- Percentuais
    ROUND(c.margem_bruta / NULLIF(c.receita_bruta, 0) * 100, 2)
                                            AS margem_pct,
    ROUND(
        (c.margem_bruta - COALESCE(pd.perda_total_devolucoes, 0)) /
        NULLIF(c.receita_bruta, 0) * 100, 2
    )                                       AS margem_ajustada_pct
FROM componentes c
LEFT JOIN perda_devolucao pd ON c.ano = pd.ano
ORDER BY c.ano;
