`timescale 1ns/1ps
module tb_detect_components;
    `include "detect_cases.vh"
    reg clk=0,rst_n=0,start=0,complete=1;
    reg [15:0] frame_id=0;
    wire [15:0] addr;
    reg [1:0] data;
    reg [1:0] masks[0:CASES*57600-1];
    reg [327:0] expected[0:CASES-1];
    wire [1:0] status;wire [2:0] count;wire [319:0] objects;wire [15:0] fid;wire busy;wire [19:0] cycles;
    integer case_id=0,elapsed,i,j,match_count,max_cycles=0,used;
    reg [79:0] got,want;
    always #5 clk=~clk;
    always @(posedge clk)data<=masks[case_id*57600+addr];
    detect_components dut(.I_clk(clk),.I_rst_n(rst_n),.I_start(start),.I_complete(complete),.I_frame_id(frame_id),
        .O_read_addr(addr),.I_read_data(data),.O_status(status),.O_count(count),.O_objects(objects),.O_frame_id(fid),.O_busy(busy),.O_cycles(cycles));
    initial begin
        $readmemh("detect_masks.hex",masks);$readmemh("detect_expected.hex",expected);
        repeat(5)@(negedge clk);rst_n=1;
        for(case_id=0;case_id<CASES;case_id=case_id+1)begin
            @(negedge clk);start=1;frame_id=case_id+1;@(negedge clk);start=0;elapsed=0;
            while(busy && elapsed<1000100)begin @(negedge clk);elapsed=elapsed+1;end
            if(busy || status!==expected[case_id][324:323] || count!==expected[case_id][322:320] || fid!==case_id+1)
                $fatal(1,"case %0d status=%0d count=%0d cycles=%0d expected=%0h",case_id,status,count,cycles,expected[case_id][327:320]);
            used=0;
            for(i=0;i<4;i=i+1)begin
                got=objects[i*80 +:80];match_count=0;
                for(j=0;j<4;j=j+1)begin
                    want=expected[case_id][j*80 +:80];
                    if(got===want)match_count=match_count+1;
                end
                if(match_count==0)$fatal(1,"case %0d slot %0d got=%020h not in expected=%080h",case_id,i,got,expected[case_id][319:0]);
                if(got!=0)used=used+1;
            end
            if(used!=(count>4?4:count))$fatal(1,"case %0d object count mismatch",case_id);
            if(cycles>max_cycles)max_cycles=cycles;
            $display("DETECT case %0d PASS status=%0d count=%0d cycles=%0d",case_id,status,count,cycles);
        end
        // Deadline and a new frame must abort old work and clear old boxes.
        case_id=0;@(negedge clk);start=1;@(negedge clk);start=0;repeat(50)@(negedge clk);
        complete=0;start=1;@(negedge clk);start=0;
        if(busy || status!=2 || objects!=0 || count!=0)$fatal(1,"new-frame abort failed");
        @(negedge clk);start=1;@(negedge clk);start=0;
        if(status!=0 || objects!=0)$fatal(1,"incomplete frame must publish WAIT");
        $display(" PASS: tb_detect_components %0d cases BFS geometry/class/BCD/multiple targets, max_cycles=%0d",CASES,max_cycles);$finish;
    end
endmodule

