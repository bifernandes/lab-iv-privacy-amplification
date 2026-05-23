// Testbench de integracao end-to-end do pipeline de privacy amplification.
//
// Exercita o fluxo completo:
//   key + matrix_window -> compression_unit -> dual_port_ram
//                                          -> multiplex_ram -> output_interface
//                                                          -> chave secreta bit a bit
//
// Verifica (de forma basica sem checar conteudo semantico):
//   1. compunit_done asserta apos compressao
//   2. oi_busy asserta apos compunit_done
//   3. key_secret_valid pulsa L vezes em sequencia
//   4. oi_done asserta ao final
//   5. oi_error nunca asserta para enderecos validos
//
// Parametros pequenos para simulacao rapida.
//
// Execucao (a partir de src/tb_pipeline/):
//   vlib work
//   vlog ../hash_engine.v ../compression_unit.v ../dual_port_ram/dual_port_ram.v \
//        ../multiplex_ram.v ../output_interface.v ../top.v tb_top_pipeline.v
//   vsim -L altera_mf_ver work.tb_top_pipeline -do "run -all; quit"

`timescale 1ns/1ps

module tb_top_pipeline;

    // Sinais da interface de top.v
    reg  clock;
    reg  rst_fpga;   // ativo em baixo
    reg  cu_start;   // ativo em baixo
    reg  [7:0] key_in;

    wire LED_cu_busy;
    wire LED_cu_done;
    wire LED_oi_busy;
    wire LED_oi_done;
    wire LED_oi_error;
    wire LED_key_bit;
    wire LED_key_valid;

    // Instancia do DUT (top.v)
    top u_top (
        .clk_fpga      (clock),
        .rst_fpga      (rst_fpga),
        .cu_start      (cu_start),
        .key_in        (key_in),
        .LED_cu_busy   (LED_cu_busy),
        .LED_cu_done   (LED_cu_done),
        .LED_oi_busy   (LED_oi_busy),
        .LED_oi_done   (LED_oi_done),
        .LED_oi_error  (LED_oi_error),
        .LED_key_bit   (LED_key_bit),
        .LED_key_valid (LED_key_valid)
    );

    // Clock 10 ns (100 MHz)
    initial clock = 1'b0;
    always  #5 clock = ~clock;

    // Auxiliares de verificacao
    integer pass_count;
    integer fail_count;
    integer bit_count;

    task assert_cond;
        input        cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  PASS [%s]", msg);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL [%s]", msg);
                fail_count = fail_count + 1;
            end
        end
    endtask

    integer timeout_cnt;

    initial begin
        pass_count = 0;
        fail_count = 0;
        bit_count  = 0;

        // Reset (KEY[0] ativo em baixo: rst_fpga=0 = reset)
        rst_fpga = 1'b0;
        cu_start = 1'b1;  // nao pressionar KEY[1]
        key_in   = 8'hA5;
        @(posedge clock);
        @(posedge clock);
        @(posedge clock);
        rst_fpga = 1'b1;  // libera reset
        @(posedge clock);

        // -------------------------------------------------------------------
        // 1. Dispara compressao (KEY[1] pressionado = cu_start = 0)
        // -------------------------------------------------------------------
        $display("\n--- Etapa 1: Iniciando compressao ---");
        cu_start = 1'b0;  // pressionar
        @(posedge clock);
        cu_start = 1'b1;  // soltar

        // Aguarda compunit_done
        timeout_cnt = 0;
        while (!LED_cu_done && timeout_cnt < 1000) begin
            @(posedge clock);
            timeout_cnt = timeout_cnt + 1;
        end
        assert_cond(LED_cu_done, "CU_DONE_ASSERTED");
        assert_cond(!LED_cu_busy, "CU_BUSY_DEASSERTED");

        // -------------------------------------------------------------------
        // 2. Verifica que output_interface inicia apos compunit_done
        // -------------------------------------------------------------------
        $display("\n--- Etapa 2: Output Interface ---");
        @(posedge clock);
        @(posedge clock);
        assert_cond(LED_oi_busy, "OI_BUSY_AFTER_CU_DONE");

        // -------------------------------------------------------------------
        // 3. Conta pulsos de key_secret_valid (deve ser exatamente L=8)
        // -------------------------------------------------------------------
        $display("\n--- Etapa 3: Contando bits validos ---");
        timeout_cnt = 0;
        bit_count   = 0;
        while (!LED_oi_done && timeout_cnt < 10000) begin
            @(posedge clock);
            if (LED_key_valid) begin
                bit_count = bit_count + 1;
                $display("  bit[%0d] = %b", bit_count - 1, LED_key_bit);
            end
            timeout_cnt = timeout_cnt + 1;
        end
        // Aguarda mais 1 ciclo para done estabilizar
        @(posedge clock);
        assert_cond(bit_count == 8, "CORRECT_BIT_COUNT"); // L=8

        // -------------------------------------------------------------------
        // 4. Verifica oi_done e ausencia de erro
        // -------------------------------------------------------------------
        $display("\n--- Etapa 4: Verificacao final ---");
        assert_cond(LED_oi_done,   "OI_DONE");
        assert_cond(!LED_oi_busy,  "OI_NOT_BUSY");
        assert_cond(!LED_oi_error, "NO_ERROR");

        // -------------------------------------------------------------------
        // Resultado
        // -------------------------------------------------------------------
        $display("\n========================================");
        if (fail_count == 0) begin
            $display("PASS: integracao end-to-end OK (%0d/%0d verificacoes)",
                     pass_count, pass_count + fail_count);
        end else begin
            $display("FAIL: %0d divergencias em %0d verificacoes",
                     fail_count, pass_count + fail_count);
        end
        $display("========================================\n");
        $finish;
    end

    initial begin
        #2000000;
        $display("[tb_top] TIMEOUT GLOBAL");
        $finish;
    end

endmodule
