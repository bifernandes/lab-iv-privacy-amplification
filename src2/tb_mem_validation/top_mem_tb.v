// Testbench de validacao da v1 (compression_unit.v) usando IPs altsyncram.
//
// Fluxo:
//   1. ROM (16x23) e pre-carregada via input_vectors.mif e fornece a cada
//      ciclo um par {matrix_window[14:0], key[7:0]}.
//   2. compression_unit (W=8, P=8) consome key/matrix_window e produz
//      hash_out[7:0] com 1 ciclo de latencia.
//   3. RAM (16x8) e um shadow array Verilog capturam hash_out, indexados pelo
//      wr_addr atrasado em 2 ciclos em relacao ao rd_addr (latencia ROM+DUT).
//   4. Ao final, $writememh dumpa o shadow para output_dump.hex.
//
// Latencia total (rd_addr=k -> hash_out de k valido em hash_out): 2 ciclos.
//   ciclo c:   address_a = k entra na ROM (combinacional do counter)
//   ciclo c+1: ROM produz q_a = palavra[k]; DUT samples key/matrix
//   ciclo c+2: hash_out = hash de palavra[k] valido (capturado em wr_addr=k)
//
// Execucao recomendada (ModelSim/Questa Altera), a partir de
// src/tb_mem_validation/:
//   vlib work
//   vlog *.v ../compression_unit.v ../hash_engine.v
//   vsim -L altera_mf_ver work.top_mem_tb -do "run -all; quit"
// O arquivo sim/output_dump.hex sera gerado.

`timescale 1ns/1ps

module top_mem_tb;

    localparam W = 8;
    localparam P = 8;
    localparam MW_BITS = W + P - 1;     // 15
    localparam WORD_BITS = W + MW_BITS; // 23
    localparam DEPTH = 16;
    localparam LATENCY = 2;

    reg clock;
    reg reset;

    // Counter unico de ciclos pos-reset. Dirige rd/wr de forma deterministica.
    reg [5:0] cycle_counter;
    reg done;

    wire rd_in_progress = (cycle_counter < DEPTH);
    wire wr_in_progress = (cycle_counter >= LATENCY) && (cycle_counter < DEPTH + LATENCY);

    wire [3:0] rd_addr = rd_in_progress ? cycle_counter[3:0] : 4'd0;
    wire [3:0] wr_addr = wr_in_progress ? (cycle_counter[3:0] - LATENCY[3:0]) : 4'd0;
    wire       wren    = wr_in_progress;

    // ROM -> {matrix_window[14:0], key[7:0]}
    wire [WORD_BITS-1:0]  rom_q;
    wire [W-1:0]          key           = rom_q[W-1:0];
    wire [MW_BITS-1:0]    matrix_window = rom_q[WORD_BITS-1:W];

    input_rom u_rom (
        .clock   (clock),
        .address (rd_addr),
        .q       (rom_q)
    );

    // DUT: a v1 do compression_unit
    wire [P-1:0] hash_out;

    compression_unit #(
        .P(P),
        .W(W)
    ) u_dut (
        .clock         (clock),
        .reset         (reset),
        .key           (key),
        .matrix_window (matrix_window),
        .hash_out      (hash_out)
    );

    // RAM destino: espelha o shadow array, util como referencia em waveform
    output_ram u_ram (
        .clock   (clock),
        .address (wr_addr),
        .data    (hash_out),
        .wren    (wren),
        .q       () // q nao usado; lemos do shadow para o dump
    );

    // Shadow array para dump determinístico, independente da implementacao do IP
    reg [7:0] shadow [0:DEPTH-1];
    integer init_i;

    // Clock
    initial clock = 1'b0;
    always #5 clock = ~clock; // 100 MHz

    // Reset e sequenciamento
    initial begin
        reset = 1'b1;
        for (init_i = 0; init_i < DEPTH; init_i = init_i + 1) begin
            shadow[init_i] = 8'h00;
        end
        // Mantem reset por ~3 ciclos
        #32;
        reset = 1'b0;
    end

    // Counter sequencial
    always @(posedge clock) begin
        if (reset) begin
            cycle_counter <= 6'd0;
            done          <= 1'b0;
        end else if (!done) begin
            if (cycle_counter == DEPTH + LATENCY - 1) begin
                done <= 1'b1;
            end
            cycle_counter <= cycle_counter + 6'd1;
        end
    end

    // Captura shadow no mesmo ciclo em que wren ativa
    always @(posedge clock) begin
        if (!reset && wren) begin
            shadow[wr_addr] <= hash_out;
        end
    end

    // Dump e finish
    integer dump_i;
    initial begin
        // Espera done pulsar
        wait (done == 1'b1);
        // Mais um ciclo para garantir que a ultima escrita estabilizou no shadow
        @(posedge clock);
        $display("[tb] dump shadow:");
        for (dump_i = 0; dump_i < DEPTH; dump_i = dump_i + 1) begin
            $display("  addr=%0d hash=%02h", dump_i, shadow[dump_i]);
        end
        $writememh("sim/output_dump.hex", shadow);
        $display("[tb] wrote output_dump.hex");
        $finish;
    end

    // Timeout de seguranca
    initial begin
        #10000;
        $display("[tb] TIMEOUT");
        $finish;
    end

endmodule
