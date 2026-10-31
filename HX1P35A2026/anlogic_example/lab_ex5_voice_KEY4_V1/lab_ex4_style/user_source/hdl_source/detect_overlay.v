// One character lookup shared by the header and four fixed result rows.
module detect_overlay #(parameter integer PIPELINED=0)(
    input wire I_clk,I_rst_n,
    input wire [11:0] I_x,I_y,input wire I_de,I_enable,
    input wire [1:0] I_status,input wire [2:0] I_count,
    input wire [319:0] I_objects,
    output wire O_text_hit,output wire [23:0] O_text_color,
    output wire O_box_hit,output wire [23:0] O_box_color
);
    reg [23:0] text_color,box_color;
    reg box_hit;
    integer n;
    reg [79:0] box;
    wire [11:0] lx=I_x-12'd704,ly=I_y-12'd16;
    reg [2:0] row;
    reg [3:0] font_y;
    reg text_area;
    wire [4:0] column=lx[8:4];
    reg [7:0] ch;
    reg [79:0] object;
    reg [39:0] color_name;
    reg [63:0] shape_name,status_name;
    reg [15:0] xb,yb;
    function [23:0] rgb;
        input [1:0] col;
        begin case(col)1:rgb=24'hff4040;2:rgb=24'h40ff60;3:rgb=24'h4080ff;default:rgb=24'hffffff;endcase end
    endfunction
    always @(*) begin
        box_hit=0;box_color=0;box=0;
        for(n=0;n<4;n=n+1)begin
            box=I_objects[n*80 +:80];
            if(I_enable && I_de && I_status==1 && box[43:42]!=0 && I_x>=box[10:0] && I_x<=box[21:11] &&
               I_y>=box[31:22] && I_y<=box[41:32] &&
               (I_x<box[10:0]+2 || I_x+2>box[21:11] || I_y<box[31:22]+2 || I_y+2>box[41:32]))begin
                box_hit=1;box_color=rgb(box[43:42]);
            end
        end
        row=0;font_y=0;text_area=0;object=0;xb=0;yb=0;
        if(ly<16)begin row=0;font_y=ly[3:0];text_area=1;end
        else if(ly>=24 && ly<40)begin row=1;font_y=ly-24;text_area=1;end
        else if(ly>=48 && ly<64)begin row=2;font_y=ly-48;text_area=1;end
        else if(ly>=72 && ly<88)begin row=3;font_y=ly-72;text_area=1;end
        else if(ly>=96 && ly<112)begin row=4;font_y=ly-96;text_area=1;end
        case(row)
            1:object=I_objects[79:0];2:object=I_objects[159:80];
            3:object=I_objects[239:160];4:object=I_objects[319:240];default:object=0;
        endcase
        case(object[43:42])1:color_name="RED  ";2:color_name="GREEN";3:color_name="BLUE ";default:color_name="     ";endcase
        case(object[45:44])1:shape_name="CIRCLE  ";2:shape_name="TRIANGLE";3:shape_name="RECT    ";default:shape_name="UNKNOWN ";endcase
        case(I_status)1:status_name="RUN     ";2:status_name="OVERFLOW";default:status_name="WAIT    ";endcase
        xb=object[61:46];yb=object[77:62];ch=8'h20;
        text_color=(row==0)?24'hfff200:rgb(object[43:42]);
        if(row==0)begin
            case(column)
                0:ch="D";1:ch="E";2:ch="T";3:ch="E";4:ch="C";5:ch="T";
                8:ch="C";9:ch="O";10:ch="U";11:ch="N";12:ch="T";13:ch=":";
                14:ch=(I_status==1)?(I_count>4?8'h34:8'h30+I_count):8'h2d;
                15:ch=(I_status!=1)?8'h2d:(I_count>4?8'h2b:8'h20);
                default:if(column>=18 && column<26)ch=status_name[63-(column-18)*8 -:8];
            endcase
        end else if(I_status==1 && object[43:42]!=0)begin
            case(column)
                0:ch=8'h30+row;
                17:ch="X";18:ch=":";19:ch=8'h30+xb[15:12];20:ch=8'h30+xb[11:8];21:ch=8'h30+xb[7:4];22:ch=8'h30+xb[3:0];
                24:ch="Y";25:ch=":";26:ch=8'h30+yb[15:12];27:ch=8'h30+yb[11:8];28:ch=8'h30+yb[7:4];29:ch=8'h30+yb[3:0];
                default:begin
                    if(column>=2 && column<7)ch=color_name[39-(column-2)*8 -:8];
                    if(column>=8 && column<16)ch=shape_name[63-(column-8)*8 -:8];
                end
            endcase
        end
    end
    wire allowed=I_enable && I_de && I_x>=704 && I_x<1216 && I_y>=16 && text_area;
    generate if(PIPELINED)begin: g_pipe
        reg [7:0] ch_d;
        reg [3:0] row_d,col_d;
        reg allowed_d,box_d;
        reg [23:0] text_color_d,box_color_d;
        wire [15:0] bits_d;
        always @(posedge I_clk or negedge I_rst_n)begin
            if(!I_rst_n)begin ch_d<=0;row_d<=0;col_d<=0;allowed_d<=0;box_d<=0;text_color_d<=0;box_color_d<=0;end
            else begin ch_d<=ch;row_d<=font_y;col_d<=lx[3:0];allowed_d<=allowed;box_d<=box_hit;text_color_d<=text_color;box_color_d<=box_color;end
        end
        osd_char_lib font(.I_char(ch_d),.I_row(row_d),.O_row_bits(bits_d));
        assign O_text_hit=allowed_d && bits_d[15-col_d];
        assign O_text_color=text_color_d;
        assign O_box_hit=box_d;assign O_box_color=box_color_d;
    end else begin: g_comb
        wire [15:0] bits_c;
        osd_char_lib font(.I_char(ch),.I_row(font_y),.O_row_bits(bits_c));
        assign O_text_hit=allowed && bits_c[15-lx[3:0]];
        assign O_text_color=text_color;
        assign O_box_hit=box_hit;assign O_box_color=box_color;
    end endgenerate
endmodule
