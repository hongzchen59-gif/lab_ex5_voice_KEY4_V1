`timescale 1ns/1ps
module tb_voice_buttons;
    reg clk=0,rst_n=0,req=0,wr=0;
    always #250 clk=~clk;
    reg [3:0] keys_n=4'he;
    reg [19:0] addr=0;
    reg [31:0] wdata=0;
    wire [31:0] rdata;
    wire error,step,enabled,pwm;
    voice_peripheral #(.KEY_DEBOUNCE(4),.BUTTON_CLK_HZ(2000000),.BUTTON_DEBOUNCE_MS(2),.WORK_INIT_FILE("voice_templates.mem")) dut(
        .clk(clk),.rst_n(rst_n),.mic_sd(1'b0),.record_key_n(1'b1),.voice_keys_n(keys_n),
        .mic_sck(),.mic_ws(),.axis_step(step),.axis_dir(),.axis_en(enabled),.servo_pwm(pwm),
        .req(req),.wr(wr),.addr(addr),.wdata(wdata),.rdata(rdata),.error(error),
        .command(),.command_toggle(),.command_ack(1'b0),.track_xy(32'd0),.track_info(32'd0),
        .track_valid(1'b0),.track_update(1'b0),.track_frame(16'd0));
    defparam dut.u_axis.CLK_HZ=2000000;
    task bus(input bit write_enable,input [19:0] a,input [31:0] d,output [31:0] q);
        begin @(negedge clk);addr=a;wdata=d;wr=write_enable;req=1;
            @(posedge clk);#1;q=rdata;if(error)$fatal(1,"button MMIO error");
            @(negedge clk);req=0;wr=0;end
    endtask
    reg [31:0] q,dummy;
    integer n,held;
    initial begin
        #2000;rst_n=1;#5000000;
        bus(0,'h58,0,q);if(q!=0)$fatal(1,"boot-held VOICE generated an event");
        bus(0,'h5c,0,q);if(q!=1)$fatal(1,"boot-held key level");
        keys_n=4'hf;#5000000;
        for(n=0;n<4;n=n+1)begin keys_n[0]=0;#500000;keys_n[0]=1;#500000;end
        bus(0,'h58,0,q);if(q!=0)$fatal(1,"bounce produced event");
        keys_n[0]=0;
        @(posedge dut.button_press[0]);
        bus(1,'h58,1,dummy); // New event wins over simultaneous W1C.
        bus(0,'h58,0,q);if(q!=1)$fatal(1,"event lost on W1C collision");
        bus(1,'h58,1,dummy);#6000000;
        bus(0,'h58,0,q);if(q!=0)$fatal(1,"held key repeated");
        keys_n=4'hf;#5000000;keys_n[1]=0;#5000000;
        bus(0,'h58,0,q);if(q!=2)$fatal(1,"MODE mapping");
        bus(1,'h58,2,dummy);keys_n=4'hf;#5000000;
        bus(1,'h30,1,dummy);bus(1,'h34,32,dummy);
        @(posedge step);keys_n[2]=0;#5000000;
        if(!enabled || !dut.u_axis.status[7] || dut.u_axis.control[1])$fatal(1,"hardware STOP did not hold/manual");
        held=$signed(dut.u_axis.position);#12000000;
        if($signed(dut.u_axis.position)!=held || $signed(dut.u_axis.target)!=held)$fatal(1,"STOP motion continued");
        bus(0,'h58,0,q);if(q!=4)$fatal(1,"STOP event mapping");
        bus(1,'h58,4,dummy);bus(1,'h30,3,dummy);
        if(dut.u_axis.control[1])$fatal(1,"held STOP allowed follow enable");
        keys_n=4'hf;#5000000;
        if(!dut.u_axis.status[7])$fatal(1,"STOP released without explicit re-arm");
        bus(1,'h30,3,dummy);if(dut.u_axis.status[7] || !dut.u_axis.control[1])$fatal(1,"explicit re-arm failed");
        keys_n[3]=0;#5000000;
        if(enabled || step || pwm)$fatal(1,"hardware DISABLE did not cut outputs");
        bus(1,'h30,3,dummy);if(enabled)$fatal(1,"held DISABLE allowed enable");
        bus(0,'h58,0,q);if(q!=8)$fatal(1,"DISABLE event mapping");
        bus(1,'h58,8,dummy);keys_n=4'hf;#5000000;
        bus(1,'h30,1,dummy);if(!enabled || dut.u_axis.status[7])$fatal(1,"manual enable after disable");
        keys_n=4'h3;#5000000;
        if(enabled || step || pwm)$fatal(1,"DISABLE must dominate simultaneous STOP");
        $display("VOICE EXTRA PASS: buttons boot-held/bounce/event/W1C, MODE mapping, CPU-independent STOP/DISABLE and explicit re-arm");
        $finish;
    end
    initial begin #150000000;$fatal(1,"button test timeout");end
endmodule
