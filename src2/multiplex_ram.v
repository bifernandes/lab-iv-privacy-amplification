// multiplex_ram — Arbitrador de leitura da Porta B da dual_port_ram.
//
// Especificacao (FR-002, FR-003):
//   - Prioridade: compression_unit enquanto compunit_busy = 1
//   - Se compunit_busy = 0: roteia sinais do output_interface
//   - Logica combinacional pura (sem registradores)
//
// Regras de arbitracao:
//   compunit_busy = 1 → rd_ram_addr = compunit_addr, rd_ram_rden = compunit_rden
//   compunit_busy = 0 → rd_ram_addr = outinterface_addr, rd_ram_rden = outinterface_rden
//
// Notas:
//   - compunit_done nao afeta a arbitracao diretamente; a prioridade e determinada
//     exclusivamente por compunit_busy (ativo = compressao em andamento).
//   - O output_interface so deve assertar outinterface_rden apos compunit_done = 1
//     (FR-010), mas o multiplex_ram nao reforca essa restricao — apenas arbitra.

`timescale 1ns/1ps

module multiplex_ram (
    // Sinais do compression_unit
    input  wire [16:0] compunit_addr,   // endereco de leitura do CU na Porta B
    input  wire        compunit_rden,   // habilitacao de leitura do CU
    input  wire        compunit_done,   // CU concluiu gravacao (nao usado na logica, exposto)
    input  wire        compunit_busy,   // CU em operacao de compressao/escrita

    // Sinais do output_interface
    input  wire [16:0] outinterface_addr,  // endereco de leitura do OI
    input  wire        outinterface_rden,  // habilitacao de leitura do OI

    // Saida para a Porta B da dual_port_ram
    output wire [16:0] rd_ram_addr,
    output wire        rd_ram_rden
);

    // Logica de arbitracao (combinacional):
    //   CU tem prioridade enquanto compunit_busy = 1
    assign rd_ram_addr = compunit_busy ? compunit_addr : outinterface_addr;
    assign rd_ram_rden = compunit_busy ? compunit_rden : outinterface_rden;

endmodule
