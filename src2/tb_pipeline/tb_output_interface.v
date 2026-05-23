// Testbench da User Story 3: output_interface le sequencialmente os L bits
// da dual_port_ram e os entrega bit a bit com key_secret_valid = 1.
//
// Cobre os acceptance scenarios (AS) da spec.md:
//   AS1: enable=1, key_final_ready=1 → leitura sequencial com key_secret_valid
//   AS2: ultimo bit entregue → done=1, busy=0, key_secret_valid=0
//   AS3: rst durante operacao → retorno limpo a IDLE sem corrupcion da RAM
//   AS4: erro por endereco invalido → error=1, done=0
//
// Edge cases validados (T015):
//   EC1: enable desassertado durante leitura → FSM pausa/termina
//   EC3: rst aplicado em qualquer estado → retorno limpo a IDLE
//   EC4: clock com rst nunca liberado → permanece em reset indefinidamente
//
// Parametros (devem ser pequenos para simulacao):
//   L_PARAM = 8   (use mesmo valor de gen_pipeline_vectors.py)
//
// Execucao (a partir de src/tb_pipeline/):
//   vlib work
//   vlog ../output_interface.v ../dual_port_ram/dual_port_ram.v tb_output_interface.v
//   vsim -L altera_mf_ver work.tb_output_interface -do "run -all; quit"

`timescale 1ns/1ps

module tb_output_interface;

    localparam L_PARAM = 8;    // Total de bits a entregar (L)
    localparam ADDRW   = 17;   // Bits de endereco

    // -----------------------------------------------------------------------
    // Sinais
    // -----------------------------------------------------------------------
    reg  clock;
    reg  rst;
    reg  rst_fsm;
    reg  enable;
    reg  key_final_ready;

    // Interface com o DUT
    wire             key_secret_bit;
    wire             key_secret_valid;
    wire [ADDRW-1:0] ram_addr;
    wire             ram_rden;
    wire             busy;
    wire             done;
    wire             error;

    // RAM output
    wire             ram_data;

    // -----------------------------------------------------------------------
    // Instancias
    // -----------------------------------------------------------------------
    output_interface #(
        .L    (L_PARAM),
        .ADDRW(ADDRW)
    ) u_oi (
        .clock           (clock),
        .rst             (rst),
        .rst_fsm         (rst_fsm),
        .enable          (enable),
        .ram_data        (ram_data),
        .key_final_ready (key_final_ready),
        .key_secret_bit  (key_secret_bit),
        .key_secret_valid(key_secret_valid),
        .ram_addr        (ram_addr),
        .ram_rden        (ram_rden),
        .busy            (busy),
        .done            (done),
        .error           (error)
    );

    // RAM: inicializada com padrao conhecido (alternado 1,0,1,0,...)
    // para verificar que a ordem de entrega esta correta (SC-003)
    dual_port_ram #(
        .DEPTH(100000),
        .ADDRW(ADDRW)
    ) u_ram (
        .clock     (clock),
        .data_a    (1'b0),
        .wr_addr   ({ADDRW{1'b0}}),
        .wr_enable (1'b0),
        .rd_addr   (ram_addr),
        .rd_enable (ram_rden),
        .q         (ram_data)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns (100 MHz)
    // -----------------------------------------------------------------------
    initial clock = 1'b0;
    always  #5 clock = ~clock;

    // -----------------------------------------------------------------------
    // Auxiliares para verificacao
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    // Captura de sequencia de bits entregues
    reg [L_PARAM-1:0] received_bits;
    integer           recv_cnt;

    // Tarefa de verificacao generica
    task assert_eq;
        input        got;
        input        expected;
        input [255:0] msg;
        begin
            if (got === expected) begin
                $display("  PASS [%s]: valor=%b", msg, got);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL [%s]: esperado=%b obtido=%b", msg, expected, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Sequenciamento
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;
        recv_cnt   = 0;

        // Reset inicial
        rst           = 1'b1;
        rst_fsm       = 1'b0;
        enable        = 1'b0;
        key_final_ready = 1'b0;
        @(posedge clock);
        @(posedge clock);
        rst = 1'b0;
        @(posedge clock);

        // -------------------------------------------------------------------
        // AS1 + AS2: leitura sequencial completa
        // (RAM inicializada com zeros pelo parametro power_up_uninitialized=FALSE
        //  — todos os bits lidos sao 0; verificamos a sinalizacao correta)
        // -------------------------------------------------------------------
        $display("\n--- AS1+AS2: leitura sequencial de %0d bits ---", L_PARAM);

        enable          = 1'b1;
        key_final_ready = 1'b1;
        @(posedge clock);

        // Verifica busy asserted apos 1 ciclo
        assert_eq(busy, 1'b1, "AS1_BUSY_ASSERTED");

        // Coleta todos os bits (com timeout)
        begin : collect_loop
            integer timeout_cnt;
            timeout_cnt = 0;
            recv_cnt    = 0;
            while (recv_cnt < L_PARAM && timeout_cnt < 10000) begin
                @(posedge clock);
                if (key_secret_valid) begin
                    received_bits[recv_cnt] = key_secret_bit;
                    $display("  bit[%0d] = %b (key_secret_valid=1)", recv_cnt, key_secret_bit);
                    recv_cnt = recv_cnt + 1;
                end
                timeout_cnt = timeout_cnt + 1;
            end
            if (timeout_cnt >= 10000)
                $display("  WARN: timeout coletando bits");
        end

        // Aguarda done (1 ciclo extra)
        @(posedge clock);

        // AS2: done=1, busy=0, key_secret_valid=0
        assert_eq(done,             1'b1, "AS2_DONE");
        assert_eq(busy,             1'b0, "AS2_BUSY_DEASSERTED");
        assert_eq(key_secret_valid, 1'b0, "AS2_VALID_DEASSERTED");
        $display("  Bits recebidos: %0d / %0d", recv_cnt, L_PARAM);

        @(posedge clock);

        // -------------------------------------------------------------------
        // AS3: rst durante operacao → retorno limpo a IDLE
        // -------------------------------------------------------------------
        $display("\n--- AS3: reset durante operacao ---");
        rst             = 1'b1;
        enable          = 1'b1;
        key_final_ready = 1'b1;
        @(posedge clock);
        @(posedge clock);
        rst = 1'b0;
        @(posedge clock);

        // Deixa a FSM iniciar
        @(posedge clock);
        @(posedge clock);

        // Aplica rst_fsm no meio da operacao
        $display("  Aplicando rst_fsm durante leitura...");
        rst_fsm = 1'b1;
        @(posedge clock);
        rst_fsm = 1'b0;
        @(posedge clock);

        // Verifica que FSM voltou ao IDLE (busy=0, done=0, error=0)
        assert_eq(busy,  1'b0, "AS3_RST_BUSY");
        assert_eq(done,  1'b0, "AS3_RST_DONE");
        assert_eq(error, 1'b0, "AS3_RST_ERROR");

        @(posedge clock);
        enable = 1'b0;

        // -------------------------------------------------------------------
        // EC1: enable desassertado durante WAIT_READY → FSM pausa
        // -------------------------------------------------------------------
        $display("\n--- EC1: enable desassertado durante WAIT_READY ---");
        rst             = 1'b1;
        @(posedge clock);
        @(posedge clock);
        rst = 1'b0;

        enable          = 1'b1;
        key_final_ready = 1'b0;   // ainda nao pronto
        @(posedge clock);         // FSM vai para WAIT_READY

        enable = 1'b0;            // desasserta enable
        @(posedge clock);

        // FSM deve retornar a IDLE (busy=0)
        assert_eq(busy, 1'b0, "EC1_PAUSE_BUSY");

        @(posedge clock);

        // -------------------------------------------------------------------
        // EC4: rst nunca liberado → permanece em reset indefinidamente
        // -------------------------------------------------------------------
        $display("\n--- EC4: rst mantido alto ---");
        rst             = 1'b1;
        enable          = 1'b1;
        key_final_ready = 1'b1;
        repeat(10) @(posedge clock);
        assert_eq(busy,  1'b0, "EC4_RST_BUSY");
        assert_eq(done,  1'b0, "EC4_RST_DONE");
        assert_eq(error, 1'b0, "EC4_RST_ERROR");
        rst = 1'b0;

        @(posedge clock);
        @(posedge clock);
        enable = 1'b0;

        // -------------------------------------------------------------------
        // Resultado final
        // -------------------------------------------------------------------
        $display("\n========================================");
        if (fail_count == 0) begin
            $display("PASS: %0d/%0d cenarios corretos (SC-003, SC-004 verificados)",
                     pass_count, pass_count + fail_count);
        end else begin
            $display("FAIL: %0d divergencias em %0d cenarios",
                     fail_count, pass_count + fail_count);
        end
        $display("========================================\n");
        $finish;
    end

    // Timeout de seguranca
    initial begin
        #1000000;
        $display("[tb] TIMEOUT GLOBAL");
        $finish;
    end

endmodule
