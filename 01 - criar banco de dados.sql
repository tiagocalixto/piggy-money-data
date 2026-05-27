-- ============================================================================
-- SCRIPT: Criação do Banco de Dados - Piggy Money
-- SISTEMA: Controle Financeiro Pessoal Multiusuário
-- SGBD:    MySQL 8.0+
-- ============================================================================
-- REGRA FUNDAMENTAL: Todas as tabelas possuem usuario_id como FK.
-- Todas as consultas da aplicação devem filtrar por usuario_id primeiro.
-- Por isso, TODO índice composto começa com usuario_id.
-- ============================================================================

CREATE DATABASE IF NOT EXISTS piggy_money
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE piggy_money;

-- ============================================================================
-- 1. TABELA: usuario
--    Entidade raiz do sistema. Todo dado pertence a um usuário.
--    Restrição: pelo menos um contato (email ou telefone) deve ser preenchido.
-- ============================================================================
CREATE TABLE usuario (
    id           INT           NOT NULL AUTO_INCREMENT,
    email        VARCHAR(255)  NULL,
    telefone     VARCHAR(20)   NULL,
    nome         VARCHAR(100)  NOT NULL,
    senha_hash   VARCHAR(255)  NULL,
    data_criacao TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_usuario PRIMARY KEY (id),

    -- Índices únicos: MySQL 8.0 InnoDB permite múltiplos NULLs em colunas UNIQUE,
    -- o que é exatamente o comportamento desejado (email e telefone são opcionais).
    CONSTRAINT uq_usuario_email    UNIQUE (email),
    CONSTRAINT uq_usuario_telefone UNIQUE (telefone),

    -- Garante que pelo menos um canal de contato exista
    CONSTRAINT chk_usuario_contato CHECK (email IS NOT NULL OR telefone IS NOT NULL)
) ENGINE=InnoDB;

-- ============================================================================
-- 2. TABELA: conta
--    Contas bancárias/correntes do usuário (ex: conta corrente, poupança).
--    Índice (usuario_id, nome): buscas de conta por nome dentro de um usuário.
-- ============================================================================
CREATE TABLE conta (
    id            INT            NOT NULL AUTO_INCREMENT,
    usuario_id    INT            NOT NULL,
    nome          VARCHAR(100)   NOT NULL,
    tipo          VARCHAR(50)    NOT NULL,
    saldo_inicial DECIMAL(15,2)  NOT NULL DEFAULT 0.00,

    CONSTRAINT pk_conta PRIMARY KEY (id),

    CONSTRAINT fk_conta_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE,

    -- Índice: busca de conta por nome dentro do escopo do usuário
    INDEX idx_conta_usuario_nome (usuario_id, nome)
) ENGINE=InnoDB;

-- ============================================================================
-- 3. TABELA: cartao_credito
--    Cartões de crédito do usuário. Vincula-se opcionalmente a uma conta
--    para pagamento da fatura.
--    Índice (usuario_id, nome): buscas de cartão por nome dentro do usuário.
-- ============================================================================
CREATE TABLE cartao_credito (
    id              INT            NOT NULL AUTO_INCREMENT,
    usuario_id      INT            NOT NULL,
    nome            VARCHAR(100)   NOT NULL,
    limite_total    DECIMAL(15,2)  NOT NULL,
    dia_fechamento  INT            NOT NULL,
    dia_vencimento  INT            NOT NULL,
    conta_id        INT            NULL COMMENT 'Conta usada para pagar a fatura',

    CONSTRAINT pk_cartao_credito PRIMARY KEY (id),

    CONSTRAINT fk_cartao_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_cartao_conta
        FOREIGN KEY (conta_id) REFERENCES conta(id)
        ON DELETE SET NULL,

    CONSTRAINT chk_cartao_dia_fechamento CHECK (dia_fechamento BETWEEN 1 AND 31),
    CONSTRAINT chk_cartao_dia_vencimento CHECK (dia_vencimento BETWEEN 1 AND 31),

    -- Índice: busca de cartão por nome dentro do escopo do usuário
    INDEX idx_cartao_usuario_nome (usuario_id, nome)
) ENGINE=InnoDB;

-- ============================================================================
-- 4. TABELA: cartao_beneficio
--    Cartões de benefício (vale-refeição, vale-alimentação, outros).
--    Índice (usuario_id, nome): buscas de benefício por nome.
-- ============================================================================
CREATE TABLE cartao_beneficio (
    id            INT            NOT NULL AUTO_INCREMENT,
    usuario_id    INT            NOT NULL,
    nome          VARCHAR(100)   NOT NULL,
    tipo          ENUM('refeicao','alimentacao','outros') NOT NULL,
    saldo_inicial DECIMAL(15,2)  NOT NULL DEFAULT 0.00,

    CONSTRAINT pk_cartao_beneficio PRIMARY KEY (id),

    CONSTRAINT fk_beneficio_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE,

    -- Índice: busca de benefício por nome dentro do escopo do usuário
    INDEX idx_beneficio_usuario_nome (usuario_id, nome)
) ENGINE=InnoDB;

-- ============================================================================
-- 5. TABELA: categoria
--    Categorias para classificar transações.
--    Ao criar um usuário, uma trigger insere automaticamente a categoria
--    padrão "Sem categoria" com tipo_permitido = 'ambos'.
--    Índice (usuario_id, nome): buscas de categoria por nome.
-- ============================================================================
CREATE TABLE categoria (
    id             INT          NOT NULL AUTO_INCREMENT,
    usuario_id     INT          NOT NULL,
    nome           VARCHAR(100) NOT NULL,
    tipo_permitido ENUM('entrada','saida','ambos') NOT NULL DEFAULT 'ambos',

    CONSTRAINT pk_categoria PRIMARY KEY (id),

    CONSTRAINT fk_categoria_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE,

    -- Índice: busca de categoria por nome dentro do escopo do usuário
    INDEX idx_categoria_usuario_nome (usuario_id, nome)
) ENGINE=InnoDB;

-- ============================================================================
-- 6. TABELA: fatura_cartao
--    Representa a fatura mensal de um cartão de crédito.
--
--    Índice 1 (usuario_id, cartao_credito_id, status):
--      Otimiza consultas como "listar faturas abertas de um cartão específico",
--      que é a query mais frequente (ex: tela de detalhes do cartão).
--
--    Índice 2 (usuario_id, data_vencimento):
--      Otimiza "listar faturas que vencem este mês" na dashboard do usuário.
--    ========================================================================
CREATE TABLE fatura_cartao (
    id               INT            NOT NULL AUTO_INCREMENT,
    usuario_id       INT            NOT NULL,
    cartao_credito_id INT           NOT NULL,
    mes_referencia   INT            NOT NULL CHECK (mes_referencia BETWEEN 1 AND 12),
    ano_referencia   INT            NOT NULL,
    data_fechamento  DATE           NOT NULL,
    data_vencimento  DATE           NOT NULL,
    total_fatura     DECIMAL(15,2)  NOT NULL DEFAULT 0.00,
    status           ENUM('aberta','paga','parcial') NOT NULL DEFAULT 'aberta',

    CONSTRAINT pk_fatura_cartao PRIMARY KEY (id),

    CONSTRAINT fk_fatura_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_fatura_cartao
        FOREIGN KEY (cartao_credito_id) REFERENCES cartao_credito(id)
        ON DELETE CASCADE,

    -- Garante apenas uma fatura por cartão/mês/ano
    CONSTRAINT uq_fatura_cartao_mes
        UNIQUE (usuario_id, cartao_credito_id, mes_referencia, ano_referencia),

    -- Index 1: consulta mais comum — faturas abertas de um cartão
    INDEX idx_fatura_usuario_cartao_status (usuario_id, cartao_credito_id, status),

    -- Index 2: faturas que vencem em determinado período (dashboard)
    INDEX idx_fatura_usuario_vencimento (usuario_id, data_vencimento)
) ENGINE=InnoDB;

-- ============================================================================
-- 7. TABELA: transacao
--    Tabela central do sistema. Toda movimentação financeira é uma transação.
--
--    REGRA DE PARCELAMENTO:
--      Quando parcelas_total > 1, são criadas N transações filhas ligadas
--      pelo campo transacao_original_id à transação "mãe" (a primeira).
--      Cada parcela é uma linha independente com seu próprio parcela_atual,
--      efetivada, data, fatura_id, etc.
--
--    REGRA DE LIMITE DO CARTÃO:
--      Limite disponível = limite_total - SUM(total_fatura) das faturas
--      com status = 'aberta' OU 'parcial'. Esse cálculo é feito em runtime
--      pela aplicação, não armazenado no banco.
--
--    REGRA DE PAGAMENTO DA FATURA:
--      Quando o usuário paga a fatura, uma transação do tipo 'saida' é
--      gerada na conta corrente vinculada, com fatura_id preenchido.
--      Ao ser efetivada (efetivada = TRUE), um trigger atualiza o status
--      da fatura para 'paga'.
--
--    ÍNDICES (todos começam com usuario_id):
--      1. (usuario_id, categoria_id, data)       → relatórios por categoria
--      2. (usuario_id, conta_id, data)            → extrato bancário
--      3. (usuario_id, cartao_credito_id, data)   → extrato do cartão
--      4. (usuario_id, cartao_beneficio_id, data) → extrato do benefício
--      5. (usuario_id, tipo_movimento, data)     → entradas vs saídas
--      6. (usuario_id, efetivada, data)           → transações pendentes
-- ============================================================================
CREATE TABLE transacao (
    id                     INT            NOT NULL AUTO_INCREMENT,
    usuario_id             INT            NOT NULL,
    descricao              VARCHAR(255)   NOT NULL,
    valor                  DECIMAL(15,2)  NOT NULL,
    data                   DATE           NOT NULL,
    categoria_id           INT            NOT NULL,
    efetivada              BOOLEAN        NOT NULL DEFAULT FALSE,
    tipo_movimento         ENUM('entrada','saida') NOT NULL,

    -- FK opcionais: exatamente uma origem/destino (conta, cartão ou benefício)
    conta_id               INT            NULL,
    cartao_credito_id      INT            NULL,
    cartao_beneficio_id    INT            NULL,

    -- Parcelamento
    parcelas_total         INT            NOT NULL DEFAULT 1,
    parcela_atual          INT            NOT NULL DEFAULT 1,
    transacao_original_id  INT            NULL COMMENT 'Auto-FK: aponta para a transação mãe do parcelamento',

    -- Fatura vinculada (preenchido quando é saída no cartão de crédito
    -- ou quando é o pagamento de uma fatura via conta corrente)
    fatura_id              INT            NULL,

    CONSTRAINT pk_transacao PRIMARY KEY (id),

    -- FK obrigatória
    CONSTRAINT fk_transacao_usuario
        FOREIGN KEY (usuario_id) REFERENCES usuario(id)
        ON DELETE CASCADE,

    CONSTRAINT fk_transacao_categoria
        FOREIGN KEY (categoria_id) REFERENCES categoria(id)
        ON DELETE RESTRICT,

    -- FK opcionais: ON DELETE SET NULL para preservar histórico ao excluir origem
    CONSTRAINT fk_transacao_conta
        FOREIGN KEY (conta_id) REFERENCES conta(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_transacao_cartao_credito
        FOREIGN KEY (cartao_credito_id) REFERENCES cartao_credito(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_transacao_cartao_beneficio
        FOREIGN KEY (cartao_beneficio_id) REFERENCES cartao_beneficio(id)
        ON DELETE SET NULL,

    CONSTRAINT fk_transacao_fatura
        FOREIGN KEY (fatura_id) REFERENCES fatura_cartao(id)
        ON DELETE SET NULL,

    -- Self-FK para parcelamento
    CONSTRAINT fk_transacao_original
        FOREIGN KEY (transacao_original_id) REFERENCES transacao(id)
        ON DELETE SET NULL,

    -- Validações
    CONSTRAINT chk_transacao_parcela_total CHECK (parcelas_total >= 1),
    CONSTRAINT chk_transacao_parcela_atual CHECK (parcela_atual >= 1 AND parcela_atual <= parcelas_total),

    -- =====================================================================
    -- ÍNDICES (todos prefixados com usuario_id, conforme regra fundamental)
    -- =====================================================================

    -- 1. Relatórios por categoria: "gastos do mês agrupados por categoria"
    INDEX idx_trans_usuario_categoria_data (usuario_id, categoria_id, data),

    -- 2. Extrato bancário: "listar transações da conta X ordenadas por data"
    INDEX idx_trans_usuario_conta_data (usuario_id, conta_id, data),

    -- 3. Extrato do cartão de crédito: "compras do cartão X no período Y"
    INDEX idx_trans_usuario_credito_data (usuario_id, cartao_credito_id, data),

    -- 4. Extrato do benefício: "gastos do vale-refeição"
    INDEX idx_trans_usuario_beneficio_data (usuario_id, cartao_beneficio_id, data),

    -- 5. Dashboard: "entradas vs saídas do mês"
    INDEX idx_trans_usuario_tipo_data (usuario_id, tipo_movimento, data),

    -- 6. Transações pendentes: "o que ainda não foi efetivado?"
    INDEX idx_trans_usuario_efetivada_data (usuario_id, efetivada, data)
) ENGINE=InnoDB;

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- ---------------------------------------------------------------------------
-- TRIGGER 1: Cria categoria padrão "Sem categoria" ao inserir um novo usuário.
-- Garante que todo usuário tenha pelo menos uma categoria para classificar
-- transações, evitando erros de FK nas inserções iniciais.
-- ---------------------------------------------------------------------------
DELIMITER //

CREATE TRIGGER trg_usuario_after_insert_categoria
    AFTER INSERT ON usuario
    FOR EACH ROW
BEGIN
    INSERT INTO categoria (usuario_id, nome, tipo_permitido)
    VALUES (NEW.id, 'Sem categoria', 'ambos');
END//

-- ---------------------------------------------------------------------------
-- TRIGGER 2: Ao efetivar o pagamento de uma fatura, atualiza o status da
-- fatura para 'paga'.
-- Dispara no UPDATE da transacao quando efetivada muda de FALSE para TRUE
-- e a transação possui fatura_id (é um pagamento de fatura).
-- ---------------------------------------------------------------------------
CREATE TRIGGER trg_transacao_update_efetiva_fatura
    AFTER UPDATE ON transacao
    FOR EACH ROW
BEGIN
    -- Se a transação é um pagamento de fatura e foi efetivada agora
    IF NEW.efetivada = TRUE
       AND OLD.efetivada = FALSE
       AND NEW.fatura_id IS NOT NULL
       AND NEW.tipo_movimento = 'saida'
    THEN
        UPDATE fatura_cartao
        SET status = 'paga'
        WHERE id = NEW.fatura_id
          AND status IN ('aberta', 'parcial');
    END IF;
END//

-- ---------------------------------------------------------------------------
-- TRIGGER 3: Se o pagamento da fatura for desefetivado (revertido),
-- volta o status da fatura para 'aberta'.
-- ---------------------------------------------------------------------------
CREATE TRIGGER trg_transacao_update_desefetiva_fatura
    AFTER UPDATE ON transacao
    FOR EACH ROW
BEGIN
    IF NEW.efetivada = FALSE
       AND OLD.efetivada = TRUE
       AND NEW.fatura_id IS NOT NULL
       AND NEW.tipo_movimento = 'saida'
    THEN
        UPDATE fatura_cartao
        SET status = 'aberta'
        WHERE id = NEW.fatura_id;
    END IF;
END//

DELIMITER ;

-- ============================================================================
-- DADOS DE DEMONSTRAÇÃO
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Usuário de demonstração
--    Senha (hash bcrypt para "123456"):
--    $2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy
-- ---------------------------------------------------------------------------
INSERT INTO usuario (email, telefone, nome, senha_hash)
VALUES ('demo@piggymoney.com', '11999999999', 'Usuário Demo',
        '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy');

-- Captura o ID do usuário demo para reuso (em scripts posteriores, use SELECT)
SET @usuario_demo = LAST_INSERT_ID();

-- ---------------------------------------------------------------------------
-- 2. Categoria padrão "Sem categoria"
--    Já foi criada automaticamente pela trigger trg_usuario_after_insert_categoria.
--    Mas podemos inserir categorias adicionais para o demo.
-- ---------------------------------------------------------------------------
INSERT INTO categoria (usuario_id, nome, tipo_permitido) VALUES
(@usuario_demo, 'Salário',     'entrada'),
(@usuario_demo, 'Alimentação',  'saida'),
(@usuario_demo, 'Transporte',   'saida'),
(@usuario_demo, 'Lazer',        'saida'),
(@usuario_demo, 'Compras',      'saida'),
(@usuario_demo, 'Investimentos','ambos');

-- ---------------------------------------------------------------------------
-- 3. Conta corrente (saldo inicial de R$ 5.000,00)
-- ---------------------------------------------------------------------------
INSERT INTO conta (usuario_id, nome, tipo, saldo_inicial)
VALUES (@usuario_demo, 'Conta Corrente', 'corrente', 5000.00);

SET @conta_corrente = LAST_INSERT_ID();

-- ---------------------------------------------------------------------------
-- 4. Cartão de crédito (limite de R$ 3.000,00, fecha dia 10, vence dia 15)
--    Vinculado à conta corrente para pagamento da fatura.
-- ---------------------------------------------------------------------------
INSERT INTO cartao_credito (usuario_id, nome, limite_total, dia_fechamento, dia_vencimento, conta_id)
VALUES (@usuario_demo, 'Cartão Principal', 3000.00, 10, 15, @conta_corrente);

SET @cartao_principal = LAST_INSERT_ID();

-- ---------------------------------------------------------------------------
-- 5. Cartão benefício — vale-refeição (saldo inicial de R$ 500,00)
-- ---------------------------------------------------------------------------
INSERT INTO cartao_beneficio (usuario_id, nome, tipo, saldo_inicial)
VALUES (@usuario_demo, 'VR Empresa', 'refeicao', 500.00);

SET @beneficio_vr = LAST_INSERT_ID();

-- ---------------------------------------------------------------------------
-- 6. Transação de entrada: Salário de R$ 4.500,00 na conta corrente
--    Data: 01/05/2026 (efetivada)
-- ---------------------------------------------------------------------------
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, conta_id, parcelas_total, parcela_atual)
SELECT @usuario_demo, 'Salário Maio/2026', 4500.00, '2026-05-01',
       c.id, TRUE, 'entrada', @conta_corrente, 1, 1
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Salário';

SET @trans_salario = LAST_INSERT_ID();

-- ---------------------------------------------------------------------------
-- 7. Compra parcelada no cartão de crédito: R$ 1.200,00 em 2x
--    Data da compra: 10/05/2026
--    Serão criadas 2 parcelas (transações filhas) vinculadas à transação mãe.
-- ---------------------------------------------------------------------------

-- Transação mãe (parcela 1/2): será a referência para as demais parcelas
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, cartao_credito_id,
                       parcelas_total, parcela_atual, transacao_original_id)
SELECT @usuario_demo, 'Smart TV 50" (1/2)', 600.00, '2026-05-10',
       c.id, FALSE, 'saida', @cartao_principal, 2, 1, NULL
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Compras';

SET @trans_mae = LAST_INSERT_ID();

-- Parcela 2/2: aponta para a transação mãe via transacao_original_id
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, cartao_credito_id,
                       parcelas_total, parcela_atual, transacao_original_id)
SELECT @usuario_demo, 'Smart TV 50" (2/2)', 600.00, '2026-06-10',
       c.id, FALSE, 'saida', @cartao_principal, 2, 2, @trans_mae
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Compras';

SET @trans_parcela2 = LAST_INSERT_ID();

-- Atualiza a transação mãe para apontar para si mesma (ou mantém NULL; a
-- convenção aqui é: transacao_original_id da primeira parcela = NULL, e as
-- filhas apontam para a primeira. Opcionalmente, podemos setar a mãe com
-- seu próprio ID, mas NULL é semanticamente mais claro: NULL = "sou a origem")
-- Já está NULL — não precisa atualizar.

-- ---------------------------------------------------------------------------
-- 8. Fatura do cartão (Maio/2026)
--    Fechamento: 10/05/2026, Vencimento: 15/05/2026
--    Total: R$ 600,00 (apenas a primeira parcela entra nesta fatura)
--    Status: aberta
-- ---------------------------------------------------------------------------
INSERT INTO fatura_cartao (usuario_id, cartao_credito_id, mes_referencia, ano_referencia,
                           data_fechamento, data_vencimento, total_fatura, status)
VALUES (@usuario_demo, @cartao_principal, 5, 2026,
        '2026-05-10', '2026-05-15', 600.00, 'aberta');

SET @fatura_maio = LAST_INSERT_ID();

-- Vincula a parcela 1 à fatura de Maio
UPDATE transacao
SET fatura_id = @fatura_maio
WHERE id = @trans_mae;

-- ---------------------------------------------------------------------------
-- 9. Pagamento da fatura (transação futura — ainda não efetivada)
--    Gerado automaticamente um dia após o fechamento (11/05/2026),
--    com data programada para o vencimento (15/05/2026).
--    Tipo: saída na conta corrente, vinculada à fatura.
--    efetivada = FALSE (transação futura/pendente).
-- ---------------------------------------------------------------------------
INSERT INTO transacao (usuario_id, descricao, valor, data, categoria_id,
                       efetivada, tipo_movimento, conta_id, fatura_id,
                       parcelas_total, parcela_atual)
SELECT @usuario_demo, 'Pagamento Fatura Cartão Principal - Mai/2026', 600.00,
       '2026-05-15', c.id, FALSE, 'saida', @conta_corrente, @fatura_maio, 1, 1
FROM categoria c
WHERE c.usuario_id = @usuario_demo AND c.nome = 'Sem categoria';

SET @trans_pagamento_fatura = LAST_INSERT_ID();

-- ============================================================================
-- VERIFICAÇÃO DOS DADOS INSERIDOS
-- ============================================================================
-- Execute os comandos abaixo para validar a inserção:
--
-- SELECT * FROM usuario;
-- SELECT * FROM categoria WHERE usuario_id = @usuario_demo;
-- SELECT * FROM conta WHERE usuario_id = @usuario_demo;
-- SELECT * FROM cartao_credito WHERE usuario_id = @usuario_demo;
-- SELECT * FROM cartao_beneficio WHERE usuario_id = @usuario_demo;
-- SELECT * FROM fatura_cartao WHERE usuario_id = @usuario_demo;
-- SELECT * FROM transacao WHERE usuario_id = @usuario_demo ORDER BY data;
--
-- Para simular o pagamento da fatura (efetivar a transação):
--   UPDATE transacao SET efetivada = TRUE WHERE id = @trans_pagamento_fatura;
--   -- A trigger trg_transacao_update_efetiva_fatura mudará a fatura para 'paga'.
--   SELECT status FROM fatura_cartao WHERE id = @fatura_maio; -- Deve ser 'paga'

-- ============================================================================
-- RESUMO DOS ÍNDICES E SUAS FINALIDADES
-- ============================================================================
--
-- TABELA          | ÍNDICE                                      | CONSULTA TÍPICA
-- ----------------|---------------------------------------------|-------------------------------
-- conta           | idx_conta_usuario_nome                      | "Buscar conta por nome"
-- cartao_credito  | idx_cartao_usuario_nome                     | "Buscar cartão por nome"
-- cartao_beneficio| idx_beneficio_usuario_nome                  | "Buscar benefício por nome"
-- categoria       | idx_categoria_usuario_nome                  | "Buscar categoria por nome"
-- fatura_cartao   | idx_fatura_usuario_cartao_status            | "Faturas abertas do cartão X"
-- fatura_cartao   | idx_fatura_usuario_vencimento               | "Faturas que vencem em maio"
-- transacao       | idx_trans_usuario_categoria_data            | "Gastos por categoria no mês"
-- transacao       | idx_trans_usuario_conta_data                | "Extrato da conta corrente"
-- transacao       | idx_trans_usuario_credito_data              | "Extrato do cartão de crédito"
-- transacao       | idx_trans_usuario_beneficio_data            | "Extrato do vale-refeição"
-- transacao       | idx_trans_usuario_tipo_data                 | "Total de entradas vs saídas"
-- transacao       | idx_trans_usuario_efetivada_data            | "Transações pendentes"
--
-- ============================================================================
-- FIM DO SCRIPT
-- ============================================================================
