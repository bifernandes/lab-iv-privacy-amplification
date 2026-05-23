// Top sintetizavel — Pipeline de Privacy Amplification (branch 001-ram-output-interface)
//
// Integra os modulos do pipeline completo:
//   compression_unit -> dual_port_ram <- multiplex_ram <- output_interface
//
// Pinout DE2-115 (Cyclone IV EP4CE115F29C7):
//   clk_fpga        <- CLOCK_50 (50 MHz)
//   rst_fpga        <- KEY[0]   (ativo em baixo: pressionar = reset)
//   cu_start        <- KEY[1]   (inicia compressao)
//   key_in[7:0]     <- SW[7:0]  (bits de chave para teste — vetor W=8)
//   LED_cu_busy     -> LEDR[0]
//   LED_cu_done     -> LEDR[1]
//   LED_oi_busy     -> LEDR[2]
//   LED_oi_done     -> LEDR[3]
//   LED_oi_error    -> LEDR[4]
//   key_secret_bit  -> LEDR[8]
//   key_secret_valid-> LEDR[9]
//
// Para a DE2-115, os sinais key_in e matrix_window_in precisarao ser ligados
// ao Input Buffer e Seed Generator reais (fora do escopo desta feature).
// Neste top, eles sao alimentados por registros internos (demo/debug).
//
// Parametros do pipeline (reducao de tamanho para coube no pinout disponivel):
//   W = 8   (largura da chave para demonstracao)
//   L = 8   (bits de saida = P para 1 rodada)
//   P = 8   (paralelismo do compression_unit)
//
// Para producao (N=10^6, L=10^5), alterar W e L e conectar ao input_buffer
// e seed_generator externos.

module top (
    input  wire        clk_fpga,
    input  wire        rst_fpga,    // KEY[0] ativo em baixo
    input  wire        cu_start,    // KEY[1] ativo em baixo
    input  wire [7:0]  key_in,      // SW[7:0]
    output wire        LED_cu_busy,
    output wire        LED_cu_done,
    output wire        LED_oi_busy,
    output wire        LED_oi_done,
    output wire        LED_oi_error,
    output wire        LED_key_bit,
    output wire        LED_key_valid
);

    // -----------------------------------------------------------------------
    // Parametros do pipeline (ajustar para producao)
    // -----------------------------------------------------------------------
    localparam W     = 8;     // largura da chave
    localparam P     = 8;     // paralelismo do compression_unit
    localparam L     = 8;     // bits de saida (L = P para demo de 1 rodada)
    localparam ADDRW = 17;    // bits de endereco da RAM

    // -----------------------------------------------------------------------
    // Clock e Reset
    // -----------------------------------------------------------------------
    wire clock = clk_fpga;
    wire reset = ~rst_fpga;      // KEY[0]: pressionar = reset (ativo em baixo)
    wire start = ~cu_start;      // KEY[1]: pressionar = inicia compressao

    // -----------------------------------------------------------------------
    // Matrix Window (para demo: vetor constante definido em sintese)
    // Em producao: conectar ao seed_generator
    // W + L - 1 = 15 bits
    // -----------------------------------------------------------------------
    localparam MW_BITS = W + L - 1; // 15
    wire [MW_BITS-1:0] matrix_window = 15'b101_1001_0011_0101; // valor de teste

    // -----------------------------------------------------------------------
    // compression_unit
    // -----------------------------------------------------------------------
    wire [ADDRW-1:0] cu_wr_addr;
    wire             cu_wr_data;
    wire             cu_wr_enable;
    wire             compunit_busy;
    wire             compunit_done;
    wire [P-1:0]     hash_out_dbg;

    compression_unit #(
        .P(P),
        .W(W),
        .L(L)
    ) u_cu (
        .clock         (clock),
        .reset         (reset),
        .key           (key_in),
        .matrix_window (matrix_window),
        .start         (start),
        .wr_addr       (cu_wr_addr),
        .wr_data       (cu_wr_data),
        .wr_enable     (cu_wr_enable),
        .compunit_busy (compunit_busy),
        .compunit_done (compunit_done),
        .hash_out      (hash_out_dbg)
    );

    // -----------------------------------------------------------------------
    // output_interface
    // -----------------------------------------------------------------------
    wire [ADDRW-1:0] oi_rd_addr;
    wire             oi_rd_rden;
    wire             key_secret_bit;
    wire             key_secret_valid;
    wire             oi_busy;
    wire             oi_done;
    wire             oi_error;

    // enable do output_interface: ativa automaticamente apos compunit_done
    wire oi_enable = compunit_done;

    output_interface #(
        .L    (L),
        .ADDRW(ADDRW)
    ) u_oi (
        .clock           (clock),
        .rst             (reset),
        .rst_fsm         (1'b0),
        .enable          (oi_enable),
        .ram_data        (ram_q),
        .key_final_ready (compunit_done),
        .key_secret_bit  (key_secret_bit),
        .key_secret_valid(key_secret_valid),
        .ram_addr        (oi_rd_addr),
        .ram_rden        (oi_rd_rden),
        .busy            (oi_busy),
        .done            (oi_done),
        .error           (oi_error)
    );

    // -----------------------------------------------------------------------
    // multiplex_ram — arbitra acesso de leitura a Porta B
    // -----------------------------------------------------------------------
    wire [ADDRW-1:0] mux_rd_addr;
    wire             mux_rd_rden;

    multiplex_ram u_mux (
        .compunit_addr     (cu_wr_addr),    // CU usa mesmo barramento de endereco
        .compunit_rden     (cu_wr_enable),  // (CU le Porta B apenas para verificacao)
        .compunit_done     (compunit_done),
        .compunit_busy     (compunit_busy),
        .outinterface_addr (oi_rd_addr),
        .outinterface_rden (oi_rd_rden),
        .rd_ram_addr       (mux_rd_addr),
        .rd_ram_rden       (mux_rd_rden)
    );

    // -----------------------------------------------------------------------
    // dual_port_ram — 100000 x 1 bit
    // -----------------------------------------------------------------------
    wire ram_q;

    dual_port_ram #(
        .DEPTH(100000),
        .ADDRW(ADDRW)
    ) u_ram (
        .clock     (clock),
        // Porta A (escrita pelo compression_unit)
        .data_a    (cu_wr_data),
        .wr_addr   (cu_wr_addr),
        .wr_enable (cu_wr_enable),
        // Porta B (leitura arbitrada pelo multiplex_ram)
        .rd_addr   (mux_rd_addr),
        .rd_enable (mux_rd_rden),
        .q         (ram_q)
    );

    // -----------------------------------------------------------------------
    // Mapeamento de LEDs
    // -----------------------------------------------------------------------
    assign LED_cu_busy  = compunit_busy;
    assign LED_cu_done  = compunit_done;
    assign LED_oi_busy  = oi_busy;
    assign LED_oi_done  = oi_done;
    assign LED_oi_error = oi_error;
    assign LED_key_bit  = key_secret_bit;
    assign LED_key_valid= key_secret_valid;

endmodule
