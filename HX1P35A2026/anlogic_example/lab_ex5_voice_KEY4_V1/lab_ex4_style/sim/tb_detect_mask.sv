`timescale 1ns/1ps
module tb_detect_mask;
    reg clk=0,rst_n=0;reg [30:0] pixel=0;
    wire start,complete,bank;wire [15:0] fid;reg [15:0] addr=0;wire [1:0] data;
    integer frame,x,y,cell_id,i,r,g,b,xx,yy;reg [1:0] expect_mask[0:31];reg [23:0] rgb;
    always #5 clk=~clk;
    detect_color_mask #(.WIDTH(32),.HEIGHT(16)) dut(.I_clk(clk),.I_rst_n(rst_n),.I_pixel(pixel),
        .O_start(start),.O_complete(complete),.O_read_bank(bank),.O_frame_id(fid),.I_read_addr(addr),.O_read_data(data));
    function [23:0] sample;
        input integer cell_id,index;
        begin case(cell_id%8)
            0:sample=24'hff0000;1:sample=24'h00ff00;2:sample=24'h0000ff;
            3:sample=24'hf0f0f0;
            4:sample=(index<8)?24'hff0000:24'h202020;
            5:sample=(index<8)?24'hff0000:24'h00ff00;
            6:sample=(index<7)?24'h0000ff:24'h202020;
            default:sample=24'h302000; // threshold V=48, chroma=48, R-G=16
        endcase end
    endfunction
    task send_frame;
        input integer malformed;
        begin
            for(y=0;y<18;y=y+1)for(x=0;x<40;x=x+1)begin
                @(negedge clk);cell_id=(y/4)*8+x/4;
                rgb=sample(cell_id,(y%4)*4+x%4);
                pixel={2'd0,1'(x==31 && y<16 && !(malformed && y==5)),1'(x==0 && y==0),1'(x<32 && y<16),2'd0,rgb};
            end
        end
    endtask
    initial begin
        for(i=0;i<32;i=i+1)case(i%8)0,4,7:expect_mask[i]=1;1:expect_mask[i]=2;2:expect_mask[i]=3;default:expect_mask[i]=0;endcase
        repeat(5)@(negedge clk);rst_n=1;
        send_frame(0);
        @(negedge clk);pixel={2'd0,1'b0,1'b1,1'b1,2'd0,24'hff0000};
        @(negedge clk);pixel=0;
        if(!complete)$fatal(1,"valid capture not complete");
        for(i=0;i<32;i=i+1)begin
            addr=i;repeat(2)@(negedge clk);
            if(data!==expect_mask[i])$fatal(1,"mask vote addr=%0d got=%0d expected=%0d",i,data,expect_mask[i]);
        end
        send_frame(1);
        @(negedge clk);pixel={2'd0,1'b0,1'b1,1'b1,2'd0,24'hff0000};
        @(negedge clk);pixel=0;
        if(complete)$fatal(1,"malformed EOL accepted");
        $display(" PASS: tb_detect_mask 4x4 votes/ties/thresholds/banks/incomplete frame");$finish;
    end
endmodule
