`timescale 10ns / 1ns

module adder (
	input  [7:0] operand0, //第一个操作数
	input  [7:0] operand1, //第二个操作数
	output [7:0] result //结果
);

	/*TODO: Please add your logic design here*/
	assign result = operand0 + operand1; //无输入进位/输出进位的加法器

endmodule
