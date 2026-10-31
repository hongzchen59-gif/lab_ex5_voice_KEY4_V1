`timescale 1ns/1ps
module tb_voice_preset;
    reg clk=0,rst_n=0,req=0,wr=0;
    always #10 clk=~clk;
    reg [19:0] addr=0;
    reg [31:0] wdata=0;
    wire [31:0] rdata;
    wire error;
    voice_peripheral #(.WORK_INIT_FILE("voice_templates.mem")) dut(.clk(clk),.rst_n(rst_n),.mic_sd(1'b0),.record_key_n(1'b1),.voice_keys_n(4'hf),
        .mic_sck(),.mic_ws(),.axis_step(),.axis_dir(),.axis_en(),.servo_pwm(),
        .req(req),.wr(wr),.addr(addr),.wdata(wdata),.rdata(rdata),.error(error),
        .command(),.command_toggle(),.command_ack(1'b0),.track_xy(32'd0),.track_info(32'd0),
        .track_valid(1'b0),.track_update(1'b0),.track_frame(16'd0));
    task bus(input bit write_enable,input [19:0] a,input [31:0] d,output [31:0] q);
        begin @(negedge clk);addr=a;wdata=d;wr=write_enable;req=1;
            @(posedge clk);#1;q=rdata;if(error)$fatal(1,"preset MMIO error");
            @(negedge clk);req=0;wr=0;end
    endtask
    function [31:0] crc_word(input [31:0] seed,input [31:0] word);
        reg [31:0] c,w;integer b,k;
        begin c=seed;w=word;
            for(b=0;b<4;b=b+1)begin c=c^(w&255);w=w>>8;
                for(k=0;k<8;k=k+1)c=(c>>1)^((c&1)?32'hedb88320:0);
            end crc_word=c;
        end
    endfunction
    reg [31:0] h[0:15],q,c,first_word,dummy;
    integer i;
    initial begin
        #100;rst_n=1;
        for(i=0;i<16;i=i+1)bus(0,'h1bc00+i*4,0,h[i]);
        if(h[0]!='h5654504c || h[2]!=15625 || h[3]!=13 || h[4]!=7800 || h[12]!=31200)$fatal(1,"preset metadata");
        if(h[5]!=131 || h[6]!=134 || h[7]!=84 || h[8]!=106 || h[9]!=500 || h[10]!=20)$fatal(1,"real enrollment metadata");
        c='1;for(i=0;i<15;i=i+1)c=crc_word(c,h[i]);
        if((c^32'hffffffff)!=h[15] || h[15]!=32'h4ebcb7dc)$fatal(1,"header CRC");
        c='1;
        for(i=0;i<7800;i=i+1)begin bus(0,'h10000+i*4,0,q);c=crc_word(c,q);end
        if((c^32'hffffffff)!=h[11] || h[11]!=32'h0520e68a)$fatal(1,"real feature payload CRC");
        bus(0,'h10000,0,first_word);bus(1,'h179e0,32'hfedcba98,dummy);
        bus(1,'h1bffc,32'h1234abcd,dummy);
        rst_n=0;#100;rst_n=1;
        bus(0,'h10000,0,q);if(q!=first_word)$fatal(1,"scratch/query/CPU reset changed template");
        bus(0,'h1bc3c,0,q);if(q!=h[15])$fatal(1,"header changed on reset");
        bus(1,'h1bc24,501,dummy);c='1;
        for(i=0;i<15;i=i+1)begin bus(0,'h1bc00+i*4,0,q);c=crc_word(c,q);end
        if((c^32'hffffffff)==h[15])$fatal(1,"metadata corruption went undetected");
        bus(1,'h10000,first_word^1,dummy);c='1;
        for(i=0;i<7800;i=i+1)begin bus(0,'h10000+i*4,0,q);c=crc_word(c,q);end
        if((c^32'hffffffff)==h[11])$fatal(1,"payload corruption went undetected");
        $display("VOICE EXTRA PASS: real template initialization/header/payload CRC, query/scratch isolation, reset retention and corruption detection");
        $finish;
    end
    initial begin #2000000;$fatal(1,"preset test timeout");end
endmodule
