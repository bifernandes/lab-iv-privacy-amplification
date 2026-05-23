// output_interface — Entrega serial da chave secreta a partir da dual_port_ram.
//
// Especificacao (FR-004 a FR-010, User Story 3):
//   Apos key_final_ready = 1, le sequencialmente os L bits da RAM
//   (enderecos 0 .. L-1) e os entrega bit a bit com key_secret_valid = 1.
//   Ao final, done = 1 e busy = 0.
//
// FSM (sincrona, reset sincrono):
//   IDLE       -> aguarda enable = 1 e key_final_ready = 1
//   WAIT_READY -> se enable ja estava asserted mas key_final_ready ainda nao
//                 (estado transitorio)
//   READ_ADDR  -> aplica rd_addr e asserta ram_rden; aguarda 1 ciclo de latencia
//   READ_DATA  -> captura ram_data (dado valido neste ciclo apos latencia)
//   OUTPUT_BIT -> asserta key_secret_valid e coloca bit em key_secret_bit;
//                 verifica se todos os L bits foram entregues
//   DONE       -> done = 1, busy = 0 (permanece ate reset)
//   ERROR      -> error = 1 (endereco invalido detectado)
//
// Latencia de leitura da RAM (outdata_reg_b = CLOCK0):
//   Ciclo C : READ_ADDR — aplica rd_addr e ram_rden = 1
//   Ciclo C+1: READ_DATA — ram_data valido neste ciclo
//   Ciclo C+1: OUTPUT_BIT — entrega key_secret_bit/key_secret_valid
//
// Parametros:
//   L     : total de bits a ler (default 100000 = 10^5)
//   ADDRW : largura do barramento de endereco (default 17)

`timescale 1ns/1ps

module output_interface #(
    parameter L     = 100000,   // Total de bits de saida (enderecos 0 .. L-1)
    parameter ADDRW = 17        // Bits de endereco (2^17 = 131072 >= 100000)
)(
    input  wire              clock,
    input  wire              rst,        // reset completo do modulo
    input  wire              rst_fsm,    // reset apenas da FSM (estado e contadores)
    input  wire              enable,     // habilitacao de operacao
    input  wire              ram_data,   // dado lido da Porta B da RAM (1 bit)
    input  wire              key_final_ready, // RAM pronta para leitura (= compunit_done)

    // Saidas para o consumidor downstream
    output reg               key_secret_bit,
    output reg               key_secret_valid,

    // Interface com a RAM (via multiplex_ram)
    output reg  [ADDRW-1:0]  ram_addr,
    output reg               ram_rden,

    // Status
    output reg               busy,
    output reg               done,
    output reg               error
);

    // -----------------------------------------------------------------------
    // Definicao dos estados da FSM
    // -----------------------------------------------------------------------
    localparam ST_IDLE       = 3'd0;
    localparam ST_WAIT_READY = 3'd1;
    localparam ST_READ_ADDR  = 3'd2;
    localparam ST_READ_DATA  = 3'd3;
    localparam ST_OUTPUT_BIT = 3'd4;
    localparam ST_DONE       = 3'd5;
    localparam ST_ERROR      = 3'd6;

    reg [2:0] state;

    // Contador de bits entregues
    // Precisa de bits suficientes para representar L
    reg [$clog2(L)-1:0] bit_cnt;

    // -----------------------------------------------------------------------
    // Logica da FSM (sincrona, reset sincrono)
    // -----------------------------------------------------------------------
    always @(posedge clock) begin
        if (rst) begin
            // Reset completo: todos os sinais ao estado inicial
            state            <= ST_IDLE;
            bit_cnt          <= 0;
            ram_addr         <= {ADDRW{1'b0}};
            ram_rden         <= 1'b0;
            key_secret_bit   <= 1'b0;
            key_secret_valid <= 1'b0;
            busy             <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;

        end else if (rst_fsm) begin
            // Reset apenas da FSM: preserva RAM (nao afeta RAM pois rden=0)
            state            <= ST_IDLE;
            bit_cnt          <= 0;
            ram_addr         <= {ADDRW{1'b0}};
            ram_rden         <= 1'b0;
            key_secret_bit   <= 1'b0;
            key_secret_valid <= 1'b0;
            busy             <= 1'b0;
            done             <= 1'b0;
            error            <= 1'b0;

        end else begin
            // Defaults (sobrescritos por cada estado quando necessario)
            key_secret_valid <= 1'b0;
            ram_rden         <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                ST_IDLE: begin
                    done  <= 1'b0;
                    error <= 1'b0;
                    busy  <= 1'b0;
                    bit_cnt  <= 0;
                    ram_addr <= {ADDRW{1'b0}};

                    if (enable && key_final_ready) begin
                        busy  <= 1'b1;
                        state <= ST_READ_ADDR;
                    end else if (enable && !key_final_ready) begin
                        busy  <= 1'b1;
                        state <= ST_WAIT_READY;
                    end
                end

                // ----------------------------------------------------------
                ST_WAIT_READY: begin
                    if (!enable) begin
                        // enable desassertado durante espera → pausa
                        busy  <= 1'b0;
                        state <= ST_IDLE;
                    end else if (key_final_ready) begin
                        state <= ST_READ_ADDR;
                    end
                    // Senao permanece em WAIT_READY
                end

                // ----------------------------------------------------------
                // Aplica endereco e asserta rden; RAM producao dado no proximo ciclo
                ST_READ_ADDR: begin
                    // Verificacao de endereco invalido (FR-007)
                    if (ram_addr >= L[ADDRW-1:0]) begin
                        ram_rden <= 1'b0;
                        state    <= ST_ERROR;
                    end else begin
                        ram_rden <= 1'b1;
                        state    <= ST_READ_DATA;
                    end
                end

                // ----------------------------------------------------------
                // Captura ram_data (valido neste ciclo)
                ST_READ_DATA: begin
                    ram_rden <= 1'b0;
                    state    <= ST_OUTPUT_BIT;
                end

                // ----------------------------------------------------------
                // Entrega o bit ao consumidor
                ST_OUTPUT_BIT: begin
                    key_secret_bit   <= ram_data;
                    key_secret_valid <= 1'b1;

                    if (bit_cnt == L - 1) begin
                        // Ultimo bit entregue
                        state <= ST_DONE;
                    end else begin
                        bit_cnt  <= bit_cnt + 1;
                        ram_addr <= ram_addr + {{(ADDRW-1){1'b0}}, 1'b1};
                        state    <= ST_READ_ADDR;
                    end
                end

                // ----------------------------------------------------------
                ST_DONE: begin
                    key_secret_valid <= 1'b0;
                    busy             <= 1'b0;
                    done             <= 1'b1;
                    // Permanece em DONE ate reset ou rst_fsm
                end

                // ----------------------------------------------------------
                ST_ERROR: begin
                    key_secret_valid <= 1'b0;
                    busy             <= 1'b0;
                    done             <= 1'b0;
                    error            <= 1'b1;
                    // Permanece em ERROR ate reset ou rst_fsm
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
