module hash_engine #(
    parameter W = 128 // Tamanho da chave
)(
    input wire clock,
    input wire reset,
    input wire [W-1:0] key,
    input wire [W-1:0] matrix,
    output reg hash_b
);

    // (reset sincrono)
    always @(posedge clock) begin
        if (reset) begin
            hash_b <= 1'b0;
        end else begin
            // Faz o AND bit a bit (multiplicacao) e a redução XOR (somatorio mod 2)
            hash_b <= ^(key & matrix);
        end
    end

endmodule