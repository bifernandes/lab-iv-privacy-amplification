# Prompt — Implementação do módulo `OUTPUT INTERFACE`
### Privacy Amplification (CV-QKD) · ENGG57 2026.1 · FPGA Altera DE2-115 (Cyclone IV)

> Este documento é um **prompt de trabalho para o Claude Code**. Ele descreve **somente** a fatia do projeto sob minha responsabilidade: o módulo **Output Interface**. Tudo o que estiver fora desse escopo (Input Buffer, Seed Generator, Hash Engine, Compression Unit, Control Unit) é responsabilidade de outros membros da equipe e **não deve ser implementado aqui** — no máximo, deve ser tratado como interface externa (portas) com a qual meu módulo conversa.

---

## 0. PRIORIDADE ABSOLUTA — ler antes de escrever qualquer linha

**Eu já tenho um esboço de código deste módulo.** A primeira tarefa não é gerar código novo, e sim **entender o que eu já fiz**.

Ordem obrigatória de execução:

1. **Localizar e ler o esboço existente.** Procure no repositório os arquivos `.v` relacionados ao output interface.
   - Caminho do esboço (preencher): `[INSERIR CAMINHO DO ESBOÇO AQUI]`
   - Se não for óbvio qual arquivo é, liste os `.v` encontrados e pergunte antes de assumir.
2. **Resumir o que o esboço faz**: portas (nomes, larguras, direção), protocolo de handshake adotado, máquina de estados (se houver), convenção de reset, parametrizações já existentes.
3. **Apontar o que está incompleto, incorreto ou ausente** em relação aos requisitos da Seção 4.
4. **Só então complementar/corrigir** — preservando ao máximo os nomes de portas, convenções e a estrutura que eu já escolhi. **Não reescrever do zero.** Se um trecho meu estiver errado, explicar o porquê antes de alterar.
5. Onde o esboço for omisso, seguir as diretrizes da Seção 5 e a interface de referência da Seção 6 (que é **sugestão**, subordinada ao que já existe).

---

## 1. Objetivo do módulo

O **Output Interface** é a etapa final do pipeline de *Privacy Amplification*. Sua única responsabilidade é **disponibilizar a chave secreta final** (produzida pela *Compression Unit*) para o exterior do sistema, de forma controlada, com sinalização de validade/conclusão e respeitando os requisitos de throughput, frequência e segurança.

Ele **não** gera, comprime nem faz hash da chave. Ele apenas a **entrega**.

---

## 2. Posição no sistema (contexto filtrado)

Decomposição funcional sugerida do sistema (apenas para situar o módulo):

```
Input Buffer → Seed Gen/Loader → Hash Engine → Compression Unit → [ OUTPUT INTERFACE ] → exterior
                                                       ▲
                                                  Control Unit (coordena o fluxo via FSM global)
```

- **Upstream (entra no meu módulo):** a chave final comprimida vem da **Compression Unit**, palavra a palavra ou via buffer.
- **Downstream (sai do meu módulo):** um consumidor externo (top-level / GPIO / FIFO / UART — definido na integração) lê a chave.
- **Control Unit:** dá os sinais de coordenação (ex.: `start`/`done` globais). Meu módulo pode ter **sua própria FSM local** para gerenciar o streaming, mas não duplica a lógica de controle global.

---

## 3. Escopo

**ESTÁ sob minha responsabilidade:**
- O módulo `output_interface` em Verilog.
- Sua FSM local de streaming/handshake.
- Sinalização de status (`busy`, `done`, `error`).
- Um **testbench de unidade** que valide o módulo isoladamente.
- Se necessário, **instâncias** de IP do Quartus (ex.: FIFO `scfifo`) — apenas instanciadas, não reimplementadas.

**NÃO está sob minha responsabilidade (tratar só como portas externas):**
- Geração/compressão/hash da chave.
- A FSM global do sistema (Control Unit).
- PLL / geração do clock de 100 MHz (vem do top-level).
- Mapeamento físico de pinos (é integração de top-level).

---

## 4. Requisitos aplicáveis ao Output Interface

Filtrados do enunciado. Os marcados como *(parcial)* aplicam-se ao sistema todo, mas têm impacto direto neste módulo.

### 4.1 Funcionais
| ID | Requisito | O que significa AQUI |
|----|-----------|----------------------|
| **RF-08** | Saída da chave secreta | **Requisito principal.** Disponibilizar a chave secreta final após a conclusão do processamento. Verificação na RTM: **Teste funcional**. |
| RF-05 *(parcial)* | Inicialização / reset | O módulo deve ter reset que o leve a um estado inicial limpo e ocioso. |
| RF-06 *(parcial)* | Controle por FSM | O streaming de saída deve ser coordenado por uma máquina de estados local. |
| RF-02 *(parcial)* | Configuração de parâmetros | O tamanho da chave final `l` deve ser parametrizável/sinalizável, não fixo em código. |

### 4.2 Não Funcionais
| ID | Requisito | Impacto no módulo |
|----|-----------|-------------------|
| RNF-01 | Throughput ≥ 100 Mbps | O caminho de saída não pode ser o gargalo. |
| RNF-02 | Frequência ≥ 100 MHz (Cyclone IV) | O módulo deve fechar timing a 100 MHz. Saídas registradas; evitar caminhos combinacionais longos. |
| RNF-03 | Lógica < 80% do FPGA | Implementação enxuta. |
| RNF-04 | Memória < 80% | Se usar FIFO/buffer, dimensionar com cuidado. |
| RNF-05 | Escalabilidade | Largura do barramento e tamanho da chave **parametrizáveis**. |
| RNF-06 | Latência < 10 ms por bloco | O estágio de saída deve adicionar latência desprezível. |
| RNF-07 | Robustez | Detectar e **sinalizar** inconsistências (ex.: dado válido sem espaço, tamanho inválido, fim inesperado) via `error`. |
| RNF-08 | Segurança | **Não expor dados intermediários.** Só a chave final sai. Considerar zeragem (zeroize) de registradores/buffers após a entrega e em reset. |

### 4.3 Desempenho
| ID | Alvo | Nota de projeto |
|----|------|-----------------|
| RD-01 | Throughput ≥ 100 Mbps | A 100 MHz, 1 bit/ciclo já atinge o mínimo; ver Seção 5 para margem. |
| RD-02 | Frequência ≥ 100 MHz | — |
| RD-03 | Bloco ≥ 10⁶ bits | O contador de palavras/bits deve suportar até ~10⁶ bits. |
| RD-04 | Paralelismo parametrizável | Via `DATA_WIDTH`. |
| RD-05/06 | Lógica/Memória ≤ 80% | — |

### 4.4 Rastreabilidade (RTM) — linha do meu módulo
| Requisito | Módulo Arquitetural | Método de Verificação |
|-----------|---------------------|------------------------|
| **RF-08** | **Output Interface** | **Teste funcional** |

O relatório técnico precisará declarar o cumprimento de RF-08 e dos RNF/RD acima para este bloco — então o código e o testbench devem **deixar evidências** disso (ex.: testbench que demonstra entrega correta da chave; comentários ligando portas/estados aos requisitos).

---

## 5. Diretrizes de projeto (obrigatórias)

- **Linguagem:** Verilog. Sem SystemVerilog, sem VHDL.
- **Modularidade e responsabilidades separadas:**
  - **Não declarar módulo dentro de módulo.** Cada módulo em seu próprio arquivo, conectado por **instanciação**.
  - O `output_interface` deve ter uma responsabilidade única (entregar a chave). Lógica de buffering/FIFO, se necessária, fica em **módulo separado instanciado** ou em **IP do Quartus instanciado** (ex.: `scfifo`).
- **Parametrização:** usar `parameter` para largura de dados e tamanho de chave/contadores (RNF-05, RD-04). Nada hardcoded.
- **FSM:** máquina de estados local explícita (estados nomeados, transições claras). Estado inicial ocioso após reset.
- **Handshake recomendado:** protocolo *valid/ready* (estilo AXI-Stream) nas duas pontas — `valid`/`ready`/`data`/`last`. É robusto, sintetizável e tolera estagnação (stall) do consumidor. **Se o meu esboço já usar outro protocolo, manter o do esboço.**
- **Timing (RNF-02):** saídas **registradas**; evitar caminhos combinacionais longos entre `s_*` e `m_*` (usar registrador/skid buffer se preciso para não criar caminho combinacional passante).
- **Reset:** seguir a convenção já usada no meu esboço (síncrono vs assíncrono, ativo-alto vs ativo-baixo). Documentar qual é.
- **Margem de throughput:** throughput ≈ `DATA_WIDTH × frequência` (sem stalls). A 100 MHz:
  - `DATA_WIDTH = 1` → 100 Mbps (mínimo, **sem margem** para stalls — não recomendado).
  - `DATA_WIDTH = 8` → 800 Mbps (boa margem). Sugerir default ≥ 8 (ex.: 32), mas **parametrizável** e idealmente **alinhado à largura do pipeline upstream**.
- **Segurança (RNF-08):** zerar registradores que contêm fragmentos da chave após a entrega e em reset; nunca expor sinais internos da chave em portas de status/debug.

---

## 6. Interface de referência (SUGESTÃO — subordinada ao esboço existente)

> Use isto **apenas** se o esboço não definir as portas. Se o esboço já as define, **preserve os nomes e larguras dele** e adapte esta referência.

```verilog
module output_interface #(
    parameter DATA_WIDTH    = 32,   // bits/ciclo entregues (paralelismo) — RNF-05/RD-04
    parameter LEN_WIDTH     = 21    // largura do contador p/ até ~10^6 bits — RD-03
)(
    input  wire                    clk,
    input  wire                    rst_n,        // ajustar à convenção do esboço

    // ---- Upstream: vem da Compression Unit (escravo: eu recebo) ----
    input  wire [DATA_WIDTH-1:0]   s_data,       // palavra da chave final
    input  wire                    s_valid,      // palavra válida
    output wire                    s_ready,      // estou pronto para receber
    input  wire                    s_last,       // marca a última palavra do bloco
    input  wire [LEN_WIDTH-1:0]    key_len_bits, // tamanho l da chave final (opcional)

    // ---- Downstream: vai para o exterior (mestre: eu entrego) ----
    output wire [DATA_WIDTH-1:0]   m_data,
    output wire                    m_valid,
    input  wire                    m_ready,
    output wire                    m_last,

    // ---- Status / controle ----
    output wire                    busy,         // entrega em andamento
    output wire                    done,         // chave final totalmente entregue
    output wire                    error         // inconsistência detectada (RNF-07)
);
```

**Comportamento esperado (resumo):**
- Em reset: estado ocioso, registradores zerados, `m_valid=0`, `busy=0`, `done=0`, `error=0`.
- Aceita palavras de `s_*` quando `s_ready && s_valid`.
- Entrega palavras em `m_*` respeitando `m_ready` (sem perder dados quando o consumidor estagna).
- Marca `m_last` na última palavra; ao concluir, pulsa/levanta `done`.
- Detecta e sinaliza inconsistências em `error` (ex.: `key_len_bits` inválido, fim inesperado).
- Após entrega completa, zera fragmentos da chave (RNF-08) e volta ao estado ocioso.

> Sobre o mapeamento físico de saída (GPIO/UART/LEDs/7-seg para a demo): **fora do escopo deste módulo**. O `output_interface` expõe um barramento de streaming genérico; a integração no top-level decide o destino físico.

---

## 7. Entregáveis deste módulo

1. `output_interface.v` — o módulo, completo, comentado, ligando estados/portas aos requisitos relevantes.
2. (Se necessário) módulo(s) auxiliar(es) **instanciado(s)** (ex.: FIFO próprio) ou nota de qual IP do Quartus instanciar (`scfifo`).
3. `tb_output_interface.v` — testbench de unidade que demonstra:
   - entrega correta de uma chave (caminho feliz);
   - comportamento com consumidor estagnado (`m_ready` oscilando);
   - reset no meio da operação;
   - sinalização de `error` em caso de inconsistência.

---

## 8. Checklist de aceitação (revisar ao final)

- [ ] Esboço existente foi lido, resumido e **preservado** (não reescrito do zero).
- [ ] RF-08: chave final é entregue após conclusão; `done` sinaliza corretamente.
- [ ] FSM local explícita e estado ocioso após reset (RF-05, RF-06).
- [ ] `DATA_WIDTH` e tamanho de chave/contador **parametrizáveis** (RNF-05, RD-03/04).
- [ ] Saídas registradas; sem caminho combinacional passante de `s_*` para `m_*` (RNF-02).
- [ ] Throughput de projeto ≥ 100 Mbps com a `DATA_WIDTH` escolhida (RNF-01/RD-01).
- [ ] `error` detecta e sinaliza inconsistências (RNF-07).
- [ ] Zeragem de fragmentos da chave após entrega e em reset; sem vazamento em portas de status (RNF-08).
- [ ] Sem módulo declarado dentro de módulo; só instanciação; responsabilidade única.
- [ ] Testbench cobre caminho feliz, stall, reset e erro.
- [ ] Verilog puro, compatível com Quartus / Cyclone IV.
