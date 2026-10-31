from pathlib import Path
root = Path(__file__).resolve().parents[1]
table = '\n'.join(f"                8'd{i}: gamma80=8'd{round(255*(i/255)**0.80)};" for i in range(256))
source = '''// Base display gamma=0.80; RGB and metadata share one register stage.
module base_gamma(input wire I_clk,I_rst_n,input wire [30:0] I_pixel,output reg [30:0] O_pixel);
    function [7:0] gamma80;
        input [7:0] value;
        begin case(value)
TABLE
            endcase
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) O_pixel<=0;
        else begin
            O_pixel[30:24]<=I_pixel[30:24];
            O_pixel[23:0]<=I_pixel[26]?{gamma80(I_pixel[23:16]),gamma80(I_pixel[15:8]),gamma80(I_pixel[7:0])}:24'd0;
        end
    end
endmodule
'''.replace('TABLE', table)
(root/'user_source/hdl_source/base_gamma.v').write_text(source, encoding='utf-8')
