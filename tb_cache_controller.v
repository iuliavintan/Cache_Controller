`timescale 1ns/1ps

module tb_cache_controller;

    reg clk;
    reg reset;
    reg read;
    reg write;
    reg [31:0] address;
    reg [63:0] write_data;
    wire [63:0] read_data;
    wire hit;
    wire miss;

    cache_controller uut (
        .clk(clk),
        .reset(reset),
        .read(read),
        .write(write),
        .address(address),
        .write_data(write_data),
        .read_data(read_data),
        .hit(hit),
        .miss(miss)
    );
   
  	 initial begin
		$dumpfile("dump.vcd");
		$dumpvars(0, tb_cache_controller);
    	clk=0;
    end

    always begin
      #5;
      clk=~clk;
    end

  
    initial begin
      
      reset = 1;
      read = 0;
      write = 0;
      address = 0;
      write_data = 0;
      #20;
      
      reset = 0;
      //case 1: read miss
      read = 1;
      address = 32'h00002000;
      #50;
      read=0;
      #20;
      // case 2: write miss
      #10;
      read = 0;
      #10;
      write = 1;
      address = 32'h00001000;
      write_data = 64'h12345678ABCDEF22;

      // case 3: read hit from the same address
      #50;
      write = 0;
      #30;
      read = 1;
      address = 32'h00001000;
      #30;
      read = 0;
      #30;
      
      // case 4: write hit
      write = 1;
      address = 32'h00001000;
      write_data = 64'h12345678ABCDEF11;
      #30;
      write = 0;

      #50;
      
      $finish;
    end

    // Monitor signals
    initial begin
      $monitor("Time=%0t | read=%b write=%b addr=0x%08h data_in=0x%016h hit=%b miss=%b data_out=%h",$time, read, write, address, write_data, hit, miss, read_data);
    end

endmodule