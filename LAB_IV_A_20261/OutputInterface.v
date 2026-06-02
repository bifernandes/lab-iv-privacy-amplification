//========================================================================================
// File: OutputInterface.v
// Description: Ler a RAM e envia resultado serialmente
//========================================================================================

module OutputInterface #(
	parameter L = 100_000,           //tamanho da chave secreta
	parameter RAM_ADDR_WIDTH = 17    // 2^17 = 131072 >= L
)(
	input clk,
	input rst,
	input rst_soft,
	input enable,
	
  output reg secret_bit,
	output reg secret_valid,
	input secret_ready,
	
	// Interface com RAM (IP Catalog - RAM:2-PORT)
	// PORT_B (leitura com saida registrada)
	output reg [RAM_ADDR_WIDTH-1:0] ram_addr,
	output reg ram_rden,
	input ram_data,
	
	// Status
	output reg busy,
	output reg done,
	output reg error
);

// FSM interna do Output Interface para controle da RAM
localparam ST_IDLE = 2'd0,
           ST_READ = 2'd1,
           ST_SEND = 2'd2,
           ST_DONE = 2'd3;

reg [1:0] state;
reg [RAM_ADDR_WIDTH-1:0] current_addr;
reg processing;

always @(posedge clk or posedge rst) 
begin
	if (rst) 												// reset assincrono global (botao FPGA)
	begin
		state <= ST_IDLE;
		current_addr <= {RAM_ADDR_WIDTH{1'b0}};
		processing <= 0;
		busy <= 0;
		done <= 0;
		error <= 0;
		secret_valid <= 0;
		secret_bit <= 0;
		ram_addr <= {RAM_ADDR_WIDTH{1'b0}};
		ram_rden <= 0;			
	end else 
	begin
		if (rst_soft)									// reset sincrono (controlar pela FSM)
		begin
			state <= ST_IDLE;
			current_addr <= {RAM_ADDR_WIDTH{1'b0}};
			processing <= 0;
			busy <= 0;
			done <= 0;
			error <= 0;
			secret_valid <= 0;
			secret_bit <= 0;
			ram_addr <= {RAM_ADDR_WIDTH{1'b0}};
			ram_rden <= 0;
		end else 
		begin
			secret_valid <= 0;
			error <= 0;
			ram_rden <= 0;
			
			if (enable && !busy && !done) 
			begin
				current_addr <= {RAM_ADDR_WIDTH{1'b0}};
				processing <= 1;
				busy <= 1;
				done <= 0;
				state <= ST_READ;
			end
			
			//FSM
			if (processing && !done && !error) 
			begin				
				case (state)
					ST_READ: begin
						if (current_addr < L) 
						begin
							ram_addr <= current_addr;
							ram_rden <= 1;
							state <= ST_SEND;
						end else 
						begin
							state <= ST_DONE;
						end
					end
					
					ST_SEND: begin
						if (secret_ready) 
						begin
							secret_bit <= ram_data;
							secret_valid <= 1;
							current_addr <= current_addr + 1'b1;
							state <= ST_READ;
						end
					end
					
					ST_DONE: begin
						processing <= 0;
						busy <= 0;
						done <= 1;
						state <= ST_IDLE;
					end
					
					default: state <= ST_IDLE;				
				endcase
			end
			
			// DESLIGAMENTO
			if (!enable) 
			begin
				processing <= 0;
				busy <= 0;
				done <= 0;
				error <= 0;
				state <= ST_IDLE;
				ram_rden <= 0;
			end
		end
	end
end
endmodule
