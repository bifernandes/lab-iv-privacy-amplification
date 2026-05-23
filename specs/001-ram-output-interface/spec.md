# Feature Specification: RAM Multiplexer e Output Interface — Pipeline de Privacy Amplification

**Feature Branch**: `001-ram-output-interface`
**Created**: 2026-05-23
**Status**: Draft
**Input**: User description: "Pipeline de privacy amplification com compression_unit, RAM de 2 portas, multiplex_ram e OutputInterface"

---

## Contexto do Sistema

O projeto implementa **privacy amplification** em hardware (FPGA DE2-115, Quartus Prime Lite 18.1) usando hashing universal baseado em matriz de Toeplitz. O pipeline é composto pelos seguintes estágios:

| Estágio            | Função                                                                 |
|--------------------|------------------------------------------------------------------------|
| `input_buffer`     | Recebe a chave reconciliada — N = 10⁶ bits                            |
| `seed_generator`   | Fornece os N + L − 1 bits de seed para construir a matriz de Toeplitz |
| `compression_unit` | Executa o hash universal (produto Toeplitz × vetor); grava na RAM      |
| `multiplex_ram`    | Arbitra o acesso de leitura à Porta B da RAM                           |
| `output_interface` | Lê os blocos da chave final da RAM e os entrega bit a bit              |

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Compressão e Gravação da Chave Final na RAM (Priority: P1)

O sistema realiza o produto interno entre os bits da chave reconciliada e as linhas da matriz de Toeplitz, e grava cada bit resultante da chave final (L bits) na RAM dual-port. O `compression_unit` tem acesso exclusivo à porta de escrita e prioridade sobre a porta de leitura durante a compressão.

**Why this priority**: É o núcleo funcional do pipeline. Sem a gravação correta dos L bits na RAM nenhum outro estágio pode operar.

**Independent Test**: Pode ser verificado isoladamente fornecendo vetores de entrada sintéticos ao `compression_unit` e comparando os L bits gravados na RAM com o resultado de referência calculado em Python (`scipy.linalg.toeplitz`).

**Acceptance Scenarios**:

1. **Given** que `compression_unit` recebe N bits de chave e N+L-1 bits de seed válidos, **When** o processamento é concluído, **Then** os L bits da chave final estão gravados corretamente nos endereços 0…L-1 da RAM, `compunit_done = 1` e `compunit_busy = 0`.
2. **Given** que o `compression_unit` está ativo (`compunit_busy = 1`), **When** o `output_interface` solicita leitura simultânea da Porta B, **Then** o `multiplex_ram` roteia o endereço e `rden` do `compression_unit`, ignorando o pedido do `output_interface`.
3. **Given** uma seed e chave totalmente zeradas, **When** o pipeline executa, **Then** todos os L bits resultantes são 0 (sanity check).

---

### User Story 2 — Arbitração sem Conflito da Leitura da Porta B (Priority: P2)

O módulo `multiplex_ram` garante que nunca haja dois masters acessando a Porta B de leitura da RAM simultaneamente, respeitando a prioridade do `compression_unit`.

**Why this priority**: Sem arbitração correta ocorrerão leituras corrompidas pelo `output_interface`, comprometendo a chave secreta entregue.

**Independent Test**: Pode ser testado com um testbench que aplica pedidos simultâneos dos dois masters e verifica qual endereço/rden é roteado para a RAM em cada ciclo.

**Acceptance Scenarios**:

1. **Given** `compunit_busy = 1` e `outinterface_rden = 1` ao mesmo tempo, **When** o `multiplex_ram` arbitra, **Then** `rd_ram_addr` = `compunit_addr` e `rd_ram_rden` = `compunit_rden`.
2. **Given** `compunit_busy = 0` e `compunit_done = 0` (compressão não iniciada), **When** `outinterface_rden = 1`, **Then** `rd_ram_addr` = `outinterface_addr` e `rd_ram_rden = 1`.
3. **Given** `compunit_done = 1`, **When** `outinterface_rden = 1`, **Then** `rd_ram_addr` = `outinterface_addr` e `rd_ram_rden = 1` (compressão já concluída, output_interface pode ler livremente).

---

### User Story 3 — Entrega da Chave Secreta pelo OutputInterface (Priority: P3)

Após a conclusão da compressão (`key_final_ready = 1`), o `output_interface` lê sequencialmente os L bits da chave final da RAM e os entrega bit a bit com sinalização de validade.

**Why this priority**: É o estágio de saída do pipeline; depende de P1 e P2 estarem corretos.

**Independent Test**: Pode ser testado em simulação fornecendo um conteúdo pré-programado na RAM e verificando que `key_secret_bit` e `key_secret_valid` reproduzem corretamente o padrão esperado, e que `done = 1` ao término.

**Acceptance Scenarios**:

1. **Given** `enable = 1` e `key_final_ready = 1`, **When** o `output_interface` inicia a leitura, **Then** `busy = 1`, os bits são entregues sequencialmente em `key_secret_bit` com `key_secret_valid = 1` por cada bit válido.
2. **Given** que todos os L bits foram entregues, **When** o último bit é emitido, **Then** `done = 1`, `busy = 0` e `key_secret_valid = 0`.
3. **Given** que `rst = 1` ou `rst_fsm = 1` durante a operação, **When** o reset é aplicado, **Then** `busy`, `done`, `error` e `key_secret_valid` voltam ao estado inicial sem corrupção do conteúdo da RAM.
4. **Given** condição de erro (ex.: leitura além do tamanho da RAM), **When** o erro é detectado, **Then** `error = 1` e `done = 0`.

---

### Edge Cases

- O que ocorre se `enable` for desassertado durante a leitura pelo `output_interface`? (operação deve pausar ou terminar conforme FSM)
- O que ocorre se `key_final_ready` for assertado antes do `compression_unit` gravar todos os L bits? (não deve acontecer por design, mas deve ser protegido por `compunit_done`)
- O que ocorre se o endereço calculado pelo `output_interface` ultrapassar 10⁵ − 1? (`error = 1`)
- O que ocorre se o clock for aplicado mas `rst` nunca for desassertado? (módulos devem permanecer em reset indefinidamente sem travar o sistema)

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O sistema DEVE implementar uma RAM dual-port com 10⁵ palavras de 1 bit, gerada pelo IP Catalog do Quartus Prime Lite 18.1, com interfaces: `data[0:0]`, `wr_addr[16:0]`, `wr_enable`, `rd_addr[16:0]`, `rd_enable`, `clock`, `q[0]`.
- **FR-002**: O módulo `multiplex_ram` DEVE arbitrar o acesso de leitura à Porta B da RAM entre `compression_unit` e `output_interface`, com prioridade sempre ao `compression_unit` enquanto `compunit_busy = 1`.
- **FR-003**: O módulo `multiplex_ram` DEVE expor as interfaces: `compunit_addr[16:0]`, `compunit_rden`, `compunit_done`, `compunit_busy`, `outinterface_addr[16:0]`, `outinterface_rden`, `rd_ram_addr[16:0]`, `rd_ram_rden`.
- **FR-004**: O módulo `output_interface` DEVE ler sequencialmente os L bits armazenados na RAM após `key_final_ready = 1` e entregá-los em `key_secret_bit` com `key_secret_valid` asserted por ciclo de dado válido.
- **FR-005**: O módulo `output_interface` DEVE expor as interfaces: `clock`, `rst`, `rst_fsm`, `enable`, `ram_data`, `key_final_ready`, `key_secret_bit`, `key_secret_valid`, `ram_addr[16:0]`, `ram_rden`, `busy`, `done`, `error`.
- **FR-006**: O módulo `output_interface` DEVE assertar `busy = 1` durante a leitura da RAM e `done = 1` ao concluir a entrega de todos os bits.
- **FR-007**: O módulo `output_interface` DEVE assertar `error = 1` quando detectar leitura fora dos limites válidos da RAM (endereço ≥ 10⁵).
- **FR-008**: Ambos `rst` e `rst_fsm` DEVEM retornar o `output_interface` ao estado inicial; `rst` reseta o módulo completo, `rst_fsm` reseta apenas a máquina de estados interna.
- **FR-009**: O `compression_unit` NÃO DEVE iniciar leitura pela Porta B da RAM enquanto estiver no modo de escrita, salvo se a arquitetura do IP de RAM dual-port permitir operações simultâneas em portas distintas.
- **FR-010**: O sistema DEVE garantir que `output_interface` só inicie leitura da RAM após `compunit_done = 1`, prevenindo leitura de dados incompletos.

### Key Entities

- **RAM Dual-Port**: Memória de 10⁵ × 1 bit. Porta A (write-only pelo `compression_unit`); Porta B (read, arbitrada pelo `multiplex_ram`). Endereçamento com 17 bits (2¹⁷ = 131.072 ≥ 100.000).
- **compression_unit**: Módulo upstream que realiza o produto Toeplitz e grava os L bits da chave final. Expõe `compunit_busy` e `compunit_done` para coordenação.
- **multiplex_ram**: Módulo combinacional/sequencial que roteia o acesso de leitura da Porta B entre os dois masters.
- **output_interface**: Módulo com FSM que lê a RAM sequencialmente e serializa a chave secreta para o consumidor downstream.
- **Chave Reconciliada**: Vetor de N = 10⁶ bits de entrada do pipeline.
- **Chave Final (Comprimida)**: Vetor de L bits resultante do hash universal; L < N.
- **Seed**: Vetor de N+L-1 bits que define a primeira linha e coluna da matriz de Toeplitz.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% dos L bits da chave final gravados na RAM pelo `compression_unit` devem coincidir bit a bit com o resultado do modelo de referência em Python para todos os vetores de teste definidos.
- **SC-002**: O `multiplex_ram` nunca roteia endereços/rden do `output_interface` enquanto `compunit_busy = 1`; verificado em 100% dos ciclos de simulação com estímulos de acesso simultâneo.
- **SC-003**: O `output_interface` entrega os L bits em ordem correta (endereço 0 → L-1) sem bits faltando ou repetidos, verificado por comparação com o conteúdo esperado da RAM.
- **SC-004**: Os sinais `busy`, `done`, `error` e `key_secret_valid` do `output_interface` respeitam o protocolo de handshake em 100% dos cenários de teste (inclui reset, enable tardio e condição de erro).
- **SC-005**: O design sintetiza sem erros no Quartus Prime Lite 18.1 para a FPGA DE2-115 (Cyclone IV EP4CE115F29C7), sem violações de timing no caminho crítico do pipeline.
- **SC-006**: A RAM gerada pelo IP Catalog ocupa no máximo os recursos de memória embarcada (M9K) disponíveis na DE2-115 para 10⁵ × 1 bit.

---

## Assumptions

- O valor de L (tamanho da chave comprimida) é conhecido em tempo de síntese e configurado como parâmetro; para os testes iniciais será usado L = 10⁵ bits (endereços 0…99.999).
- A RAM dual-port gerada pelo IP Catalog do Quartus 18.1 (`altsyncram`) tem leitura síncrona na Porta B; o `output_interface` deve aguardar 1 ciclo de clock após assertar `rd_enable` para ler `q[0]`.
- O `compression_unit` já está implementado e expõe corretamente os sinais `compunit_busy` e `compunit_done`; apenas os novos módulos (`multiplex_ram`, RAM IP, `output_interface`) são escopo desta feature.
- Não há requisito de pipeline paralelo: o `output_interface` só inicia após `compunit_done = 1`; não há sobreposição de execução entre compressão e entrega da chave.
- O clock é único e compartilhado por todos os módulos do pipeline.
- Reset assíncrono não é obrigatório; reset síncrono é suficiente para esta plataforma.
- O sinal `key_final_ready` é equivalente funcional de `compunit_done` visto pelo `output_interface`; podem ser o mesmo sinal roteado.
