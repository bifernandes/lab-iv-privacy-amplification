// ROM single-port baseada em altsyncram, inicializada via input_vectors.mif.
// Largura 23 bits = {matrix_window[14:0], key[7:0]}. Profundidade 16.
//
// outdata_reg_a = "UNREGISTERED" -> latencia de leitura = 1 ciclo (registrador
// de endereco interno apenas). Mantem o pipeline previsivel para o testbench.
//
// Para simulacao no ModelSim/Questa Altera execute com -L altera_mf_ver para
// que a biblioteca seja resolvida.

module input_rom (
    input  wire        clock,
    input  wire [3:0]  address,
    output wire [22:0] q
);

    altsyncram #(
        .operation_mode        ("ROM"),
        .width_a               (23),
        .widthad_a             (4),
        .numwords_a            (16),
        .lpm_type              ("altsyncram"),
        .init_file             ("input_vectors.mif"),
        .address_aclr_a        ("NONE"),
        .outdata_aclr_a        ("NONE"),
        .outdata_reg_a         ("UNREGISTERED"),
        .clock_enable_input_a  ("BYPASS"),
        .clock_enable_output_a ("BYPASS"),
        .intended_device_family("Cyclone IV E")
    ) u_rom (
        .clock0     (clock),
        .address_a  (address),
        .q_a        (q),
        // Tied-off ports
        .aclr0      (1'b0),
        .aclr1      (1'b0),
        .address_b  (1'b1),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a  (1'b1),
        .byteena_b  (1'b1),
        .clock1     (1'b1),
        .clocken0   (1'b1),
        .clocken1   (1'b1),
        .clocken2   (1'b1),
        .clocken3   (1'b1),
        .data_a     ({23{1'b1}}),
        .data_b     (1'b1),
        .eccstatus  (),
        .q_b        (),
        .rden_a     (1'b1),
        .rden_b     (1'b1),
        .wren_a     (1'b0),
        .wren_b     (1'b0)
    );

endmodule
