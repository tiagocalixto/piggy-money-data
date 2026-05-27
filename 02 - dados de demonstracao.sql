-- ============================================================================
-- SCRIPT: Dados de Demonstração - Piggy Money
-- SISTEMA: Controle Financeiro Pessoal Multiusuário
-- SGBD:    MySQL 8.0+
-- OBJETIVO: Popular o banco com dados de exemplo para desenvolvimento/testes.
-- ATENÇÃO: Execute APÓS o script 01 - criacao.sql
-- ============================================================================

USE piggy_money;

-- ============================================================================
-- 1. Usuário de demonstração
--    Senha (hash bcrypt para "123456"):
--    $2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy
-- ============================================================================
INSERT INTO usuario (email, telefone, nome, senha_hash)
VALUES ('demo@piggymoney.com', '11999999999', 'Usuário Demo',
        '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy');

-- Captura o ID do usuário demo para reuso
SET @usuario_demo = LAST_INSERT_ID();

-- ============================================================================
-- 2. Categorias adicionais para o usuário demo
--    Obs: a categoria "Sem categoria" já foi criada automaticamente pela trigger.
-- ============================================================================
INSERT INTO categoria (usuario_id, nome, tipo_permitido) VALUES
(@usuario_demo, 'Salário',     'entrada'),
(@usuario_demo, 'Alimentação',  'saida'),
(@usuario_demo, 'Transporte',   'saida'),
(@usuario_demo, 'Lazer',        'saida'),
(@usuario_demo, 'Compras',      'saida'),
(@usuario_demo, 'Investimentos','ambos');

-- ============================================================================
-- 3. Conta corrente (saldo inicial de R$ 5.000,00)
-- ============================================================================
INSERT INTO conta (usuario_id, nome, tipo, saldo_inicial)
VALUES (@usuario_demo, 'Conta Corrente', 'corrente', 5000.00);

SET @conta_corrente = LAST_INSERT_ID();

-- ============================================================================
-- 4. Cartão de crédito (limite de R$ 3.000,00, fecha dia 10, vence dia 15)
--    Vinculado à conta corrente para pagamento da fatura.
-- ============================================================================
INSERT INTO cartao_credito (usuario_id, nome, limite_total, dia_fechamento, dia_vencimento, conta_id)
VALUES (@usuario_demo, 'Cartão Principal', 3000.00, 10, 15, @conta_corrente);

SET @cartao_principal = LAST_INSERT_ID();

-- ============================================================================
-- 5. Cartão benefício — vale-refeição (saldo inicial de R$ 500,00)
-- ============================================================================
INSERT INTO cartao_beneficio (usuario_id, nome, tipo, saldo_inicial)
VALUES (@usuario_demo, 'VR Empresa', 'refeicao', 500.00);

SET @beneficio_vr = LAST_INSERT_ID();

-- ============================================================================
-- 6. Transação de entrada: Salário de R$ 4.500,00 na conta corrente
--    Data: 01/05/2026 (efetivada)
-- ============================================================================
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, conta_id, parcelas_total, parcela_atual)
SELECT @usuario_demo, 'Salário Maio/2026', 4500.00, '2026-05-01',
       c.id, TRUE, 'entrada', @conta_corrente, 1, 1
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Salário';

SET @trans_salario = LAST_INSERT_ID();

-- ============================================================================
-- 7. Compra parcelada no cartão de crédito: R$ 1.200,00 em 2x
--    Data da compra: 10/05/2026
-- ============================================================================

-- Parcela 1/2 (transação mãe)
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, cartao_credito_id,
                       parcelas_total, parcela_atual, transacao_original_id)
SELECT @usuario_demo, 'Smart TV 50" (1/2)', 600.00, '2026-05-10',
       c.id, FALSE, 'saida', @cartao_principal, 2, 1, NULL
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Compras';

SET @trans_mae = LAST_INSERT_ID();

-- Parcela 2/2
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, cartao_credito_id,
                       parcelas_total, parcela_atual, transacao_original_id)
SELECT @usuario_demo, 'Smart TV 50" (2/2)', 600.00, '2026-06-10',
       c.id, FALSE, 'saida', @cartao_principal, 2, 2, @trans_mae
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Compras';

SET @trans_parcela2 = LAST_INSERT_ID();

-- ============================================================================
-- 8. Fatura do cartão (Maio/2026)
--    Fechamento: 10/05/2026, Vencimento: 15/05/2026
--    Total: R$ 600,00 (apenas a primeira parcela)
--    Status: aberta
-- ============================================================================
INSERT INTO fatura_cartao (usuario_id, cartao_credito_id, mes_referencia, ano_referencia,
                           data_fechamento, data_vencimento, total_fatura, status)
VALUES (@usuario_demo, @cartao_principal, 5, 2026,
        '2026-05-10', '2026-05-15', 600.00, 'aberta');

SET @fatura_maio = LAST_INSERT_ID();

-- Vincula a parcela 1 à fatura de Maio
UPDATE transacao
SET fatura_id = @fatura_maio
WHERE id = @trans_mae;

-- ============================================================================
-- 9. Pagamento da fatura (transação futura — ainda não efetivada)
--    Data programada para o vencimento (15/05/2026).
-- ============================================================================
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, conta_id, fatura_id,
                       parcelas_total, parcela_atual)
SELECT @usuario_demo, 'Pagamento Fatura Cartão Principal - Mai/2026', 600.00,
       '2026-05-15', c.id, FALSE, 'saida', @conta_corrente, @fatura_maio, 1, 1
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Sem categoria';

SET @trans_pagamento_fatura = LAST_INSERT_ID();

-- ============================================================================
-- VERIFICAÇÃO
-- ============================================================================
-- SELECT * FROM usuario;
-- SELECT * FROM categoria WHERE usuario_id = @usuario_demo;
-- SELECT * FROM conta WHERE usuario_id = @usuario_demo;
-- SELECT * FROM cartao_credito WHERE usuario_id = @usuario_demo;
-- SELECT * FROM cartao_beneficio WHERE usuario_id = @usuario_demo;
-- SELECT * FROM fatura_cartao WHERE usuario_id = @usuario_demo;
-- SELECT * FROM transacao WHERE usuario_id = @usuario_demo ORDER BY data;
--
-- Para simular o pagamento da fatura:
--   UPDATE transacao SET efetivada = TRUE WHERE id = @trans_pagamento_fatura;
--   SELECT status FROM fatura_cartao WHERE id = @fatura_maio; -- Deve ser 'paga'

-- ============================================================================
-- FIM DO SCRIPT
-- ============================================================================
