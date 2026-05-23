// Testbench de validacao da User Story 1:
//   compression_unit grava corretamente os L bits da chave comprimida
//   nos enderecos 0..L-1 da Porta A da dual_port_ram.
//
// Parametros do DUT (configurados via localparam):
//   W = 16  (largura da chave — equivale a N nos vetores de referencia)
//   L = 8   (bits de saida — use os mesmos valores usados em gen_pipeline_vectors.py)
//   P = L   (parallelismo = L para uma unica rodada COMPUTE+WRITE)
//
// Vetores de entrada carregados de arquivos gerados por gen_pipeline_vectors.py:
//   key_hex.hex        -- 1 bit por linha (16 linhas = 16 bits)
//   matrix_window.hex  -- 1 bit por linha (23 linhas = N+L-1 bits)
//
// Saida gerada em sim/output_dump.hex (1 bit por linha, L linhas).
// Validacao: comparar output_dump.hex com expected_ram.hex usando
//   python3 ../../high_level_simulation/validate_pipeline_dump.py
//
// Execucao (a partir de src/tb_pipeline/):
//   vlib work
//   vlog tb_compression_ram.v ../compression_unit.v ../hash_engine.v \
//        ../dual_port_ram/dual_port_ram.v
//   vsim -L altera_mf_ver work.tb_compression_ram -do "run -all; quit"

`timescale 1ns/1ps

module tb_compression_ram;

    // -----------------------------------------------------------------------
    // Parametros — devem coincidir com gen_pipeline_vectors.py
    // -----------------------------------------------------------------------
    localparam W    = 16;   // largura da chave
    localparam L    = 8;    // bits de saida (L deve ser multiplo de P)
    localparam P    = 8;    // paralelismo do compression_unit (P = L para 1 rodada)
    localparam ADDRW = 17;  // bits de endereco da RAM

    // -----------------------------------------------------------------------
    // DUT — sinais
    // -----------------------------------------------------------------------
    reg              clock;
    reg              reset;
    reg              start;

    // Dados (carregados do arquivo via $readmemh bit a bit)
    reg [W-1:0]      key;
    reg [W+L-2:0]    matrix_window;

    wire [ADDRW-1:0] wr_addr;
    wire             wr_data;
    wire             wr_enable;
    wire             compunit_busy;
    wire             compunit_done;
    wire [P-1:0]     hash_out_dbg;

    // Saida da RAM Porta B (para leitura de verificacao)
    wire             ram_q;
    reg  [ADDRW-1:0] rd_addr;
    reg              rd_enable;

    // -----------------------------------------------------------------------
    // Instancias
    // -----------------------------------------------------------------------
    compression_unit #(
        .P(P),
        .W(W),
        .L(L)
    ) u_cu (
        .clock         (clock),
        .reset         (reset),
        .key           (key),
        .matrix_window (matrix_window),
        .start         (start),
        .wr_addr       (wr_addr),
        .wr_data       (wr_data),
        .wr_enable     (wr_enable),
        .compunit_busy (compunit_busy),
        .compunit_done (compunit_done),
        .hash_out      (hash_out_dbg)
    );

    dual_port_ram #(
        .DEPTH(100000),
        .ADDRW(ADDRW)
    ) u_ram (
        .clock     (clock),
        .data_a    (wr_data),
        .wr_addr   (wr_addr),
        .wr_enable (wr_enable),
        .rd_addr   (rd_addr),
        .rd_enable (rd_enable),
        .q         (ram_q)
    );

    // -----------------------------------------------------------------------
    // Auxiliares
    // -----------------------------------------------------------------------
    // Buffer para carregar bits do arquivo 1 linha por vez
    reg [W+L-1:0]  key_bits_raw   [0:W-1];    // W linhas de 1 bit cada
    reg [W+L-1:0]  mw_bits_raw    [0:W+L-2];  // W+L-1 linhas de 1 bit cada

    // Shadow array para dump determinístico
    reg [0:0] shadow [0:L-1];
    integer   i;

    // -----------------------------------------------------------------------
    // Clock: 10 ns de periodo (100 MHz)
    // -----------------------------------------------------------------------
    initial clock = 1'b0;
    always  #5 clock = ~clock;

    // -----------------------------------------------------------------------
    // Sequenciamento principal
    // -----------------------------------------------------------------------
    initial begin
        // Inicializa shadow
        for (i = 0; i < L; i = i + 1) shadow[i] = 1'b0;

        // Reset
        reset  = 1'b1;
        start  = 1'b0;
        rd_addr   = 0;
        rd_enable = 1'b0;
        key            = 0;
        matrix_window  = 0;
        @(posedge clock);
        @(posedge clock);
        reset = 1'b0;
        @(posedge clock);

        // Carrega key (1 bit por linha do arquivo hex)
        $readmemh("key_hex.hex", key_bits_raw);
        for (i = 0; i < W; i = i + 1)
            key[i] = key_bits_raw[i][0];

        // Carrega matrix_window (1 bit por linha)
        $readmemh("matrix_window.hex", mw_bits_raw);
        for (i = 0; i < W + L - 1; i = i + 1)
            matrix_window[i] = mw_bits_raw[i][0];

        $display("[tb] key = %h", key);
        $display("[tb] matrix_window[%0d:0] loaded", W+L-2);

        // Dispara compressao
        start = 1'b1;
        @(posedge clock);
        start = 1'b0;

        // Aguarda compunit_done
        wait (compunit_done == 1'b1);
        @(posedge clock);  // extra para garantir ultimo wr_enable propagado

        $display("[tb] compunit_done = 1, iniciando leitura da RAM");

        // Le os L bits da Porta B e captura no shadow
        rd_enable = 1'b1;
        for (i = 0; i < L; i = i + 1) begin
            rd_addr = i[ADDRW-1:0];
            @(posedge clock);           // aplica rd_addr
            @(posedge clock);           // latencia 1 ciclo (outdata_reg_b = CLOCK0)
            shadow[i] = ram_q;
            $display("[tb] addr=%0d  bit=%b", i, ram_q);
        end
        rd_enable = 1'b0;

        // Dump para arquivo
        $writememh("sim/output_dump.hex", shadow);
        $display("[tb] escreveu sim/output_dump.hex");

        // Acceptance scenario 3: zero-input sanity check (exibir apenas)
        $display("[tb] hash_out_dbg (ultimo valor computado) = %b", hash_out_dbg);

        $finish;
    end

    // Timeout
    initial begin
        #500000;
        $display("[tb] TIMEOUT");
        $finish;
    end

endmodule
