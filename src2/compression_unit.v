// Compression unit que implementa multiplicacao por matriz Toeplitz sobre GF(2):
//
//   hash_out = (T @ key) mod 2
//
// onde T tem shape L x W e T[i,j] depende apenas de (i - j):
//   - T[i,j] = matrix_window[j - i]         para j >= i (diagonais superiores)
//   - T[i,j] = matrix_window[W + i - j - 1] para j <  i (diagonais inferiores)
//
// O matrix_window tem W+L-1 bits e define todas as diagonais da matriz, com
// a mesma convencao usada por high_level_simulation/compression_model.py.
//
// Cada engine i recebe sua linha-i pre-montada (W bits nao contiguos do
// matrix_window) e calcula hash_out[i] = XOR(key & row_i).
//
// FSM de escrita na Porta A da RAM (novidade em relacao a versao anterior):
//   IDLE    -> aguarda start=1
//   COMPUTE -> aguarda 1 ciclo para os hash_engines registrarem a saida
//   WRITE   -> escreve hash_out[P-1:0] bit a bit na RAM (P ciclos)
//   DONE    -> compunit_done=1, compunit_busy=0; aguarda reset ou novo start
//
// Parametros:
//   P : paralelismo / numero de hash engines = numero de bits de saida por rodada
//   W : largura da chave (bits) = numero de colunas da matriz Toeplitz
//   L : total de bits de saida gravados na RAM (deve ser multiplo de P)
//
// Para L = P (caso de uso do testbench de validacao), a FSM executa uma unica
// rodada COMPUTE + WRITE.  Para L > P (producao), a FSM itera ceil(L/P) vezes
// com as mesmas entradas (key, matrix_window); o caller deve fornecer um
// matrix_window diferente a cada rodada, ou usar L = P.

`timescale 1ns/1ps

module compression_unit #(
    parameter P = 8,    // Paralelismo (hash engines em paralelo)
    parameter W = 16,   // Largura da chave (bits)
    parameter L = 8     // Total de bits de saida (deve ser multiplo de P)
)(
    input  wire              clock,
    input  wire              reset,

    // Dados de entrada (estaticos durante a computacao)
    input  wire [W-1:0]      key,
    input  wire [W+L-2:0]    matrix_window,  // W+L-1 bits

    // Controle
    input  wire              start,           // pulso ou nivel alto para iniciar

    // Interface de escrita na RAM (Porta A)
    output reg  [16:0]       wr_addr,
    output reg               wr_data,
    output reg               wr_enable,

    // Status
    output reg               compunit_busy,
    output reg               compunit_done,

    // Saida combinacional dos hash engines (util para depuracao)
    output wire [P-1:0]      hash_out
);

    // -----------------------------------------------------------------------
    // Gera P hash engines, cada um calculando 1 bit de hash_out
    // -----------------------------------------------------------------------
    genvar gi, gj;
    generate
        for (gi = 0; gi < P; gi = gi + 1) begin : gen_hash_engines
            wire [W-1:0] toeplitz_row;

            for (gj = 0; gj < W; gj = gj + 1) begin : gen_row_bits
                if (gj >= gi) begin : ge_case
                    assign toeplitz_row[gj] = matrix_window[gj - gi];
                end else begin : lt_case
                    assign toeplitz_row[gj] = matrix_window[W + gi - gj - 1];
                end
            end

            hash_engine #(
                .W(W)
            ) engine_inst (
                .clock   (clock),
                .reset   (reset),
                .key     (key),
                .matrix  (toeplitz_row),
                .hash_b  (hash_out[gi])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // FSM de escrita na Porta A da RAM
    // -----------------------------------------------------------------------
    localparam FSM_IDLE    = 2'd0;
    localparam FSM_COMPUTE = 2'd1;
    localparam FSM_WRITE   = 2'd2;
    localparam FSM_DONE    = 2'd3;

    reg [1:0] state;

    // Contador de bits escritos dentro de uma rodada (0 .. P-1)
    reg [$clog2(P)-1:0] bit_cnt;

    // Contador de rodadas (0 .. L/P - 1); necessario apenas para L > P
    localparam ROUNDS = L / P;
    reg [$clog2(ROUNDS > 1 ? ROUNDS : 2)-1:0] round_cnt;

    always @(posedge clock) begin
        if (reset) begin
            state         <= FSM_IDLE;
            wr_addr       <= 17'd0;
            wr_data       <= 1'b0;
            wr_enable     <= 1'b0;
            compunit_busy <= 1'b0;
            compunit_done <= 1'b0;
            bit_cnt       <= 0;
            round_cnt     <= 0;
        end else begin
            case (state)
                // ----------------------------------------------------------
                FSM_IDLE: begin
                    wr_enable     <= 1'b0;
                    compunit_done <= 1'b0;
                    if (start) begin
                        compunit_busy <= 1'b1;
                        wr_addr       <= 17'd0;
                        bit_cnt       <= 0;
                        round_cnt     <= 0;
                        state         <= FSM_COMPUTE;
                    end
                end

                // ----------------------------------------------------------
                // Aguarda 1 ciclo para hash_engine registrar o resultado
                FSM_COMPUTE: begin
                    wr_enable <= 1'b0;
                    state     <= FSM_WRITE;
                end

                // ----------------------------------------------------------
                // Escreve hash_out[bit_cnt] no endereco corrente da RAM
                FSM_WRITE: begin
                    wr_data   <= hash_out[bit_cnt];
                    wr_enable <= 1'b1;

                    if (bit_cnt == P - 1) begin
                        // Ultima bit desta rodada
                        bit_cnt <= 0;
                        if (round_cnt == ROUNDS - 1) begin
                            // Todas as rodadas concluidas
                            wr_addr   <= wr_addr + 17'd1; // avanca endereco do ultimo bit
                            state     <= FSM_DONE;
                        end else begin
                            round_cnt <= round_cnt + 1;
                            wr_addr   <= wr_addr + 17'd1;
                            state     <= FSM_COMPUTE; // proxima rodada
                        end
                    end else begin
                        bit_cnt <= bit_cnt + 1;
                        wr_addr <= wr_addr + 17'd1;
                    end
                end

                // ----------------------------------------------------------
                FSM_DONE: begin
                    wr_enable     <= 1'b0;
                    compunit_busy <= 1'b0;
                    compunit_done <= 1'b1;
                    // Permanece em DONE ate reset ou novo ciclo
                end

                default: state <= FSM_IDLE;
            endcase
        end
    end

endmodule
