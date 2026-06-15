`timescale 10 ns / 1 ns

`define DATA_WIDTH 32

module alu(
	input  [`DATA_WIDTH - 1:0]  A,
	input  [`DATA_WIDTH - 1:0]  B,
	input  [              2:0]  ALUop,
	output                      Overflow,
	output                      CarryOut,
	output                      Zero,
	output [`DATA_WIDTH - 1:0]  Result
);
	// TODO: Please add your logic design here 
	wire [31:0] realB;
	wire        cin;

	assign realB = (ALUop[2] == 1'b1 || ALUop == 3'b011) ? ~B : B;
        assign cin   = (ALUop[2] == 1'b1 || ALUop == 3'b011) ? 1'b1 : 1'b0; //加法时，直接A + B + 0；减法时，需要A + ~B + 1；这里通过判断ALUop的第一位来判断进行减法还是加法

	wire [31:0] AND;
	wire [31:0]  OR;
	wire [31:0] SLT;
	wire [31:0] ADD_SUB; //可用一个结果同时表达加法/减法的运算结果
	wire [31:0] XOR; //新增的异或
	wire [31:0] NOR; //新增的同或
	wire [31:0] SLTU; //新增的无符号数比较
	wire tempcarryout; //做减法时，carryout需要取反，先定义一个中间结果，最后再根据ALUop决定是否取反

	assign AND  = A & B; 	//按位与，000
	assign OR   = A | B; 	//按位或，001
	assign SLT  = (Overflow == 0) ? (ADD_SUB[31] == 1 ? 32'b1 : 32'b0) : (ADD_SUB[31] == 1 ? 32'b0 : 32'b1);//比较有符号数，通过观察A-B的符号位实现，同时考虑Overflow是否存在，若存在需取反，111；
	assign XOR  = A ^ B; 	//按位异或，100
	assign NOR  = ~(A | B); //按位同或，101
	assign SLTU = (tempcarryout == 1'b0) ? 32'b1 : 32'b0; //无符号数比较，011

 	assign Result =
	(ALUop == 3'b000)                    ? AND :
	(ALUop == 3'b001)                    ?  OR :
	(ALUop == 3'b010 || ALUop == 3'b110) ? ADD_SUB :
	(ALUop == 3'b100)		     ? XOR :
	(ALUop == 3'b101)	 	     ? NOR :
	(ALUop == 3'b111)                    ? SLT :
	(ALUop == 3'b011)		     ? SLTU :
	32'b0;
	//用多层多目运算符实现多路选择器

	assign Overflow = 
	(ALUop[2] == 0) ? ((((~A[31] && ~B[31]) && ADD_SUB[31]) || ((A[31] && B[31]) && ~ADD_SUB[31])) ? 1'b1 : 1'b0) :
	(ALUop[2] == 1) ? ((((~A[31] && B[31]) && ADD_SUB[31])  || ((A[31] && ~B[31]) && ~ADD_SUB[31])) ? 1'b1 : 1'b0) :
	1'b0;
	//正数 + 正数 == 负数/负数 + 负数 == 正数/正数 - 负数 = 负数/负数 - 正数 = 正数，则有符号数加减法溢出

	

	assign {tempcarryout,ADD_SUB} = A + realB + {31'b0,cin};
	//拼接一个完整结果，可通过tempcarryout得出是否存在A + B < A || A + B < B || A - B > A，即无符号数加减法溢出(进位)；ADD为010，SUB为110

	assign CarryOut = 
		(ALUop[2] == 1'b0) ?  tempcarryout : 
		(ALUop[2] == 1'b1) ? ~tempcarryout :
	1'b0; //减法时需取反

	assign Zero = (Result == 32'b0); //Result是否为0

endmodule
