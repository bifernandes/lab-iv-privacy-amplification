`timescale 1ns/1ps

module compression_unit_tb;

    // Parâmetros Globais do TB
    parameter P = 4;
    parameter W = 32;

    // Sinais parametrizados
    reg clock;
    reg reset;
    reg [W-1:0] key;
    reg [(W+P-2):0] matrix_window; 
    wire [P-1:0] hash_out;

    // Instanciação da Compression Unit
    compression_unit #(
        .P(P),
        .W(W)
    ) uut (
        .clock         (clock),
        .reset         (reset),
        .key           (key),
        .matrix_window (matrix_window),
        .hash_out      (hash_out)
    );

    // Clock: período de 10ns
    initial clock = 0;
    always #5 clock = ~clock;

    // Funcao para calcular o esperado em software, espelhando a construcao
    // Toeplitz implementada em compression_unit.v:
    //   T[i,j] = m_win[j-i]         se j >= i
    //   T[i,j] = m_win[W+i-j-1]     se j <  i
    function [P-1:0] calc_expected;
        input [W-1:0] k;
        input [(W+P-2):0] m_win;

        integer i, j, idx;
        reg row_bit;
        reg bit_result;
        reg [P-1:0] full_result;

        begin
            full_result = 0;
            for (i = 0; i < P; i = i + 1) begin
                bit_result = 1'b0;
                for (j = 0; j < W; j = j + 1) begin
                    idx = (j >= i) ? (j - i) : (W + i - j - 1);
                    row_bit = m_win[idx];
                    bit_result = bit_result ^ (k[j] & row_bit);
                end
                full_result[i] = bit_result;
            end
            calc_expected = full_result;
        end
    endfunction

    // Tarefa de verificação
    task apply_and_check;
        input [W-1:0] t_key;
        input [(W+P-2):0] t_matrix_window;
        input [P-1:0] t_expected;
        input [151:0] t_label;
        
        reg [P-1:0] actual_out;
        begin
            key = t_key;
            matrix_window = t_matrix_window;
            
            @(posedge clock); #1;
            actual_out = hash_out;
            
            if (actual_out === t_expected)
                $display("[PASS] %s | hash_out=%b (esperado=%b)",
                          t_label, actual_out, t_expected);
            else
                $display("[FAIL] %s | hash_out=%b (esperado=%b) | key=0x%08X mat=0x%016X",
                          t_label, actual_out, t_expected, t_key, t_matrix_window);
        end
    endtask

    integer idx;
    reg [W-1:0] rand_key;
    reg [(W+P-2):0] rand_mat;

    initial begin
        // -----------------------------------------------
        // Inicialização e Reset
        // -----------------------------------------------
        reset = 1;
        key = 0;
        matrix_window = 0;

        @(posedge clock); #1;

        if (hash_out === {P{1'b0}})
            $display("[PASS] Reset        | hash_out=0 apos reset");
        else
            $display("[FAIL] Reset        | hash_out=%b (esperado=0)", hash_out);
            
        reset = 0;

        // Casos determinísticos triviais que valem para a construcao Toeplitz
        $display("--- Casos deterministicos (P = %0d, W = %0d) ---", P, W);

        // Zeros -> 4'b0000 (T multiplicando 0 da 0)
        apply_and_check(32'h00000000, 63'h0000000000000000, 4'b0000, "Zeros           ");

        // Todos uns -> 4'b0000
        // T tem todas entradas = 1, key tem W=32 uns. Cada hash[i] = sum_j 1 mod 2 = 0.
        apply_and_check(32'hFFFFFFFF, 63'h7FFFFFFFFFFFFFFF, 4'b0000, "Todos uns       ");

        // Apenas bit 0 da key, apenas bit 0 do matrix_window -> hash = 4'b0001
        // hash[i] = T[i,0] = (i==0) ? mw[0] : mw[W+i-1]. Com mw so com bit 0 ativo,
        // T[0,0]=1 e T[i>0,0]=0. So bit 0 do hash acende.
        apply_and_check(32'h00000001, 63'h0000000000000001, 4'b0001, "Apenas bit 0    ");

        // -----------------------------------------------
        // Casos Aleatórios
        // -----------------------------------------------
        $display("--- Casos aleatorios ---");
        for (idx = 0; idx < 10; idx = idx + 1) begin
            rand_key = $random;
            rand_mat = {$random, $random}; 
            apply_and_check(rand_key, rand_mat, calc_expected(rand_key, rand_mat), "Aleatorio       ");
        end

        // -----------------------------------------------
        // Verifica reset no meio da operação
        // -----------------------------------------------
        $display("--- Teste de Reset Assincrono / Sincrono ---");
        key = 32'hDEADBEEF;
        matrix_window = 64'hCAFEBABEDEADBEEF;
        
        @(posedge clock); #1;
        reset = 1;
        @(posedge clock); #1;
        
        if (hash_out === {P{1'b0}})
            $display("[PASS] Reset mid-op | hash_out=0 apos reset");
        else
            $display("[FAIL] Reset mid-op | hash_out=%b (esperado=0)", hash_out);
            
        reset = 0;

        #20;
        $display("--- Testbench concluido ---");
        $stop;
    end

endmodule