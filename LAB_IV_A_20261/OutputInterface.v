//========================================================================================
// File: OutputInterface.v
// Description: Estagio final do pipeline de Privacy Amplification (RF-08).
//              Le a chave secreta da RAM dupla-porta (RAM_OUT, preenchida pela
//              Compression Unit) e a entrega serialmente (1 bit/ciclo) ao exterior
//              via handshake valid/ready, com sinalizacao de status busy/done/error.
//
// Rastreabilidade de requisitos:
//   RF-08    : entrega da chave secreta apos a conclusao (sinalizada por 'done').
//   RF-05/06 : reset leva a IDLE limpo; streaming coordenado por FSM local.
//   RNF-01/  : leitura PIPELINADA sustenta 1 bit/ciclo = 100 Mbps @100 MHz
//   RD-01      (a RAM_OUT tem 2 ciclos de latencia de leitura registrada; sem
//              pipeline o throughput cairia para ~1 bit/3 ciclos).
//   RNF-02   : saidas registradas; sem caminho combinacional de ram_data -> secret_bit.
//   RNF-05/  : L, RAM_ADDR_WIDTH e RAM_READ_LATENCY parametrizaveis.
//   RD-03/04   (para blocos >= 10^6 bits, regerar RAM_OUT com mais palavras e usar
//              RAM_ADDR_WIDTH >= 20).
//   RNF-07   : 'error' detecta L invalido e fim inesperado (enable cai no meio),
//              travando em ST_ERROR.
//   RNF-08   : zeragem (zeroize) dos fragmentos da chave em done/error/reset; nenhum
//              sinal interno da chave e exposto em portas de status.
//========================================================================================

module OutputInterface #(
	parameter L                = 100_000, // tamanho da chave secreta (bits) - RF-02/RNF-05
	parameter RAM_ADDR_WIDTH   = 17,       // 2^17 = 131072 >= L (largura de endereco da RAM)
	parameter RAM_READ_LATENCY = 2,        // ciclos de latencia da RAM_OUT (addr_reg + outdata_reg)
	parameter FIFO_DEPTH       = 4,        // skid buffer; deve ser > CAP_DELAY p/ throughput pleno
	parameter TIMEOUT_EN       = 0,        // 1 = sinaliza error se consumidor travar (opcional)
	parameter TIMEOUT_CYC      = 1_000_000 // ciclos sem secret_ready ate timeout (se habilitado)
)(
	input clk,
	input rst,        // reset assincrono global, ativo-alto (botao FPGA)
	input rst_soft,   // reset sincrono, ativo-alto (controlado pela Control Unit)
	input enable,

	// ---- Downstream: entrega ao exterior (mestre: eu entrego) ----
	output reg secret_bit,    // bit da chave final
	output reg secret_valid,  // bit valido
	input      secret_ready,  // consumidor pronto

	// ---- Interface com RAM (IP Catalog - RAM:2-PORT), PORT_B (leitura registrada) ----
	output reg [RAM_ADDR_WIDTH-1:0] ram_addr,
	output reg                      ram_rden,
	input                           ram_data,

	// ---- Status ----
	output reg busy,
	output reg done,
	output reg error
);

	// --------------------------------------------------------------------------------
	// FSM interna do Output Interface (RF-06)
	// --------------------------------------------------------------------------------
	localparam ST_IDLE  = 3'd0,  // ocioso, aguardando 'enable'
	           ST_READ  = 3'd1,  // ciclo de preparacao (pointers prontos)
	           ST_SEND  = 3'd2,  // streaming pipelinado (emite leituras + drena saida)
	           ST_DONE  = 3'd3,  // chave entregue; zeroize; aguarda re-arme
	           ST_ERROR = 3'd4;  // inconsistencia detectada; zeroize; travado (RNF-07)

	reg [2:0] state;

	// Larguras derivadas
	localparam CNTW      = RAM_ADDR_WIDTH + 1;          // contadores 0..L
	localparam CAP_DELAY = RAM_READ_LATENCY + 1;        // +1 do registro de ram_addr/ram_rden
	localparam FIFO_AW   = (FIFO_DEPTH <= 1) ? 1 : $clog2(FIFO_DEPTH);

	// Geracao de leitura (issue)
	reg  [CNTW-1:0]      current_addr;   // proximo endereco a emitir (read pointer)
	reg  [CNTW-1:0]      sent_cnt;       // bits ja aceitos pelo consumidor (0..L)

	// Rastreamento de leituras "em voo" (pipeline da latencia da RAM)
	reg  [CAP_DELAY-1:0] inflight_pipe;  // tag '1' por ciclo em que houve emissao
	reg  [3:0]           inflight;       // numero de leituras emitidas e ainda nao capturadas

	// Skid buffer / FIFO de saida (1 bit), em Verilog puro (RNF-08: fragmentos da chave)
	reg                  buf_mem [0:FIFO_DEPTH-1];
	reg  [FIFO_AW-1:0]   wr_ptr;
	reg  [FIFO_AW-1:0]   rd_ptr_f;
	reg  [FIFO_AW:0]     fifo_count;     // ocupacao 0..FIFO_DEPTH

	// Timeout opcional do consumidor (RNF-07, desabilitado por padrao)
	reg  [31:0]          stall_cnt;

	// Deteccao de borda de subida de 'enable' (re-arme apos done/error)
	reg                  enable_d;

	integer i;

	// --------------------------------------------------------------------------------
	// Sinais combinacionais de controle (usam valores correntes dos registradores)
	// --------------------------------------------------------------------------------
	// Espaco do registrador de saida livre para receber um novo bit
	wire out_free   = (~secret_valid) | secret_ready;
	// O dado da RAM esta valido neste ciclo (tag emergindo do pipeline de latencia)
	wire capture    = inflight_pipe[CAP_DELAY-1];
	// Ha credito para emitir nova leitura sem estourar a FIFO:
	//   inflight + fifo_count <= FIFO_DEPTH  =>  fifo_count nunca excede FIFO_DEPTH (sem perda)
	wire can_issue  = ((inflight + fifo_count) < FIFO_DEPTH);
	wire do_issue   = (state == ST_SEND) & (current_addr < L) & can_issue;
	// Pop da FIFO para o registrador de saida
	wire pop        = out_free & (fifo_count != 0);
	// Obs.: a deteccao de borda de subida de 'enable' (re-arme) e feita INLINE no bloco
	// sincrono via (enable & ~enable_d), lendo o reg enable_d com seu valor pre-borda.

	// Tarefa de zeragem dos fragmentos da chave (RNF-08)
	// (implementada inline; reset e estados finais limpam buffer e saida)

	always @(posedge clk or posedge rst)
	begin
		if (rst)  // ----- reset assincrono global -----
		begin
			state         <= ST_IDLE;
			current_addr  <= {CNTW{1'b0}};
			sent_cnt      <= {CNTW{1'b0}};
			inflight_pipe <= {CAP_DELAY{1'b0}};
			inflight      <= 4'd0;
			wr_ptr        <= {FIFO_AW{1'b0}};
			rd_ptr_f      <= {FIFO_AW{1'b0}};
			fifo_count    <= {(FIFO_AW+1){1'b0}};
			stall_cnt     <= 32'd0;
			enable_d      <= 1'b0;
			secret_bit    <= 1'b0;
			secret_valid  <= 1'b0;
			ram_addr      <= {RAM_ADDR_WIDTH{1'b0}};
			ram_rden      <= 1'b0;
			busy          <= 1'b0;
			done          <= 1'b0;
			error         <= 1'b0;
			for (i = 0; i < FIFO_DEPTH; i = i + 1) buf_mem[i] <= 1'b0; // zeroize (RNF-08)
		end
		else if (rst_soft)  // ----- reset sincrono (Control Unit) -----
		begin
			state         <= ST_IDLE;
			current_addr  <= {CNTW{1'b0}};
			sent_cnt      <= {CNTW{1'b0}};
			inflight_pipe <= {CAP_DELAY{1'b0}};
			inflight      <= 4'd0;
			wr_ptr        <= {FIFO_AW{1'b0}};
			rd_ptr_f      <= {FIFO_AW{1'b0}};
			fifo_count    <= {(FIFO_AW+1){1'b0}};
			stall_cnt     <= 32'd0;
			enable_d      <= 1'b0;
			secret_bit    <= 1'b0;
			secret_valid  <= 1'b0;
			ram_addr      <= {RAM_ADDR_WIDTH{1'b0}};
			ram_rden      <= 1'b0;
			busy          <= 1'b0;
			done          <= 1'b0;
			error         <= 1'b0;
			for (i = 0; i < FIFO_DEPTH; i = i + 1) buf_mem[i] <= 1'b0; // zeroize (RNF-08)
		end
		else
		begin
			enable_d <= enable;  // registra enable p/ deteccao de borda
			case (state)
				// -------------------------------------------------------------------
				ST_IDLE: begin
					ram_rden     <= 1'b0;
					secret_valid <= 1'b0;
					if (enable)
					begin
						// Validacao de L (RNF-07): tamanho fora do suportado pela RAM
						if ((L == 0) || (L > (1 << RAM_ADDR_WIDTH)))
						begin
							error <= 1'b1;
							busy  <= 1'b0;
							done  <= 1'b0;
							state <= ST_ERROR;
						end
						else
						begin
							// Inicializa streaming
							current_addr  <= {CNTW{1'b0}};
							sent_cnt      <= {CNTW{1'b0}};
							inflight_pipe <= {CAP_DELAY{1'b0}};
							inflight      <= 4'd0;
							wr_ptr        <= {FIFO_AW{1'b0}};
							rd_ptr_f      <= {FIFO_AW{1'b0}};
							fifo_count    <= {(FIFO_AW+1){1'b0}};
							stall_cnt     <= 32'd0;
							secret_bit    <= 1'b0;
							secret_valid  <= 1'b0;
							busy          <= 1'b1;
							done          <= 1'b0;
							error         <= 1'b0;
							state         <= ST_READ;
						end
					end
				end

				// -------------------------------------------------------------------
				ST_READ: begin
					// Ciclo de preparacao: pointers/credito ja zerados; inicia o streaming.
					ram_rden <= 1'b0;
					state    <= ST_SEND;
				end

				// -------------------------------------------------------------------
				// Streaming PIPELINADO (RNF-01/RD-01): emite uma leitura por ciclo
				// enquanto houver credito, e drena os dados que saem da RAM CAP_DELAY
				// ciclos depois. O skid buffer absorve as leituras em voo quando o
				// consumidor estagna (secret_ready=0), sem perder bits.
				ST_SEND: begin
					// (1) Emissao de leitura
					if (do_issue)
					begin
						ram_addr     <= current_addr[RAM_ADDR_WIDTH-1:0];
						ram_rden     <= 1'b1;
						current_addr <= current_addr + 1'b1;
					end
					else
					begin
						ram_rden <= 1'b0;
					end

					// (2) Pipeline de latencia da RAM: insere a tag da emissao
					inflight_pipe <= {inflight_pipe[CAP_DELAY-2:0], do_issue};
					inflight      <= inflight + (do_issue ? 4'd1 : 4'd0)
					                          - (capture  ? 4'd1 : 4'd0);

					// (3) Captura do dado valido da RAM para a FIFO
					if (capture)
					begin
						buf_mem[wr_ptr] <= ram_data;
						wr_ptr          <= wr_ptr + 1'b1;
					end

					// (4) Drenagem da FIFO para a saida registrada (RNF-02)
					if (out_free)
					begin
						if (fifo_count != 0)
						begin
							secret_bit   <= buf_mem[rd_ptr_f];
							secret_valid <= 1'b1;
							rd_ptr_f     <= rd_ptr_f + 1'b1;
						end
						else
						begin
							secret_bit   <= 1'b0; // nada a enviar (zeroize do datapath)
							secret_valid <= 1'b0;
						end
					end

					// (5) Atualiza ocupacao da FIFO (push=capture, pop)
					fifo_count <= fifo_count + (capture ? 1'b1 : 1'b0)
					                         - (pop     ? 1'b1 : 1'b0);

					// (6) Conta bits aceitos pelo consumidor (handshake completo)
					if (secret_valid & secret_ready)
						sent_cnt <= sent_cnt + 1'b1;

					// (7) Timeout opcional do consumidor (RNF-07)
					if (TIMEOUT_EN)
					begin
						if (secret_valid & ~secret_ready) stall_cnt <= stall_cnt + 1'b1;
						else                              stall_cnt <= 32'd0;
					end

					// (8) Condicoes de saida do estado
					if (~enable)
					begin
						// Fim inesperado: enable caiu antes de concluir (RNF-07)
						error        <= 1'b1;
						busy         <= 1'b0;
						secret_valid <= 1'b0;
						secret_bit   <= 1'b0;
						ram_rden     <= 1'b0;
						state        <= ST_ERROR;
					end
					else if (TIMEOUT_EN && (stall_cnt >= TIMEOUT_CYC))
					begin
						error        <= 1'b1;
						busy         <= 1'b0;
						secret_valid <= 1'b0;
						secret_bit   <= 1'b0;
						ram_rden     <= 1'b0;
						state        <= ST_ERROR;
					end
					else if (sent_cnt == L)
					begin
						state <= ST_DONE;
					end
				end

				// -------------------------------------------------------------------
				ST_DONE: begin
					// RF-08: chave totalmente entregue.
					busy         <= 1'b0;
					done         <= 1'b1;
					ram_rden     <= 1'b0;
					secret_valid <= 1'b0;
					secret_bit   <= 1'b0;                                  // zeroize (RNF-08)
					for (i = 0; i < FIFO_DEPTH; i = i + 1) buf_mem[i] <= 1'b0; // zeroize (RNF-08)
					// Re-arme: aguarda 'enable' baixar antes de aceitar nova chave.
					if (~enable)
					begin
						done  <= 1'b0;
						state <= ST_IDLE;
					end
				end

				// -------------------------------------------------------------------
				ST_ERROR: begin
					// RNF-07: travado sinalizando erro; nao expoe dados (RNF-08).
					busy         <= 1'b0;
					error        <= 1'b1;
					ram_rden     <= 1'b0;
					secret_valid <= 1'b0;
					secret_bit   <= 1'b0;                                  // zeroize (RNF-08)
					for (i = 0; i < FIFO_DEPTH; i = i + 1) buf_mem[i] <= 1'b0; // zeroize (RNF-08)
					// Re-arme: 'error' fica latched ate uma NOVA requisicao (borda de
					// subida de enable). Necessario porque o "fim inesperado" e disparado
					// justamente por enable baixar -- nao se pode limpar com ~enable.
					if (enable & ~enable_d)
					begin
						error <= 1'b0;
						done  <= 1'b0;
						state <= ST_IDLE;
					end
				end

				// -------------------------------------------------------------------
				default: state <= ST_IDLE;
			endcase
		end
	end
endmodule
