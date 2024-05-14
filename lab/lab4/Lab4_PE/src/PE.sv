`include "def.svh"
`include "Mul_hybrid.sv"

`define COL 3:2
`define CH 1:0
`define SIGN `Psum_BITS-1

module PE (
    input clk,
    input rst,

    // configuration
        input set_info,
        input [2:0] Ch_size,
        input [5:0] ifmap_column,
        input [5:0] ofmap_column,
        input [3:0] ifmap_Quant_size,
        input [3:0] filter_Quant_size,

    // filter
    input filter_enable,
    input [7:0] filter,
    output logic filter_ready,

    // ifmap
    input ifmap_enable,
    input [31:0] ifmap,
    output logic ifmap_ready,

    // ipsum
    input ipsum_enable,
    input [`Psum_BITS-1:0] ipsum,
    output logic ipsum_ready,

    // opsum
    input opsum_ready,
    output logic [`Psum_BITS-1:0] opsum,
    output logic opsum_enable
);

/**************** Declaration ****************/

    // control signals
    reg [3:0] ifmap_rid, ifmap_rid_nx;
    reg [3:0] filter_rid, filter_rid_nx;
    reg [3:0] ifmap_wid, ifmap_wid_nx;
    reg [3:0] filter_wid, filter_wid_nx;
    wire psum_wen;
    wire ifmap_wen = ifmap_ready && ifmap_enable;
    wire filter_wen = filter_ready && filter_enable;

    // scratchpad memory
    reg [7:0] ifmap_spad [11:0];
    reg [7:0] filter_spad [11:0];
    reg [23:0] psum_spad;

    // configuration registers
    reg [2:0] ch_sz;
    reg [5:0] ifmap_col;
    reg [5:0] ofmap_col;
    reg [3:0] ifmap_bits;
    reg [3:0] filter_bits;
    reg [5:0] out_cnt;

    // finite state machine
    enum {IDLE, MAC, ACC, OUT} state, state_nx;

/**************** Datapath ****************/

    // read spads
    wire [7:0] mul_src1 = ifmap_spad[ifmap_rid];
    wire [7:0] mul_src2 = filter_spad[filter_rid];
    always @(*) opsum = psum_spad;

    // multiplier
    wire [`Psum_BITS-1:0] mul_res;
    Mul_hybrid mul(
        .ifmap(mul_src1),
        .filter(mul_src2),
        .ifmap_Quant_size(ifmap_bits),
        .filter_Quant_size(filter_bits),
        .product(mul_res)
    );
    // wire [23:0] mul_res = {{16{mul_src1[7]}}, mul_src1} * {{16{mul_src2[7]}}, mul_src2};

    // adder
    wire [23:0] adder_src = state == ACC ? ipsum : mul_res;
    wire [23:0] adder_tmp = psum_spad + adder_src;
    wire overflow = psum_spad[`SIGN] == adder_src[`SIGN] && adder_src[`SIGN] != adder_tmp[`SIGN];
    wire [23:0] saturate = psum_spad[`SIGN] ? 24'h800000 : 24'h7fffff;
    wire [23:0] adder_res = overflow ? saturate : adder_tmp;

    // write spads
    wire clear = state == OUT && out_cnt == ofmap_col - 6'd1;
    wire shift = state == OUT && ifmap_rid == 4'd12 && !clear;
    integer i;
    always @(posedge clk or posedge rst) begin
        if (rst || clear) begin
            psum_spad <= `Psum_BITS'b0;
            for (i = 0; i < 12; i += 1) begin
                ifmap_spad[i] <= 8'b0;
                filter_spad[i] <= 8'b0;
            end
        end else if (shift) begin
            psum_spad <= `Psum_BITS'b0;
            for (i = 0; i < 4; i += 1) begin
                ifmap_spad[i] <= ifmap_spad[i+4];
                ifmap_spad[i+4] <= ifmap_spad[i+8];
                ifmap_spad[i+8] <= 8'b0;
            end
        end else begin
            psum_spad <= psum_wen ? adder_res : psum_spad;
            filter_spad[filter_wid] <= filter_wen ? filter : filter_spad[filter_wid];
            ifmap_spad[ifmap_wid] <= ifmap_wen ? ifmap[7:0] : ifmap_spad[ifmap_wid];
            ifmap_spad[ifmap_wid+4'd1] <= ifmap_wen ? ifmap[15:8] : ifmap_spad[ifmap_wid+4'd1];
            ifmap_spad[ifmap_wid+4'd2] <= ifmap_wen ? ifmap[23:16] : ifmap_spad[ifmap_wid+4'd2];
            ifmap_spad[ifmap_wid+4'd3] <= ifmap_wen ? ifmap[31:24] : ifmap_spad[ifmap_wid+4'd3];
        end
    end

    // configuration
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ch_sz <= 3'd0;
            ifmap_col <= 6'd0;
            ofmap_col <= 6'd0;
            ifmap_bits <= 4'd0;
            filter_bits <= 4'd0;
        end else begin
            ch_sz <= set_info ? Ch_size : ch_sz;
            ifmap_col <= set_info ? ifmap_column : ifmap_col;
            ofmap_col <= set_info ? ofmap_column : ofmap_col;
            ifmap_bits <= set_info ? ifmap_Quant_size : ifmap_bits;
            filter_bits <= set_info ? filter_Quant_size : filter_bits;
        end
    end

/**************** Controller ****************/

    wire last_mac = ifmap_rid == 4'd12;
    wire last_filt = filter_rid == 4'd12;

    // state transition
    always @(posedge clk or posedge rst) state <= rst ? IDLE: state_nx;
    always @(*) begin
        case (state)
            IDLE: state_nx = set_info ? MAC : state;
            MAC: state_nx = (last_mac && last_filt) ? ACC : state;
            ACC: state_nx = (ipsum_ready && ipsum_enable) ? OUT : state;
            OUT: state_nx = (opsum_ready && opsum_enable) ? MAC : state;
            default: state_nx = IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst || clear) out_cnt = 6'd0;
        else if (state == OUT) out_cnt = out_cnt + 6'd1;
        else out_cnt = out_cnt;
    end

    assign psum_wen = (state == MAC) || (ipsum_ready && ipsum_enable);

    always @(posedge clk or posedge rst) begin
        ifmap_wid <= rst ? 4'd0 :ifmap_wid_nx;
        ifmap_rid <= rst ? 4'd0 :ifmap_rid_nx;
        filter_wid <= rst ? 4'd0 :filter_wid_nx;
        filter_rid <= rst ? 4'd0 :filter_rid_nx;
    end

    // ifmap_wid_nx
    wire ifmap_not_full = ifmap_wid[`COL] < 2'd3 && ifmap_wid[`CH] < ch_sz;
    always @(*) begin
        if (set_info || clear)
            ifmap_wid_nx = 4'd0;
        else if (state == MAC && ifmap_not_full && ifmap_wen)
            ifmap_wid_nx = ifmap_wid + 4'd4;
        else if (state == OUT)
            ifmap_wid_nx = 4'd8;
        else
            ifmap_wid_nx = ifmap_wid;
    end

    // filter_wid_nx
    wire filter_not_full = filter_wid[`COL] < 2'd3 && filter_wid[`CH] < ch_sz;
    always @(*) begin
        if (set_info || clear)
            filter_wid_nx = 4'd0;
        else if (state == MAC && filter_not_full && filter_wen)
            if (({1'd0, filter_wid[`CH]} + 3'd1) == ch_sz)
                filter_wid_nx = {(filter_wid[`COL] + 2'd1), 2'd0};
            else
                filter_wid_nx = filter_wid + 4'd1;
        else
            filter_wid_nx = filter_wid;
    end

    // ifmap_rid_nx
    always @(*) begin
        if (state == IDLE || state == OUT)
            ifmap_rid_nx = 4'd0;
        else if (state == MAC && ifmap_rid < filter_wid && ifmap_rid[`COL] < ifmap_wid[`COL])
            ifmap_rid_nx = ifmap_rid + 4'd1;
        else
            ifmap_rid_nx = ifmap_rid;
    end

    // filter_rid_nx
    always @(*) begin
        if (state == IDLE || state == OUT)
            filter_rid_nx = 4'd0;
        else if (state == MAC && filter_rid < filter_wid && filter_rid[`COL] < ifmap_wid[`COL])
            filter_rid_nx = filter_rid + 4'd1;
        else
            filter_rid_nx = filter_rid;
    end

    // output handshaking
    assign ifmap_ready = state == MAC && ifmap_not_full;
    assign filter_ready = state == MAC && filter_not_full;
    assign ipsum_ready = state == ACC;
    assign opsum_enable = state == OUT;

/* debug */
/*
always @(state) begin
	$display("--- ifmap_spad ---  --- filter_spad ---");
	for (i = 0; i < ch_sz; i += 1) begin
		$write("%4d %4d %4d      %4d %4d %4d\n",
            $signed(ifmap_spad[i]),
            $signed(ifmap_spad[4+i]),
            $signed(ifmap_spad[8+i]),
		    $signed(filter_spad[i]),
            $signed(filter_spad[4+i]),
            $signed(filter_spad[8+i])
        );
	end
	$display("------------------ ------------------");

	// $display("[mul_res] = %d", $signed(mul_res));
	// $display("[adder_src] = %d", $signed(adder_src));
	// $display("[adder_res] = %d", $signed(adder_res));
	// $display("[psum_wen] = %d", psum_wen);
	$display("[psum_spad] = %d", $signed(psum_spad));
    $write("\n");

    // $display("[ifmap_ready, ifmap_enable] = %d & %d", ifmap_ready, ifmap_enable);
	// $display("[filter_ready, filter_enable] = %d & %d", filter_ready, filter_enable);
	$display("[ifmap_wid] = %d -> %d", ifmap_wid, ifmap_wid_nx);
	$display("[filter_wid] = %d -> %d", filter_wid, filter_wid_nx);
	$display("[ifmap_rid] = %d -> %d", ifmap_rid, ifmap_rid_nx);
	$display("[filter_rid] = %d -> %d", filter_rid, filter_rid_nx);
    $write("\n");

	// $display("[ipsum_ready, ipsum_enable] = %d & %d", ipsum_ready, ipsum_enable);
	$display("[ipsum] = %d", $signed(ipsum));
	// $display("[opsum_ready, opsum_enable] = %d & %d", opsum_ready, opsum_enable);
	$display("[opsum] = %d", $signed(opsum));
	$display("[out_cnt] = %d", out_cnt);

	$display("[state] = %s -> %s", state, state_nx);
	$display("------------------ ------------------\n");
end
*/
endmodule
