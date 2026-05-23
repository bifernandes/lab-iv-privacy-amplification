# Tasks: RAM Multiplexer e Output Interface — Pipeline de Privacy Amplification

**Input**: Design documents from `specs/001-ram-output-interface/`
**Prerequisites**: spec.md ✅ | plan.md ⚠️ (gerado a partir do contexto do projeto — `compression_unit.v`, `top.v`, `RUN.md`)

**Plataforma**: Verilog / Quartus Prime Lite 18.1 / ModelSim / Python (scipy)
**Target FPGA**: DE2-115 (Cyclone IV EP4CE115F29C7) — clock único 50 MHz

**Escopo**: Apenas os novos módulos: RAM dual-port IP (`altsyncram`), `multiplex_ram.v`,
`output_interface.v`, adaptação da interface de escrita do `compression_unit`, integração em `top.v`.

---

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Pode executar em paralelo (arquivo diferente, sem dependência incompleta)
- **[Story]**: User story à qual a tarefa pertence (US1, US2, US3)
- Caminhos relativos a `src/` salvo indicação contrária

---

## Phase 1: Setup (Infraestrutura de Testes)

**Objetivo**: Criar estrutura de diretórios e scripts de referência Python para as novas fases do pipeline

- [x] T001 Criar diretório `src/tb_pipeline/` e arquivo vazio `src/tb_pipeline/.gitkeep` para o novo conjunto de testbenches do pipeline
- [x] T002 [P] Criar script Python `high_level_simulation/gen_pipeline_vectors.py` que gera: um par (key, seed) de N bits e N+L−1 bits respectivamente, executa o produto Toeplitz via `scipy.linalg.toeplitz`, e salva os L bits resultantes como `src/tb_pipeline/expected_ram.hex` (um bit por linha, hex)

---

## Phase 2: Foundational (RAM Dual-Port IP — Pré-requisito para Todas as Stories)

**Objetivo**: Gerar e registrar o IP `altsyncram` dual-port (100 000 × 1 bit) que é usado por todos os módulos downstream

**⚠️ CRÍTICO**: Nenhuma user story pode ser implementada antes que esta fase esteja completa

- [x] T003 Gerar IP dual-port RAM via Quartus IP Catalog (MegaWizard / IP Catalog): `altsyncram`, 100 000 palavras de 1 bit, endereço de 17 bits, Porta A = write-only (dados, wr_addr, wren, clock), Porta B = read-only (rd_addr, rden, q, clock); salvar em `src/dual_port_ram/dual_port_ram.v` + `src/dual_port_ram/dual_port_ram.qip`
- [x] T004 Registrar o IP no projeto Quartus: adicionar `set_global_assignment -name QIP_FILE dual_port_ram/dual_port_ram.qip` em `src/lab_iv_privacy_amplification.qsf` e adicionar `src/dual_port_ram/` ao `SEARCH_PATH` se necessário

**Checkpoint**: RAM IP registrado — implementação das user stories pode iniciar

---

## Phase 3: User Story 1 — Compressão e Gravação da Chave Final na RAM (Priority: P1) 🎯 MVP

**Goal**: O `compression_unit` grava sequencialmente os L bits da chave comprimida nos endereços 0…L−1 da Porta A da RAM; ao final, `compunit_done = 1` e `compunit_busy = 0`.

**Independent Test**: Fornecer vetores sintéticos ao `compression_unit` via testbench, deixar o módulo processar, depois ler a RAM e comparar bit a bit com `high_level_simulation/gen_pipeline_vectors.py`.

### Implementação — User Story 1

- [x] T005 [US1] Adaptar `src/compression_unit.v` adicionando FSM de escrita sequencial na Porta A da RAM: acrescentar parâmetro `L` (número de bits de saída), saídas `compunit_busy`, `compunit_done`, `wr_addr[16:0]`, `wr_data`, `wr_enable`; estados FSM: `IDLE → COMPUTE → WRITE → DONE`; manter compatibilidade com a lógica Toeplitz existente baseada em `hash_engine.v`
- [x] T006 [P] [US1] Criar testbench `src/tb_pipeline/tb_compression_ram.v` que: instancia `compression_unit` + `dual_port_ram`, aplica vetores de entrada (key de N bits, matrix_window de N+L−1 bits) usando `$readmemh`, aguarda `compunit_done = 1`, lê os L bits da Porta B da RAM e salva em `src/tb_pipeline/sim/output_dump.hex`
- [x] T007 [US1] Criar script de compilação ModelSim `src/tb_pipeline/sim_compression.do`: `vlib work`, `vlog ../compression_unit.v ../hash_engine.v ../dual_port_ram/dual_port_ram.v tb_compression_ram.v`, `vsim work.tb_compression_ram -L altera_mf_ver -do "run -all; quit"`
- [x] T008 [US1] Executar simulação com `vsim` a partir de `src/tb_pipeline/` e validar `src/tb_pipeline/sim/output_dump.hex` contra `expected_ram.hex` com `high_level_simulation/validate_dump.py` (SC-001: 100% dos L bits corretos); cobrir acceptance scenarios 1 (compressão correta) e 3 (input zero → output zero)

**Checkpoint**: US1 verificada — L bits da chave comprimida estão corretos na RAM

---

## Phase 4: User Story 2 — Arbitração sem Conflito da Leitura da Porta B (Priority: P2)

**Goal**: `multiplex_ram` garante que apenas um master acessa a Porta B por vez; prioridade sempre ao `compression_unit` enquanto `compunit_busy = 1`.

**Independent Test**: Testbench aplica pedidos simultâneos dos dois masters em todos os cenários de prioridade; verificar `rd_ram_addr` e `rd_ram_rden` a cada ciclo.

### Implementação — User Story 2

- [x] T009 [US2] Implementar `src/multiplex_ram.v` (lógica combinacional pura): entradas `compunit_addr[16:0]`, `compunit_rden`, `compunit_done`, `compunit_busy`, `outinterface_addr[16:0]`, `outinterface_rden`; saídas `rd_ram_addr[16:0]`, `rd_ram_rden`; regra: se `compunit_busy = 1` → rotear compunit; caso contrário → rotear outinterface (conforme FR-002 e FR-003)
- [x] T010 [P] [US2] Criar testbench `src/tb_pipeline/tb_multiplex_ram.v` cobrindo os três acceptance scenarios: (a) `compunit_busy=1 + outinterface_rden=1` → compunit vence; (b) `compunit_busy=0, compunit_done=0` + `outinterface_rden=1` → outinterface vence; (c) `compunit_done=1` + `outinterface_rden=1` → outinterface vence; usar `$monitor` para dump ciclo a ciclo
- [x] T011 [US2] Compilar e executar `src/tb_pipeline/tb_multiplex_ram.v` no ModelSim; verificar SC-002 (100% dos ciclos com acesso simultâneo roteados corretamente para o master de maior prioridade)

**Checkpoint**: US2 verificada — multiplex_ram arbitra corretamente em todos os cenários

---

## Phase 5: User Story 3 — Entrega da Chave Secreta pelo OutputInterface (Priority: P3)

**Goal**: Após `key_final_ready = 1`, `output_interface` lê os L bits da RAM sequencialmente e os entrega em `key_secret_bit` com `key_secret_valid = 1` por bit válido; ao final, `done = 1`.

**Independent Test**: Inicializar `dual_port_ram` com conteúdo conhecido via `$readmemh`, assertar `key_final_ready`, capturar a sequência de `key_secret_bit`/`key_secret_valid` e comparar com o conteúdo esperado.

### Implementação — User Story 3

- [x] T012 [US3] Implementar `src/output_interface.v` com FSM síncrona: parâmetro `L`; entradas `clock`, `rst`, `rst_fsm`, `enable`, `ram_data`, `key_final_ready`; saídas `key_secret_bit`, `key_secret_valid`, `ram_addr[16:0]`, `ram_rden`, `busy`, `done`, `error`; estados: `IDLE → WAIT_READY → READ_ADDR → READ_DATA → OUTPUT_BIT → [CHECK_DONE] → DONE / ERROR`; `error = 1` quando `ram_addr >= 100000` (FR-007); leitura síncrona da RAM requer 1 ciclo de latência após `rden` (conforme assumption da spec)
- [x] T013 [P] [US3] Criar testbench `src/tb_pipeline/tb_output_interface.v` que: instancia `output_interface` + `dual_port_ram` inicializado com padrão conhecido; cobre acceptance scenarios 1 (leitura sequencial), 2 (done ao final), 3 (reset durante operação), 4 (condição de erro por endereço inválido)
- [x] T014 [US3] Compilar e executar `src/tb_pipeline/tb_output_interface.v` no ModelSim; verificar SC-003 (bits em ordem sem falhas/repetições) e SC-004 (`busy`/`done`/`error`/`key_secret_valid` respeitam protocolo em 100% dos cenários)
- [x] T015 [US3] Validar edge cases no ModelSim: (a) `enable` desassertado durante leitura → FSM pausa ou termina conforme design; (b) `key_final_ready` assertado antes de `compunit_done` ser propagado → não deve iniciar (dependência via FR-010); (c) `rst` aplicado em qualquer estado → retorno limpo a IDLE sem corrupção da RAM; (d) clock com `rst` nunca liberado → permanece em reset indefinidamente

**Checkpoint**: US3 verificada — chave entregue bit a bit com sinalização correta

---

## Phase 6: Integração, Síntese e Polish

**Objetivo**: Conectar todos os módulos em `top.v`, sintetizar para a DE2-115 e documentar

- [x] T016 Atualizar `src/top.v` para instanciar `dual_port_ram`, `multiplex_ram` e `output_interface` junto ao `compression_unit` existente: conectar Porta A da RAM às saídas de escrita do `compression_unit`, Porta B da RAM às saídas de `multiplex_ram`, entradas de `multiplex_ram` conectadas a `compression_unit` e `output_interface`, sinais `key_secret_bit`/`key_secret_valid`/`busy`/`done` mapeados a LEDs/pinos disponíveis da DE2-115 no `.qsf`
- [x] T017 [P] Criar testbench de integração completa `src/tb_pipeline/tb_top_pipeline.v` que exercita o pipeline end-to-end: seed → compression_unit → RAM → multiplex_ram → output_interface → chave secreta
- [ ] T018 Executar compilação completa no Quartus Prime Lite 18.1 (`Processing → Start Compilation`) e verificar SC-005: zero erros de compilação, sem violações de timing no caminho crítico a 50 MHz na DE2-115 *(requer Quartus IDE — pendente execução manual)*
- [ ] T019 [P] Inspecionar Fitter Report e verificar SC-006: recursos M9K para 100 000 × 1 bit estão dentro do budget da EP4CE115F29C7 (a placa possui 432 blocos M9K) *(requer Quartus IDE — pendente execução manual)*
- [x] T020 [P] Atualizar `RUN.md` na raiz do repositório com as instruções do novo pipeline: comandos ModelSim para cada testbench, fluxo de síntese, mapeamento de pinos dos novos sinais

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
    └─► Phase 2 (RAM IP) ──────────────────────────────────┐
              └─► Phase 3 (US1 — Compressão + RAM)         │
              └─► Phase 4 (US2 — multiplex_ram)            │ podem rodar em paralelo
              └─► Phase 5 (US3 — output_interface)         │ após Phase 2 concluída
                        └─► Phase 6 (Integração + Síntese) ┘
```

### User Story Dependencies

- **US1 (P1)**: Depende apenas da Phase 2 (RAM IP) — independente de US2/US3
- **US2 (P2)**: Depende da Phase 2 (RAM IP) — independente de US1/US3 (usa apenas interface de `compression_unit` via sinais de controle)
- **US3 (P3)**: Depende da Phase 2 (RAM IP) e conceitualmente de US1 (RAM deve ter conteúdo) e US2 (precisa de `multiplex_ram` para leitura) — mas pode ser testada isoladamente com RAM pré-carregada

### Dependências Dentro de Cada Story

- **US1**: T002 → T005 (vectors antes de adaptar CU) → T006 || T007 → T008
- **US2**: T009 → T010 || T011
- **US3**: T012 → T013 || T014 → T015
- **Integração**: T016 → T017 → T018 → T019 || T020

---

## Parallel Opportunities

```
# Phase 1 — rodar em paralelo:
T001: criar src/tb_pipeline/
T002: gen_pipeline_vectors.py

# Phase 2 — sequencial (T003 antes de T004):
T003 → T004

# Phase 3, 4, 5 — após Phase 2, podem rodar em paralelo:
Developer A: T005 → T006 → T007 → T008  (US1)
Developer B: T009 → T010 → T011         (US2)
Developer C: T012 → T013 → T014 → T015 (US3)

# Dentro de cada story, tarefas [P] paralelas:
US1: T006 (testbench) || T007 (script .do) após T005
US2: T010 (testbench) em paralelo com início de T011 (espera T009)
US3: T013 (testbench) em paralelo com início de T014 (espera T012)

# Phase 6:
T016 → T017 → T018 → [T019 || T020]
```

---

## Implementation Strategy

### MVP First (User Story 1 + validação funcional)

1. Completar Phase 1: Setup (T001, T002)
2. Completar Phase 2: RAM IP (T003, T004) — **CRÍTICO, bloqueia tudo**
3. Completar Phase 3: US1 (T005–T008)
4. **PARAR E VALIDAR**: `PASS: L/L vetores ok` no script Python
5. Demonstrar: RAM com chave comprimida correta

### Entrega Incremental

1. Setup + RAM IP → base pronta
2. US1 completa → comprimir e gravar na RAM ✓
3. US2 completa → arbitração sem conflito ✓
4. US3 completa → entregar chave bit a bit ✓
5. Integração → pipeline end-to-end na DE2-115 ✓

### Estratégia de Paralelo (equipe)

Com múltiplos desenvolvedores, após Phase 2 concluída:
- Dev A → US1 (compression_unit + RAM)
- Dev B → US2 (multiplex_ram)
- Dev C → US3 (output_interface)

---

## Notes

- `[P]` = arquivos distintos, sem dependências incompletas → podem rodar em paralelo
- `[USn]` = rastreabilidade à user story n da spec.md
- Latência de leitura síncrona da Porta B: 1 ciclo de clock após `rden` assertado — `output_interface` deve compensar na FSM
- L = 10⁵ (100 000) bits nos testes iniciais; endereçamento com 17 bits (2¹⁷ = 131 072 ≥ 100 000)
- `rst` = reset completo do módulo; `rst_fsm` = reset apenas da FSM do `output_interface`
- Commit após cada tarefa ou grupo lógico; usar `vlog` para verificação de sintaxe rápida antes de `vsim`
- Evitar: tarefas vagas, conflitos no mesmo arquivo, dependências cross-story que quebrem a testabilidade independente
