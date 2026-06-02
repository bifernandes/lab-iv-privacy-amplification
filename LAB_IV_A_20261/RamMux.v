//========================================================================================
// File: RamMux.v
// Description: Multiplexador para leitura na PORT_B da RAM 
//              (CompressionUnit e OutputInterface executando simultaneamente)
//========================================================================================

module RamMux #(
    parameter RAM_ADDR_WIDTH = 17
)(
	// Interface com CompressionUnit (sempre ativo)
	input [RAM_ADDR_WIDTH-1:0] cu_addr,
	input cu_rden,
	
	// Interface com OutputInterface (sempre ativo)
	input [RAM_ADDR_WIDTH-1:0] oi_addr,
	input oi_rden,
	
	// Interface com CompressionUnit (para saber quando processa)
	input cu_busy,
	input cu_done,
	
	// Saída para a RAM
	output reg [RAM_ADDR_WIDTH-1:0] ram_addr,
	output reg ram_rden
);

always @(*) 
begin
	// Prioridade para CompressionUnit enquanto nao terminou
	if (!cu_done) 
	begin
		ram_addr = cu_addr;
		ram_rden = cu_rden;
	end else 
	begin
		// CompressionUnit terminou, OutputInterface pode ler
		ram_addr = oi_addr;
		ram_rden = oi_rden;
	end
end
endmodule
