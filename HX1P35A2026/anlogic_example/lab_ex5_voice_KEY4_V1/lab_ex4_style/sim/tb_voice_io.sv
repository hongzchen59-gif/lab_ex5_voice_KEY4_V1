`timescale 1ns/1ps
module tb_voice_io;
    reg clk=0,hclk=0,pclk=0,rst_n=0;
    always #10 clk=~clk;
    always #3.333 hclk=~hclk;
    always #6.667 pclk=~pclk;
    reg sd=0;wire sck,ws,ready,valid;wire signed [15:0] pcm;
    voice_i2s_rx #(.WARMUP(10000)) rx(.clk(clk),.rst_n(rst_n),.sd(sd),
        .sck(sck),.ws(ws),.ready(ready),.valid(valid),.pcm(pcm));
    reg previous_ws=0;integer pos=0,frame=0,audio_checked=0;
    reg [23:0] word=24'h123456;
    always @(negedge sck) begin
        #1;
        if(ws!=previous_ws) begin
            pos=0;
            if(!ws) begin frame=frame+1;word=frame[0]?24'hfedcba:24'h123456;end
        end else pos=pos+1;
        previous_ws=ws;
        if(!ws && pos>=1 && pos<=24) sd=word[24-pos];
        else sd=1'bx;
    end
    always @(posedge clk) begin
        #1;
        if(valid) begin
            if(pcm!==word[23:8]) $fatal(1,"I2S sign/one-bit/slot alignment: %h expected %h",pcm,word[23:8]);
            audio_checked=audio_checked+1;
        end
    end
    reg [1:0] htrans=0;reg hwrite=0;reg [30:0] haddr=0;
    reg [2:0] hsize=2;reg [31:0] hwdata=0;
    wire hready;wire [1:0] hresp;wire [31:0] hrdata;
    wire req,wr,error;wire [19:0] addr;wire [31:0] wdata,rdata;
    voice_ahb_bridge bridge(.hclk(hclk),.hreset_n(rst_n),.htrans(htrans),
        .hwrite(hwrite),.haddr(haddr),.hsize(hsize),.hwdata(hwdata),
        .hready(hready),.hresp(hresp),.hrdata(hrdata),.clk(clk),.reset_n(rst_n),
        .req(req),.wr(wr),.addr(addr),.wdata(wdata),.rdata(rdata),.error(error));
    wire [31:0] command;wire ct,ca;wire [31:0] xy,info;wire [63:0] telemetry;
    wire [15:0] result_frame;
    reg record_key_n=1;
    voice_peripheral #(.KEY_DEBOUNCE(16),.WORK_INIT_FILE("voice_templates.mem")) peripheral(.clk(clk),.rst_n(rst_n),.mic_sd(1'b0),.record_key_n(record_key_n),
        .voice_keys_n(4'hf),
        .mic_sck(),.mic_ws(),.req(req),.wr(wr),.addr(addr),.wdata(wdata),
        .axis_step(),.axis_dir(),.axis_en(),.servo_pwm(),
        .rdata(rdata),.error(error),.command(command),.command_toggle(ct),.command_ack(ca),
        .track_xy(xy),.track_info(info),.track_valid(1'b1),.track_update(1'b1),.track_frame(result_frame));
    defparam peripheral.u_rx.HALF_DIV=2;
    defparam peripheral.u_rx.WARMUP=10;
    reg [319:0] objects=0;reg [15:0] frame_id=0;reg [1:0] status=1;reg [2:0] count=1;
    voice_target_select selector(.clk(pclk),.rst_n(rst_n),.command(command),
        .command_toggle(ct),.command_ack(ca),.status(status),.count(count),
        .objects(objects),.frame_id(frame_id),.xy(xy),.info(info),.result_frame_id(result_frame));
    task bus(input bit write_enable,input [30:0] address,input [31:0] value,output [31:0] result);
        integer timeout;
        begin
            @(negedge hclk);htrans=2;hwrite=write_enable;haddr=address;hwdata=32'hbad0bad0;
            @(posedge hclk);#1;
            @(negedge hclk);htrans=0;hwdata=value;
            timeout=0;
            while(!hready && timeout<100) begin @(negedge hclk);timeout=timeout+1;end
            if(timeout==100) $fatal(1,"AHB response timeout");
            if(hresp!=0) $fatal(1,"unexpected AHB error at %h",address);
            result=hrdata;@(negedge hclk);
        end
    endtask
    task next_frame;
        begin @(negedge pclk);frame_id=frame_id+1;repeat(25) @(negedge pclk);end
    endtask
    reg [31:0] result;integer n;
    initial begin
        #100;rst_n=1;repeat(30) @(negedge clk);
        bus(0,0,0,result);if(result!==32'h564f4938)$fatal(1,"ID");
        bus(0,20'h4c,0,result);if(result!==32'h41584931)$fatal(1,"axis capability");
        bus(0,20'h40,0,result);if(result!==0)$fatal(1,"axis reset disabled");
        bus(1,20'h30,1,result);bus(0,20'h40,0,result);if(!result[0])$fatal(1,"axis enable via AHB");
        bus(1,20'h34,32'hfffffff8,result);bus(0,20'h34,0,result);if(result!==32'hfffffff8)$fatal(1,"signed axis target via AHB");
        bus(1,20'h38,20,result);bus(0,20'h38,0,result);if(result!==1520)$fatal(1,"servo target via AHB");
        bus(1,20'h34,32'h7fffffff,result);bus(0,20'h34,0,result);if(result!==1024)$fatal(1,"production positive pan clamp");
        bus(1,20'h34,32'h80000000,result);bus(0,20'h34,0,result);if($signed(result)!==-1024)$fatal(1,"production negative pan clamp");
        bus(1,20'h38,32'h7fffffff,result);bus(0,20'h38,0,result);if(result!==2000)$fatal(1,"production servo upper clamp");
        bus(1,20'h38,32'h80000000,result);bus(0,20'h38,0,result);if(result!==1000)$fatal(1,"production servo lower clamp");
        bus(1,20'h30,0,result);bus(0,20'h40,0,result);if(result[0])$fatal(1,"axis disarm via AHB");
        bus(0,4,0,result);if(result!==15625)$fatal(1,"sample-rate register");
        record_key_n=0;repeat(25) @(negedge clk);
        bus(0,20'h0c,0,result);if(!result[6])$fatal(1,"record key debounce");
        record_key_n=1;repeat(25) @(negedge clk);
        bus(0,20'h0c,0,result);if(result[6])$fatal(1,"record key release");
        // Distinct address/data phase patterns across a non-integer clock ratio.
        for(n=0;n<40;n=n+1) begin
            bus(1,20'h10000+4*n,32'hcaf00000+n,result);
            bus(0,20'h10000+4*n,0,result);
            if(result!==32'hcaf00000+n)$fatal(1,"AHB phase or RAM address %d",n);
        end
        objects[10:0]=100;objects[21:11]=199;objects[31:22]=200;objects[41:32]=299;
        objects[43:42]=1;objects[45:44]=1;
        bus(1,20'h20,32'h00010101,result);repeat(20) @(negedge pclk);
        if(info[7:0]!=1 || info[8])$fatal(1,"command commit or stale selection");
        next_frame();next_frame();if(info[8])$fatal(1,"old pipeline result accepted");
        next_frame();if(!info[8] || xy!={16'd249,16'd149})$fatal(1,"target coordinates");
        if(result_frame!==frame_id)$fatal(1,"result frame must commit with coordinates");
        @(negedge pclk);frame_id=frame_id+1;
        repeat(5)@(negedge pclk);
        if(!info[8] || xy!={16'd249,16'd149} || result_frame!==frame_id-16'd1)
            $fatal(1,"in-progress selection published a transient invalid packet");
        repeat(20)@(negedge pclk);
        if(!info[8] || result_frame!==frame_id)$fatal(1,"next valid frame did not commit");
        count=0;next_frame();
        if(info[8] || xy!=0 || result_frame!==frame_id)$fatal(1,"committed empty frame must clear target");
        count=1;next_frame();
        if(!info[8])$fatal(1,"valid result must recover after empty frame");
        status=2;repeat(3) @(negedge pclk);
        if(info[8] || xy!=0)$fatal(1,"invalid detector result retained");
        status=1;next_frame();
        // Wide enough to catch accidental width truncation in the 8*w test.
        objects[10:0]=100;objects[21:11]=699;objects[31:22]=10;objects[41:32]=609;
        objects[43:42]=3;objects[45:44]=3;
        bus(1,20'h20,32'h00040301,result);repeat(20) @(negedge pclk);
        next_frame();next_frame();next_frame();
        if(!info[8] || xy!={16'd309,16'd399})$fatal(1,"large square geometry");
        objects[41:32]=309;next_frame();
        if(info[8])$fatal(1,"rectangle accepted as square");
        bus(1,20'h20,32'h00000002,result);repeat(20) @(negedge pclk);
        if(info[8] || xy!=0 || info[7:0]!=2)$fatal(1,"STOP must clear target");
        bus(1,20'h8,1,result);
        // Force CPU starvation: first full bank must remain immutable and next
        // wrap must stop capture, not overwrite the unread buffer.
        repeat(550000) @(negedge clk);
        bus(0,20'h0c,0,result);
        if(!result[4] || result[1] || result[3:2]!=3)$fatal(1,"overflow/backpressure %h",result);
        bus(0,20'h10,0,result);if(result!==2048)$fatal(1,"sample count on overflow");
        bus(1,20'h8,1,result);bus(0,20'h0c,0,result);
        if(result[4] || !result[1] || result[3:2]!=0)$fatal(1,"record restart");
        // Illegal accesses must receive the required two-cycle AHB error.
        @(negedge hclk);htrans=2;hsize=1;haddr=0;
        @(negedge hclk);htrans=0;
        @(negedge hclk);
        if(hresp!=1 || hready)$fatal(1,"AHB first error cycle");
        @(negedge hclk);if(hresp!=1 || !hready)$fatal(1,"AHB second error cycle");
        hsize=2;@(negedge hclk);
        rst_n=0;repeat(10) @(negedge clk);rst_n=1;
        repeat(30) @(negedge clk);
        bus(0,0,0,result);if(result!==32'h564f4938)$fatal(1,"AHB reset recovery");
        if(audio_checked<8)$fatal(1,"too few I2S samples");
        $display("VOICE IO PASS: I2S signed 24/32 slots, AHB CDC/data phase, work RAM, target epoch/STOP, overflow/restart/error; audio=%0d",audio_checked);
        $finish;
    end
    initial begin #20000000;$fatal(1,"test timeout");end
endmodule

