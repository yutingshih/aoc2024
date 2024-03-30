`include "../include/def.svh"

module ModifiedBoothUnit #(
    parameter IN_WIDTH = 8,
    parameter OUT_WIDTH = 9
) (
    input  [IN_WIDTH-1:0]  multiplicand,
    input  [2:0]           multiplier,
    output logic [OUT_WIDTH-1:0] product
);
    logic [IN_WIDTH:0] zero = {(IN_WIDTH+1){1'b0}};
    logic [IN_WIDTH:0] once = {multiplicand[IN_WIDTH-1], multiplicand};
    logic [IN_WIDTH:0] twice = {multiplicand[IN_WIDTH-1], multiplicand} << 1;
    logic [IN_WIDTH:0] negative = ~{multiplicand[IN_WIDTH-1], multiplicand} + {{IN_WIDTH{1'b0}}, 1'b1};
    logic [IN_WIDTH:0] neg_twice = negative << 1;
    logic [IN_WIDTH:0] res;

    always_comb begin
        case (multiplier)
            3'b000:  res = zero;
            3'b001:  res = once;
            3'b010:  res = once;
            3'b011:  res = twice;
            3'b100:  res = neg_twice;
            3'b101:  res = negative;
            3'b110:  res = negative;
            3'b111:  res = zero;
            default: res = zero;
        endcase
        product = {{(OUT_WIDTH-IN_WIDTH-1){res[IN_WIDTH]}}, res};
    end
endmodule

module Mul_hybrid (
    input	[7:0]	ifmap,			//input feature map
    input	[7:0]	filter, 		//filter
    input	[3:0]	ifmap_Quant_size,
    input	[3:0]	filter_Quant_size,
    output	logic	[`Psum_BITS-1:0]	product
);
    logic [7:0] multiplicand0;
    logic [7:0] multiplicand1;
    logic [7:0] multiplicand2;
    logic [7:0] multiplicand3;
    logic [2:0] multiplier0;
    logic [2:0] multiplier1;
    logic [2:0] multiplier2;
    logic [2:0] multiplier3;
    logic [14:0] product0;
    logic [12:0] product1;
    logic [10:0] product2;
    logic [ 9:0] product3;

    ModifiedBoothUnit #(.IN_WIDTH(8), .OUT_WIDTH(15)) mbu0(
        .multiplicand(multiplicand0),
        .multiplier(multiplier0),
        .product(product0)
    );
    ModifiedBoothUnit #(.IN_WIDTH(8), .OUT_WIDTH(13)) mbu1(
        .multiplicand(multiplicand1),
        .multiplier(multiplier1),
        .product(product1)
    );
    ModifiedBoothUnit #(.IN_WIDTH(8), .OUT_WIDTH(11)) mbu2(
        .multiplicand(multiplicand2),
        .multiplier(multiplier2),
        .product(product2)
    );
    ModifiedBoothUnit #(.IN_WIDTH(8), .OUT_WIDTH( 9)) mbu3(
        .multiplicand(multiplicand3),
        .multiplier(multiplier3),
        .product(product3)
    );

    always_comb begin
        case (ifmap_Quant_size)
            4'd8: begin
                multiplicand0 = ifmap;
                multiplicand1 = ifmap;
                multiplicand2 = ifmap;
                multiplicand3 = ifmap;
            end
            4'd4: begin
                multiplicand0 = {{4{ifmap[3]}}, ifmap[3:0]};
                multiplicand1 = {{4{ifmap[3]}}, ifmap[3:0]};
                multiplicand2 = {{4{ifmap[3]}}, ifmap[3:0]};
                multiplicand3 = {{4{ifmap[3]}}, ifmap[3:0]};
            end
            4'd2: begin
                multiplicand0 = {{6{ifmap[1]}}, ifmap[1:0]};
                multiplicand1 = {{6{ifmap[5]}}, ifmap[5:4]};
                multiplicand2 = {{6{ifmap[1]}}, ifmap[1:0]};
                multiplicand3 = {{6{ifmap[5]}}, ifmap[5:4]};
            end
            default: begin
                multiplicand0 = ifmap;
                multiplicand1 = ifmap;
                multiplicand2 = ifmap;
                multiplicand3 = ifmap;
            end
        endcase
    end

    always_comb begin
        case (filter_Quant_size)
            4'd8: begin
                multiplier0 = {filter[1:0], 1'b0};
                multiplier1 = filter[3:1];
                multiplier2 = filter[5:3];
                multiplier3 = filter[7:5];
            end
            4'd4: begin
                multiplier0 = {filter[1:0], 1'b0};
                multiplier1 = filter[3:1];
                multiplier2 = {filter[5:4], 1'b0};
                multiplier3 = filter[7:5];
            end
            4'd2: begin
                multiplier0 = {filter[1:0], 1'b0};
                multiplier1 = {filter[3:2], 1'b0};
                multiplier2 = {filter[5:4], 1'b0};
                multiplier3 = {filter[7:6], 1'b0};
            end
            default: begin
                multiplier0 = 3'b0;
                multiplier1 = 3'b0;
                multiplier2 = 3'b0;
                multiplier3 = 3'b0;
            end
        endcase
    end

    logic [14:0] sum01 = product0 + {product1, {2{1'b0}}};  // 15 bits
    logic [10:0] sum23 = product2 + {product3, {2{1'b0}}};  // 11 bits
    logic [14:0] sum0123 = sum01 + {sum23, {4{1'b0}}};  // 15 bits

    always_comb begin
        case (ifmap_Quant_size)
            4'd8: product = sum0123;
            4'd4: product = {sum23[10], sum23, sum01[11:0]};
            4'd2: product = {product3[5:0], product2[5:0], product1[5:0], product0[5:0]};
            default: product = `Psum_BITS'd0;
        endcase
    end
    // always_comb begin
        //// tb0
        //product[23:0] = $signed(ifmap)*$signed(filter);
        //// tb1
        //product[23:12] = -12'd7;
        //product[11:0] = 12'd1;
        // product[23:12] = $signed(ifmap[3:0])*$signed(filter[7:4]);
        // product[11:0] = $signed(ifmap[3:0])*$signed(filter[3:0]);

        //// tb2
        /* product[23:18] = $signed(ifmap[5:4])*$signed(filter[5:4]);
        product[17:12] = $signed(ifmap[1:0])*$signed(filter[5:4]);
        product[11:6] = $signed(ifmap[5:4])*$signed(filter[1:0]); */

        //$display("Mul: %d %d",$signed(ifmap[1:0]),$signed(filter[1:0]));
        //product[5:0] = $signed(ifmap[1:0])*$signed(filter[1:0]);
        //$display("Mul product : %d",$signed(product[5:0]));
    // end

endmodule