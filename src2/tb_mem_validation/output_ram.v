// RAM single-port baseada em altsyncram, captura hash_out (8 bits) por endereco.
// Profundidade 16, controlada por wren externo.
//
// outdata_reg_a = "UNREGISTERED" -> latencia de leitura 1 ciclo.
// O testbench tambem mantem um shadow array para um dump robusto via
// $writememh independente da implementacao interna do IP.

module output_ram (
    input  wire       clock,
    input  wire [3:0] address,
    input  wire [7:0] data,
    input  wire       wren,
    output wire [7:0] q
);

    altsyncram #(
        .operation_mode        ("SINGLE_PORT"),
        .width_a               (8),
        .widthad_a             (4),
        .numwords_a            (16),
        .lpm_type              ("altsyncram"),
        .lpm_hint              ("ENABLE_RUNTIME_MOD=YES, INSTANCE_NAME=ORAM"),
        .address_aclr_a        ("NONE"),
        .outdata_aclr_a        ("NONE"),
        .outdata_reg_a         ("UNREGISTERED"),
        .indata_aclr_a         ("NONE"),
        .wrcontrol_aclr_a      ("NONE"),
        .byteena_aclr_a        ("NONE"),
        .clock_enable_input_a  ("BYPASS"),
        .clock_enable_output_a ("BYPASS"),
        .power_up_uninitialized("FALSE"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
        .intended_device_family("Cyclone IV E")
    ) u_ram (
        .clock0       (clock),
        .address_a    (address),
        .data_a       (data),
        .wren_a       (wren),
        .q_a          (q),
        // Tied-off ports
        .aclr0        (1'b0),
        .aclr1        (1'b0),
        .address_b    (1'b1),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a    (1'b1),
        .byteena_b    (1'b1),
        .clock1       (1'b1),
        .clocken0     (1'b1),
        .clocken1     (1'b1),
        .clocken2     (1'b1),
        .clocken3     (1'b1),
        .data_b       (1'b1),
        .eccstatus    (),
        .q_b          (),
        .rden_a       (1'b1),
        .rden_b       (1'b1),
        .wren_b       (1'b0)
    );

endmodule
