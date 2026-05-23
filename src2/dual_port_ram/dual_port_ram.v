// RAM dual-port para o pipeline de privacy amplification.
//
// Especificacao (FR-001):
//   - 100 000 palavras de 1 bit (enderecos 0 .. 99999)
//   - Enderecamento com 17 bits (2^17 = 131072 >= 100000)
//   - Porta A: escrita exclusiva pelo compression_unit
//   - Porta B: leitura arbitrada pelo multiplex_ram
//   - Leitura sincrona na Porta B: 1 ciclo de latencia apos rden_b asserted
//
// Sintese: Quartus Prime Lite 18.1, FPGA Cyclone IV EP4CE115F29C7 (DE2-115)
//   Esperado: ~12 blocos M9K (100000 bits / 9216 bits por M9K)
//
// Simulacao ModelSim/Questa Altera: requer flag -L altera_mf_ver

module dual_port_ram #(
    parameter DEPTH   = 100000, // Numero de palavras (L bits)
    parameter ADDRW   = 17      // Bits de endereco (2^17 = 131072 >= 100000)
)(
    input  wire              clock,

    // Porta A — escrita pelo compression_unit
    input  wire [0:0]        data_a,       // dado a escrever (1 bit)
    input  wire [ADDRW-1:0]  wr_addr,      // endereco de escrita
    input  wire              wr_enable,    // habilitacao de escrita

    // Porta B — leitura arbitrada pelo multiplex_ram
    input  wire [ADDRW-1:0]  rd_addr,      // endereco de leitura
    input  wire              rd_enable,    // habilitacao de leitura
    output wire              q             // dado lido (1 bit, latencia 1 ciclo)
);

    altsyncram #(
        // Modo dual-port verdadeiro
        .operation_mode             ("BIDIR_DUAL_PORT"),

        // Porta A (escrita)
        .width_a                    (1),
        .widthad_a                  (ADDRW),
        .numwords_a                 (DEPTH),
        .outdata_reg_a              ("UNREGISTERED"),
        .address_aclr_a             ("NONE"),
        .indata_aclr_a              ("NONE"),
        .wrcontrol_aclr_a           ("NONE"),
        .byteena_aclr_a             ("NONE"),
        .outdata_aclr_a             ("NONE"),
        .clock_enable_input_a       ("BYPASS"),
        .clock_enable_output_a      ("BYPASS"),
        .read_during_write_mode_port_a ("NEW_DATA_NO_NBE_READ"),

        // Porta B (leitura)
        .width_b                    (1),
        .widthad_b                  (ADDRW),
        .numwords_b                 (DEPTH),
        .outdata_reg_b              ("CLOCK0"),  // latencia 1 ciclo na Porta B
        .address_aclr_b             ("NONE"),
        .outdata_aclr_b             ("NONE"),
        .rdcontrol_aclr_b           ("NONE"),
        .clock_enable_input_b       ("BYPASS"),
        .clock_enable_output_b      ("BYPASS"),
        .read_during_write_mode_mixed_ports ("DONT_CARE"),

        // Geral
        .lpm_type                   ("altsyncram"),
        .power_up_uninitialized     ("FALSE"),
        .intended_device_family     ("Cyclone IV E")
    ) u_ram (
        // Porta A
        .clock0      (clock),
        .address_a   (wr_addr),
        .data_a      (data_a),
        .wren_a      (wr_enable),
        .rden_a      (1'b0),      // Porta A e write-only neste design
        .q_a         (),

        // Porta B
        .clock1      (clock),
        .address_b   (rd_addr),
        .rden_b      (rd_enable),
        .wren_b      (1'b0),      // Porta B e read-only neste design
        .data_b      (1'b0),
        .q_b         (q),

        // Sinais opcionais tied-off
        .aclr0            (1'b0),
        .aclr1            (1'b0),
        .addressstall_a   (1'b0),
        .addressstall_b   (1'b0),
        .byteena_a        (1'b1),
        .byteena_b        (1'b1),
        .clocken0         (1'b1),
        .clocken1         (1'b1),
        .clocken2         (1'b1),
        .clocken3         (1'b1),
        .eccstatus        ()
    );

endmodule
