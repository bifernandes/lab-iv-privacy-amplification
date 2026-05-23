`timescale 1ns/1ps

module hash_engine_tb;
    // Parâmetros Globais do TB
    parameter W = 32;

    // Sinais dimensionados por W
    reg clock;
    reg reset;
    reg [W-1:0] key;
    reg [W-1:0] matrix;
    wire hash_b;

    // Instanciação parametrizada
    hash_engine #(.W(W)) uut (
        .clock  (clock),
        .reset  (reset),
        .key    (key),
        .matrix (matrix),
        .hash_b (hash_b)
    );

    // Clock: período de 10ns
    initial clock = 0;
    always #5 clock = ~clock;

    // Função para calcular o esperado em software
    function calc_expected;
        input [W-1:0] k;
        input [W-1:0] m;
        integer j;
        reg result;
        begin
            result = 1'b0;
            for (j = 0; j < W; j = j + 1)
                result = result ^ (k[j] & m[j]);
            calc_expected = result;
        end
    endfunction

    // Tarefa de verificação
    task apply_and_check;
        input [W-1:0] t_key;
        input [W-1:0] t_matrix;
        input         t_expected;
        input [127:0] t_label;
        begin
            key    = t_key;
            matrix = t_matrix;
            @(posedge clock); #1;
            if (hash_b === t_expected)
                $display("[PASS] %s | key=0x%08X matrix=0x%08X | hash_b=%b (esperado=%b)",
                          t_label, t_key, t_matrix, hash_b, t_expected);
            else
                $display("[FAIL] %s | key=0x%08X matrix=0x%08X | hash_b=%b (esperado=%b)",
                          t_label, t_key, t_matrix, hash_b, t_expected);
        end
    endtask

    integer i;
    reg [W-1:0] rand_key, rand_mat;

    initial begin
        reset = 1;
        key = 0;
        matrix = 0;

        @(posedge clock); #1;

        if (hash_b === 1'b0)
            $display("[PASS] Reset | hash_b=0 apos reset");
        else
            $display("[FAIL] Reset | hash_b=%b (esperado=0)", hash_b);
            
        reset = 0;

        // -----------------------------------------------
        // Casos determinísticos
        // -----------------------------------------------

        // Todos zeros: resultado deve ser 0
        apply_and_check(32'h00000000, 32'h00000000, 1'b0, "Zeros        ");

        // Todos uns: 32 bits ativos, XOR de 32 x 1 = 0 (par)
        apply_and_check(32'hFFFFFFFF, 32'hFFFFFFFF, 1'b0, "Todos uns    ");

        // Um único bit ativo: resultado deve ser 1
        apply_and_check(32'h00000001, 32'h00000001, 1'b1, "1 bit ativo  ");

        // Bits sem sobreposição: AND = 0, resultado = 0
        apply_and_check(32'hAAAAAAAA, 32'h55555555, 1'b0, "Sem overlap  ");

        // Caso manual: key=0x3, matrix=0x3 → bits 0 e 1 ativos → XOR(1,1) = 0
        apply_and_check(32'h00000003, 32'h00000003, 1'b0, "2 bits pares ");

        // Caso manual: key=0x7, matrix=0x7 → bits 0,1,2 ativos → XOR(1,1,1) = 1
        apply_and_check(32'h00000007, 32'h00000007, 1'b1, "3 bits impares");

        // -----------------------------------------------
        // Casos aleatórios com verificação automática
        // -----------------------------------------------
        $display("--- Casos aleatorios ---");
        for (i = 0; i < 5; i = i + 1) begin
            // Gerando valores aleatórios compatíveis com a largura
            rand_key = $random;
            rand_mat = $random;
            apply_and_check(rand_key, rand_mat,
                            calc_expected(rand_key, rand_mat),
                            "Aleatorio    ");
        end

        // -----------------------------------------------
        // Verifica reset no meio da operação
        // -----------------------------------------------
        key = 32'hDEADBEEF;
        matrix = 32'hCAFEBABE;

        @(posedge clock); #1;
        reset = 1;
        @(posedge clock); #1;
        
        if (hash_b === 1'b0)
            $display("[PASS] Reset mid-op | hash_b=0 apos reset");
        else
            $display("[FAIL] Reset mid-op | hash_b=%b (esperado=0)", hash_b);
            
        reset = 0;

        #20;
        $display("--- Testbench concluido ---");
        $stop;
    end
endmodule