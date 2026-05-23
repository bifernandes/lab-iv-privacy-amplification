// Testbench da User Story 2: multiplex_ram arbitra corretamente o acesso
// de leitura a Porta B da RAM entre compression_unit e output_interface.
//
// Cobre os tres acceptance scenarios (AS) da spec.md:
//   AS1: compunit_busy=1 + outinterface_rden=1 → compunit vence
//   AS2: compunit_busy=0, compunit_done=0, outinterface_rden=1 → outinterface vence
//   AS3: compunit_done=1, outinterface_rden=1 → outinterface vence
//
// Execucao (a partir de src/tb_pipeline/):
//   vlib work
//   vlog ../multiplex_ram.v tb_multiplex_ram.v
//   vsim work.tb_multiplex_ram -do "run -all; quit"
//   (nao requer -L altera_mf_ver pois nao instancia IP)

`timescale 1ns/1ps

module tb_multiplex_ram;

    // Entradas (estimulos)
    reg [16:0] compunit_addr;
    reg        compunit_rden;
    reg        compunit_done;
    reg        compunit_busy;
    reg [16:0] outinterface_addr;
    reg        outinterface_rden;

    // Saidas do DUT
    wire [16:0] rd_ram_addr;
    wire        rd_ram_rden;

    // Instancia do DUT
    multiplex_ram u_mux (
        .compunit_addr    (compunit_addr),
        .compunit_rden    (compunit_rden),
        .compunit_done    (compunit_done),
        .compunit_busy    (compunit_busy),
        .outinterface_addr(outinterface_addr),
        .outinterface_rden(outinterface_rden),
        .rd_ram_addr      (rd_ram_addr),
        .rd_ram_rden      (rd_ram_rden)
    );

    // Monitor ciclo a ciclo
    initial begin
        $monitor("[%0t] busy=%b done=%b | cu_addr=%0d cu_rden=%b | oi_addr=%0d oi_rden=%b || rd_addr=%0d rd_rden=%b",
                 $time,
                 compunit_busy, compunit_done,
                 compunit_addr, compunit_rden,
                 outinterface_addr, outinterface_rden,
                 rd_ram_addr, rd_ram_rden);
    end

    integer pass_count;
    integer fail_count;

    task check;
        input [16:0] exp_addr;
        input        exp_rden;
        input [255:0] scenario;
        begin
            #1; // pequeno delay para logica combinacional estabilizar
            if (rd_ram_addr === exp_addr && rd_ram_rden === exp_rden) begin
                $display("  PASS [%s]: rd_addr=%0d rd_rden=%b", scenario, rd_ram_addr, rd_ram_rden);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL [%s]: esperado addr=%0d rden=%b, obtido addr=%0d rden=%b",
                         scenario, exp_addr, exp_rden, rd_ram_addr, rd_ram_rden);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        pass_count = 0;
        fail_count = 0;

        // Valores iniciais
        compunit_addr     = 17'd1000;
        compunit_rden     = 1'b1;
        compunit_done     = 1'b0;
        compunit_busy     = 1'b0;
        outinterface_addr = 17'd2000;
        outinterface_rden = 1'b0;

        #10;

        // ---------------------------------------------------------------
        // AS1: compunit_busy=1 + outinterface_rden=1 → compunit vence
        // ---------------------------------------------------------------
        $display("\n--- AS1: compunit_busy=1 + outinterface_rden=1 ---");
        compunit_busy     = 1'b1;
        compunit_done     = 1'b0;
        compunit_addr     = 17'd1234;
        compunit_rden     = 1'b1;
        outinterface_addr = 17'd5678;
        outinterface_rden = 1'b1;
        check(17'd1234, 1'b1, "AS1");

        #10;

        // ---------------------------------------------------------------
        // AS2: compunit_busy=0, compunit_done=0, outinterface_rden=1
        //      → outinterface vence
        // ---------------------------------------------------------------
        $display("\n--- AS2: compunit_busy=0, compunit_done=0, outinterface_rden=1 ---");
        compunit_busy     = 1'b0;
        compunit_done     = 1'b0;
        compunit_addr     = 17'd1234;
        compunit_rden     = 1'b0;
        outinterface_addr = 17'd5678;
        outinterface_rden = 1'b1;
        check(17'd5678, 1'b1, "AS2");

        #10;

        // ---------------------------------------------------------------
        // AS3: compunit_done=1, outinterface_rden=1 → outinterface vence
        // ---------------------------------------------------------------
        $display("\n--- AS3: compunit_done=1, outinterface_rden=1 ---");
        compunit_busy     = 1'b0;
        compunit_done     = 1'b1;
        compunit_addr     = 17'd9999;
        compunit_rden     = 1'b0;
        outinterface_addr = 17'd4242;
        outinterface_rden = 1'b1;
        check(17'd4242, 1'b1, "AS3");

        #10;

        // ---------------------------------------------------------------
        // Extra: ambos rden=0 → ambos addr podem ser qualquer, rden=0
        // ---------------------------------------------------------------
        $display("\n--- Extra: ambos rden=0, busy=0 ---");
        compunit_busy     = 1'b0;
        compunit_done     = 1'b0;
        compunit_rden     = 1'b0;
        outinterface_rden = 1'b0;
        check(outinterface_addr, 1'b0, "EXTRA_NOP");

        #10;

        // Resultado final
        $display("\n========================================");
        if (fail_count == 0) begin
            $display("PASS: %0d/%0d cenarios corretos (SC-002 verificado)", pass_count, pass_count + fail_count);
        end else begin
            $display("FAIL: %0d divergencias em %0d cenarios", fail_count, pass_count + fail_count);
        end
        $display("========================================\n");
        $finish;
    end

    // Timeout
    initial begin
        #10000;
        $display("[tb] TIMEOUT");
        $finish;
    end

endmodule
