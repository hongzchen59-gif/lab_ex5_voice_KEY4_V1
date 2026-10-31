`timescale 1ns/1ps
module tb_video_latency;
    reg clk=0,rst=0;always #6.667 clk=~clk;
    reg [31:0] now_us=0,sid=0,cap=0;
    reg input_sof=0,output_sof=0,de=0,sv=1,cv=1;
    wire [1:0] status;wire history;wire [15:0] value,minimum,maximum;wire [31:0] measured;wire [19:0] elapsed;wire update;
    video_latency dut(.clk(clk),.rst_n(rst),.now_us(now_us),.input_sof(input_sof),.output_sof(output_sof),.output_de(de),
        .source_id(sid),.capture_us(cap),.source_valid(sv),.capture_valid(cv),.status(status),.history_valid(history),
        .latency_bcd(value),.min_bcd(minimum),.max_bcd(maximum),.measured_source(measured),.measured_us(elapsed),.update(update));
    integer updates=0;always @(posedge clk) if(update)updates=updates+1;
    task frame(input [31:0] id,start_time,end_time,input good_tag,good_time);
        begin
            @(negedge clk);sid=id;cap=start_time;sv=good_tag;cv=good_time;input_sof=1;
            @(negedge clk);input_sof=0;repeat(5) @(negedge clk);
            now_us=end_time;output_sof=1;de=1;@(negedge clk);output_sof=0;de=0;repeat(24) @(negedge clk);
        end
    endtask
    initial begin
        repeat(8) @(negedge clk);rst=1;
        frame(1,1000,9000,1,1);if(history || updates!=0 || status!=0)$fatal(1,"Startup identity priming");
        frame(2,2000,12234,1,1);
        if(!history || value!==16'h0102 || minimum!==16'h0102 || maximum!==16'h0102 || elapsed!=10234 || measured!=2 || updates!=1)$fatal(1,"First real latency");
        frame(2,2000,22000,1,1);if(updates!=1 || elapsed!=10234)$fatal(1,"Duplicate display counted");
        frame(3,3000,35000,1,1);if(value!==16'h0320 || maximum!==16'h0320 || minimum!==16'h0102)$fatal(1,"Maximum latency");
        frame(4,4000,9123,1,1);if(value!==16'h0051 || minimum!==16'h0051 || maximum!==16'h0320)$fatal(1,"Minimum latency");
        frame(5,32'hffffff00,32'h00002610,1,1);if(elapsed!=10000 || value!==16'h0100)$fatal(1,"Microsecond counter wrap");
        frame(5,32'hffffff00,32'h00002610+500001,1,1);if(status!=2 || updates!=4)$fatal(1,"Repeated-frame HOLD timeout");
        frame(6,100000,150000,1,0);if(status!=3 || updates!=4)$fatal(1,"Missing capture timestamp");
        frame(7,100000,160000,1,1);if(status!=0 || updates!=4)$fatal(1,"Recovery must prime identity");
        frame(8,100000,166777,1,1);if(status!=1 || value!==16'h0667 || updates!=5)$fatal(1,"Recovery valid measurement");
        frame(9,100000,1200000,1,1);if(status!=3 || updates!=5)$fatal(1,"Out-of-range timestamp accepted");
        frame(10,100000,150000,0,1);if(status!=3 || updates!=5)$fatal(1,"Invalid source tag accepted");
        frame(11,100000,160000,1,1);frame(12,100000,199999,1,1);
        if(value!==16'h0999 || minimum!==16'h0051 || maximum!==16'h0999 || updates!=6)$fatal(1,"Final counters");
        $display("LATENCY PASS: first-source priming, exact us/min/max/BCD, duplicate rejection, modulo wrap, HOLD, invalid capture/tag, resync and range bound");$finish;
    end
    initial begin #100000;$fatal(1,"Latency timeout");end
endmodule
