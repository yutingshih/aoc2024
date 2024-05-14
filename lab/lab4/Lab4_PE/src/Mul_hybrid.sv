`include "def.svh"

module ModifiedBoothUnit #(parameter IN_WIDTH = 8, OUT_WIDTH = 10) (
    input  [IN_WIDTH-1:0]  multiplicand,
    input  [2:0]           multiplier,
    output logic [OUT_WIDTH-1:0] product
);
    logic [OUT_WIDTH-1:0] zero;
    logic [OUT_WIDTH-1:0] pos_once;
    logic [OUT_WIDTH-1:0] neg_once;
    logic [OUT_WIDTH-1:0] pos_twice;
    logic [OUT_WIDTH-1:0] neg_twice;

    assign zero = {OUT_WIDTH{1'b0}};
    assign pos_once = {{(OUT_WIDTH-IN_WIDTH){multiplicand[IN_WIDTH-1]}}, multiplicand};
    assign neg_once = ~pos_once + 1;
    assign pos_twice = pos_once << 1;
    assign neg_twice = neg_once << 1;

    always_comb begin
        case (multiplier)
            3'b000:  product = zero;
            3'b001:  product = pos_once;
            3'b010:  product = pos_once;
            3'b011:  product = pos_twice;
            3'b100:  product = neg_twice;
            3'b101:  product = neg_once;
            3'b110:  product = neg_once;
            3'b111:  product = zero;
            default: product = zero;
        endcase
    end
endmodule

module Mul_hybrid (
    input	[7:0]	ifmap,			//input feature map
    input	[7:0]	filter, 		//filter
    input	[3:0]	ifmap_Quant_size,
    input	[3:0]	filter_Quant_size,
    output	logic 	[`Psum_BITS-1:0]	product
);
    logic [7:0] multiplicands [3:0];
    logic [2:0] multipliers [3:0];
    logic [9:0] products [3:0];
    logic [11:0] sum01;
    logic [11:0] sum23;
    logic [23:0] sum0123;

    ModifiedBoothUnit mbu0(.multiplicand(multiplicands[0]),.multiplier(multipliers[0]),.product(products[0]));
    ModifiedBoothUnit mbu1(.multiplicand(multiplicands[1]),.multiplier(multipliers[1]),.product(products[1]));
    ModifiedBoothUnit mbu2(.multiplicand(multiplicands[2]),.multiplier(multipliers[2]),.product(products[2]));
    ModifiedBoothUnit mbu3(.multiplicand(multiplicands[3]),.multiplier(multipliers[3]),.product(products[3]));

    always_comb begin
        case (ifmap_Quant_size)
            4'd8: begin
                multiplicands[0] = ifmap;
                multiplicands[1] = ifmap;
                multiplicands[2] = ifmap;
                multiplicands[3] = ifmap;
            end
            4'd4: begin
                multiplicands[0] = {{4{ifmap[3]}}, ifmap[3:0]};
                multiplicands[1] = {{4{ifmap[3]}}, ifmap[3:0]};
                multiplicands[2] = {{4{ifmap[3]}}, ifmap[3:0]};
                multiplicands[3] = {{4{ifmap[3]}}, ifmap[3:0]};
            end
            4'd2: begin
                multiplicands[0] = {{6{ifmap[1]}}, ifmap[1:0]};
                multiplicands[1] = {{6{ifmap[5]}}, ifmap[5:4]};
                multiplicands[2] = {{6{ifmap[1]}}, ifmap[1:0]};
                multiplicands[3] = {{6{ifmap[5]}}, ifmap[5:4]};
            end
            default: begin
                multiplicands[0] = 8'd0;
                multiplicands[1] = 8'd0;
                multiplicands[2] = 8'd0;
                multiplicands[3] = 8'd0;
            end
        endcase
    end

    always_comb begin
        case (filter_Quant_size)
            4'd8: begin
                multipliers[0] = {filter[1:0], 1'b0};
                multipliers[1] = filter[3:1];
                multipliers[2] = filter[5:3];
                multipliers[3] = filter[7:5];
            end
            4'd4: begin
                multipliers[0] = {filter[1:0], 1'b0};
                multipliers[1] = filter[3:1];
                multipliers[2] = {filter[5:4], 1'b0};
                multipliers[3] = filter[7:5];
            end
            4'd2: begin
                multipliers[0] = {filter[1:0], 1'b0};
                multipliers[1] = {filter[1:0], 1'b0};
                multipliers[2] = {filter[5:4], 1'b0};
                multipliers[3] = {filter[5:4], 1'b0};
            end
            default: begin
                multipliers[0] = 3'b0;
                multipliers[1] = 3'b0;
                multipliers[2] = 3'b0;
                multipliers[3] = 3'b0;
            end
        endcase
    end

    assign sum01 = {{2{products[0][9]}}, products[0]} + {products[1], {2{1'b0}}};
    assign sum23 = {{2{products[2][9]}}, products[2]} + {products[3], {2{1'b0}}};
    assign sum0123 = {{12{sum01[11]}}, sum01} + ({{12{sum23[11]}}, sum23} << 4);

    always_comb begin
        case (ifmap_Quant_size)
            4'd8: product = sum0123;
            4'd4: product = {sum23, sum01};
            4'd2: product = {products[3][5:0], products[2][5:0], products[1][5:0], products[0][5:0]};
            default: product = `Psum_BITS'd0;
        endcase
    end

endmodule
