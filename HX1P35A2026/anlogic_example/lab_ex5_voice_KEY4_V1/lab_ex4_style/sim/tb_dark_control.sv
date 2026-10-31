`timescale 1ns/1ps
module tb_dark_control;
    reg clk=0,dc=0,rst=0;
    always #5 clk=~clk;always #7 dc=~dc;
    reg sof=0,v=0;reg [31:0] samples=0;
    wire mv;wire [7:0] mean,meter_highs;
    frame_meter #(.GROUPS_PER_LINE(8),.LINES(8),.X_START(2),.X_END(6),
        .Y_START(2),.Y_END(6),.X_SKIP_BITS(0),.Y_SKIP_BITS(0),.SAMPLE_GROUP_LOG2(4)) meter(
        .I_clk(clk),.I_rst_n(rst),.I_sof(sof),.I_valid(v),.I_samples(samples),.O_mean(mean),.O_highlights(meter_highs),.O_valid(mv));
    reg send=0;reg [23:0] payload=0;wire receive;wire [23:0] received;
    meter_cdc cdc(.I_src_clk(clk),.I_src_rst_n(rst),.I_valid(send),.I_data(payload),
        .I_dst_clk(dc),.I_dst_rst_n(rst),.O_valid(receive),.O_data(received));
    reg [7:0] highs=0;
    reg cfg=0,done=1,stats=0;reg [23:0] values=0;
    wire request;wire [15:0] exposure;wire [6:0] gain;
    wire [23:0] means;wire debug_valid;
    camera_auto_exposure #(.SETTLE_FRAMES(2)) ae(.I_clk(clk),.I_rst_n(rst),.I_cfg_done(cfg),
        .I_ae_done(done),.I_meter_valid(stats),.I_means(values),.I_highlights(highs),.O_req(request),
        .O_exp(exposure),.O_gain(gain),.O_means(means),.O_debug_valid(debug_valid));
    reg [30:0] gp=0;wire [30:0] go;
    base_gamma gamma(.I_clk(clk),.I_rst_n(rst),.I_pixel(gp),.O_pixel(go));
    reg [7:0] reference[0:255];
    integer i,j,x,y,nreq=0,old_requests;
    reg [15:0] old_exp;reg [6:0] old_gain;
    reg auto_ack=1;
    integer busy_ticks=0;
    always @(posedge clk) begin
        if(request) begin nreq=nreq+1;if(auto_ack) begin done<=0;busy_ticks<=4;end end
        else if(busy_ticks>0) begin busy_ticks<=busy_ticks-1;if(busy_ticks==1) done<=1;end
    end
    task tick;@(negedge clk);endtask
    task observation(input integer level);
        begin tick;values={8'(level),8'(level),8'(level)};stats=1;tick;stats=0;repeat(12) tick;end
    endtask
    task pulse_sof;
        begin tick;sof=1;tick;sof=0;end
    endtask
    initial begin
        $readmemh("gamma80.hex",reference);
        repeat(4) tick;rst=1;repeat(4) tick;
        // Meter excludes border and tolerates intra-line gaps.
        pulse_sof;
        for(y=0;y<8;y=y+1) for(x=0;x<8;x=x+1) begin
            tick;v=1;samples=(x>=2 && x<6 && y>=2 && y<6)?32'h0a141e28:32'hffffffff;
            tick;v=0;repeat((x+y)%3) tick;
        end
        tick;sof=1;@(posedge clk);#1;
        if(!mv || mean!==25) $fatal(1,"Meter ROI mean %0d valid %b",mean,mv);
        tick;sof=0;
        repeat(7) begin tick;v=1;samples=0;end
        tick;v=0;sof=1;@(posedge clk);#1;
        if(mv) $fatal(1,"Incomplete frame accepted");
        tick;sof=0;
        // One clipped sample per group is 25%, independently of average brightness.
        for(y=0;y<8;y=y+1) for(x=0;x<8;x=x+1) begin
            tick;v=1;samples=32'hff101010;
        end
        tick;v=0;sof=1;@(posedge clk);#1;
        if(!mv || meter_highs!=64 || mean!=75) $fatal(1,"Highlight fraction %0d mean %0d",meter_highs,mean);
        tick;sof=0;
        // Mailbox must preserve a coherent word despite unrelated clocks.
        for(i=0;i<32;i=i+1) begin
            tick;payload=24'h13579b^(i*24'h319);send=1;tick;send=0;
            @(posedge receive);#1;
            if(received !== payload) $fatal(1,"CDC corrupt payload");
            repeat(12) tick;
        end
        for(i=0;i<256;i=i+1) begin
            tick;gp={7'b1010100,8'(i),8'(255-i),8'(i^8'h55)};
            @(posedge clk);#1;
            if(go !== {gp[30:24],reference[i],reference[255-i],reference[i^8'h55]}) $fatal(1,"Gamma mismatch %0d",i);
        end
        tick;gp[26]=0;@(posedge clk);#1;if(go[23:0]!==0) $fatal(1,"Gamma blanking");
        // No sensor writes until initialization is complete.
        for(i=0;i<10;i=i+1) observation(0);
        if(nreq!=0) $fatal(1,"AE wrote before cfg done");
        cfg=1;
        for(i=0;i<50;i=i+1) observation(0);
        if(exposure!=3990 || gain!=64) $fatal(1,"AE failed dark limit exp=%0d gain=%0d",exposure,gain);
        old_requests=nreq;
        for(i=0;i<12;i=i+1) observation(50);
        if(nreq!=old_requests) $fatal(1,"AE hunted inside deadband");
        highs=16;old_gain=gain;
        for(i=0;i<6;i=i+1) observation(30);
        if(gain>=old_gain) $fatal(1,"AE ignored highlight clipping");
        highs=5;old_requests=nreq;
        for(i=0;i<12;i=i+1) observation(30);
        if(nreq!=old_requests) $fatal(1,"AE increased exposure inside highlight hysteresis");
        highs=0;
        for(i=0;i<150;i=i+1) observation(240);
        if(gain!=0 || exposure!=16) $fatal(1,"AE failed bright limit exp=%0d gain=%0d",exposure,gain);
        // Bright -> dark raises exposure before increasing gain.
        for(i=0;i<12;i=i+1) observation(0);
        if(exposure<=16 || gain!=0) $fatal(1,"AE exposure priority");
        // A held-busy I2C transaction cannot be overwritten by later frames.
        auto_ack=0;done=0;old_requests=nreq;old_exp=exposure;old_gain=gain;
        for(i=0;i<20;i=i+1) observation(0);
        if(nreq!=old_requests || exposure!=old_exp || gain!=old_gain) $fatal(1,"AE overwrote busy sensor transaction");
        $display("DARK PASS: ROI/gaps/incomplete frame, 32 CDC words, exhaustive gamma, AE limits/deadband/priority/busy");$finish;
    end
    initial begin #2000000;$fatal(1,"Dark control timeout");end
endmodule
