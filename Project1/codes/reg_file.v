`timescale 10 ns / 1 ns

`define DATA_WIDTH 32
`define ADDR_WIDTH 5

module reg_file(
	input                       clk, //时钟周期
	input  [`ADDR_WIDTH - 1:0]  waddr, //写地址
	input  [`ADDR_WIDTH - 1:0]  raddr1, //一号端口读地址
	input  [`ADDR_WIDTH - 1:0]  raddr2, //二号端口读地址
	input                       wen, //写使能信号
	input  [`DATA_WIDTH - 1:0]  wdata, //写入的数据
	output [`DATA_WIDTH - 1:0]  rdata1, //一号端口读出数据
	output [`DATA_WIDTH - 1:0]  rdata2 //二号端口读出数据
);

	// TODO: Please add your logic design here
	reg [31:0] data [0:31]; //32*32 寄存器堆，即有32个元素，每个元素为32位向量的数组
	always@(posedge clk) begin
		if(wen == 1'b1)begin //写使能，同步信号
			if(waddr != 32'b0)begin //不能写入0号寄存器
				data[waddr] <= wdata; //写入寄存器
			end
		end
	end
	assign rdata1 = (raddr1 == 32'b0) ? 32'b0 : data[raddr1]; //0号寄存器必须读出0
	assign rdata2 = (raddr2 == 32'b0) ? 32'b0 : data[raddr2];
	
endmodule
