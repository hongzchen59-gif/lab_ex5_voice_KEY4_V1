// Cyan latency HUD at the lower-right of the 1280x720 active image. One glyph stage
// matches detect_overlay PIPELINED=1 and the established HDMI mixer pipeline.
module latency_overlay #(parameter X_ORIGIN=912,Y_ORIGIN=600)(
    input wire clk,rst_n,input wire [11:0] x,y,input wire de,
    input wire [1:0] status,input wire history_valid,
    input wire [15:0] value_bcd,min_bcd,max_bcd,input wire [31:0] measured_source,
    output wire text_hit,output wire [23:0] text_color
);
    wire [11:0] lx=x-X_ORIGIN,ly=y-Y_ORIGIN;
    wire [4:0] column=lx[8:4];reg [1:0] line;reg [3:0] font_y;
    reg area;reg [7:0] ch;reg [15:0] digits;reg show_number;reg [55:0] state_name;
    function [7:0] hex_char;
        input [3:0] n;begin hex_char=n<10?8'h30+n:8'h41+n-10;end
    endfunction
    always @(*) begin
        line=0;font_y=0;area=0;ch=" ";digits=0;show_number=0;
        if(ly<16)begin line=0;font_y=ly[3:0];area=1;end
        else if(ly>=24 && ly<40)begin line=1;font_y=ly-24;area=1;end
        else if(ly>=48 && ly<64)begin line=2;font_y=ly-48;area=1;end
        else if(ly>=72 && ly<88)begin line=3;font_y=ly-72;area=1;end
        case(status)1:state_name="LIVE   ";2:state_name="HOLD   ";3:state_name="INVALID";default:state_name="WAIT   ";endcase
        case(line)
            0:begin digits=value_bcd;show_number=history_valid && status==1;end
            1:begin digits=min_bcd;show_number=history_valid;end
            2:begin digits=max_bcd;show_number=history_valid;end
            default:begin digits=0;show_number=0;end
        endcase
        if(line<3) begin
            case(column)
                0:ch=line==0?"L":"M";
                1:ch=line==0?"A":(line==1?"I":"A");
                2:ch=line==0?"T":(line==1?"N":"X");
                3:ch=":";
                5:ch=show_number?hex_char(digits[15:12]):8'h2d;
                6:ch=show_number?hex_char(digits[11:8]):8'h2d;
                7:ch=show_number?hex_char(digits[7:4]):8'h2d;
                8:ch=".";
                9:ch=show_number?hex_char(digits[3:0]):8'h2d;
                11:ch="m";12:ch="s";
                default:if(line==0 && column>=14 && column<21)ch=state_name[55-(column-14)*8-:8];
            endcase
        end else begin
            case(column)0:ch="M";1:ch="E";2:ch="A";3:ch="S";4:ch=":";
                default:if(column>=6 && column<14)ch=history_valid?hex_char(measured_source[31-(column-6)*4-:4]):8'h2d;
            endcase
        end
    end
    reg [7:0] char_d;reg [3:0] row_d,col_d;reg allowed_d;wire [15:0] glyph;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin char_d<=0;row_d<=0;col_d<=0;allowed_d<=0;end
        else begin char_d<=ch;row_d<=font_y;col_d<=lx[3:0];allowed_d<=de && x>=X_ORIGIN && x<X_ORIGIN+336 && y>=Y_ORIGIN && area;end
    end
    osd_char_lib font(.I_char(char_d),.I_row(row_d),.O_row_bits(glyph));
    assign text_hit=allowed_d && glyph[15-col_d];assign text_color=24'h80ffff;
endmodule
