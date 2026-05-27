-- ============================================================================
-- SCRIPT: Migração saldo_inicial → saldo
-- SISTEMA: Piggy Money
-- SGBD:    MySQL 8.0+
-- OBJETIVO: Substituir o campo estático saldo_inicial por um campo
--           dinâmico saldo nas tabelas conta e cartao_beneficio.
--           A atualização do saldo passa a ser responsabilidade da
--           aplicação (camada de serviços).
-- ATENÇÃO: Este script NÃO utiliza triggers.
-- ============================================================================

USE piggy_money;

-- ============================================================================
-- ETAPA 1: Adicionar coluna saldo (NULL inicialmente)
-- A coluna é adicionada como NULL para permitir copiar dados existentes
-- antes de aplicar as regras de negócio e torná-la NOT NULL.
-- ============================================================================
ALTER TABLE conta
    ADD COLUMN saldo DECIMAL(15,2) NULL AFTER tipo;

ALTER TABLE cartao_beneficio
    ADD COLUMN saldo DECIMAL(15,2) NULL AFTER tipo;

-- ============================================================================
-- ETAPA 2: Copiar valores existentes de saldo_inicial para saldo
-- Serve como base inicial para todos os registros.
-- ============================================================================
UPDATE conta SET saldo = saldo_inicial;
UPDATE cartao_beneficio SET saldo = saldo_inicial;

-- ============================================================================
-- ETAPA 3: Recalcular saldo para registros com transações efetivadas
-- Regra: entradas somam, saídas subtraem.
-- O cálculo parte do saldo_inicial original e aplica as movimentações
-- efetivadas (efetivada = TRUE).
-- ============================================================================
UPDATE conta c
INNER JOIN (
    SELECT
        conta_id,
        SUM(CASE WHEN tipo_movimento = 'entrada' THEN valor ELSE -valor END) AS movimento
    FROM transacao
    WHERE efetivada = TRUE AND conta_id IS NOT NULL
    GROUP BY conta_id
) t ON c.id = t.conta_id
SET c.saldo = COALESCE(c.saldo, 0) + t.movimento;

UPDATE cartao_beneficio cb
INNER JOIN (
    SELECT
        cartao_beneficio_id,
        SUM(CASE WHEN tipo_movimento = 'entrada' THEN valor ELSE -valor END) AS movimento
    FROM transacao
    WHERE efetivada = TRUE AND cartao_beneficio_id IS NOT NULL
    GROUP BY cartao_beneficio_id
) t ON cb.id = t.cartao_beneficio_id
SET cb.saldo = COALESCE(cb.saldo, 0) + t.movimento;

-- ============================================================================
-- ETAPA 4: Registros sem movimentação mantêm o antigo saldo_inicial
-- (Já realizado na Etapa 2 — mantido como documentação)
-- SELECT * FROM conta WHERE id NOT IN (SELECT DISTINCT conta_id FROM transacao WHERE conta_id IS NOT NULL);
-- SELECT * FROM cartao_beneficio WHERE id NOT IN (SELECT DISTINCT cartao_beneficio_id FROM transacao WHERE cartao_beneficio_id IS NOT NULL);
-- ============================================================================

-- ============================================================================
-- ETAPA 5: Definir 0.00 para registros sem movimentação e sem saldo anterior
-- Atinge registros onde saldo_inicial era NULL e não há transações.
-- ============================================================================
UPDATE conta SET saldo = 0.00 WHERE saldo IS NULL;
UPDATE cartao_beneficio SET saldo = 0.00 WHERE saldo IS NULL;

-- ============================================================================
-- ETAPA 6: Alterar coluna saldo para NOT NULL DEFAULT 0.00
-- Após a migração dos dados, a coluna pode ser tornada obrigatória.
-- ============================================================================
ALTER TABLE conta
    MODIFY COLUMN saldo DECIMAL(15,2) NOT NULL DEFAULT 0.00;

ALTER TABLE cartao_beneficio
    MODIFY COLUMN saldo DECIMAL(15,2) NOT NULL DEFAULT 0.00;

-- ============================================================================
-- ETAPA 7: Remover coluna antiga saldo_inicial
-- Após a migração completa, o campo legado é eliminado.
-- ============================================================================
ALTER TABLE conta
    DROP COLUMN saldo_inicial;

ALTER TABLE cartao_beneficio
    DROP COLUMN saldo_inicial;

-- ============================================================================
-- FIM DA MIGRAÇÃO
-- ============================================================================
