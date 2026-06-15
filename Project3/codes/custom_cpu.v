`timescale 10ns / 1ns

module custom_cpu(
	input         		clk,			//时钟周期
	input         		rst,			//复位信号

	//Instruction request channel
	output [31:0] 		PC,			//程序计数器
	output        		Inst_Req_Valid,		//访存请求
	input         		Inst_Req_Ready,		//取指进入指令等待

	//Instruction response channel
	input  [31:0] 		Instruction,		//32位指令
	input         		Inst_Valid,		//指令等待进入译码
	output        		Inst_Ready,		//指令接受信号

	//Memory request channel
	output [31:0]		Address,		//访存地址
	output       		MemWrite,		//内存写使能
	output [31:0] 		Write_data,		//内存写数据
	output [ 3:0] 		Write_strb,		//内存写字节控制
	output       		MemRead,		//内存读使能
	input         		Mem_Req_Ready,		//内存写进入取指

	//Memory data response channel
	input  [31:0] 		Read_data,		//内存读取数据
	input         		Read_data_Valid,	//读数据等待进入写回
	output       		Read_data_Ready,	//内存读进入读数据等待

	input         		intr,

	output [31:0] 		cpu_perf_cnt_0,		//周期计数
	output [31:0] 		cpu_perf_cnt_1,
	output [31:0] 		cpu_perf_cnt_2,
	output [31:0] 		cpu_perf_cnt_3,
	output [31:0] 		cpu_perf_cnt_4,
	output [31:0] 		cpu_perf_cnt_5,
	output [31:0] 		cpu_perf_cnt_6,
	output [31:0] 		cpu_perf_cnt_7,
	output [31:0] 		cpu_perf_cnt_8,
	output [31:0] 		cpu_perf_cnt_9,
	output [31:0] 		cpu_perf_cnt_10,
	output [31:0] 		cpu_perf_cnt_11,
	output [31:0] 		cpu_perf_cnt_12,
	output [31:0] 		cpu_perf_cnt_13,
	output [31:0] 		cpu_perf_cnt_14,
	output [31:0] 		cpu_perf_cnt_15,

	output [69:0] 		inst_retire
);

/* The following signal is leveraged for behavioral simulation, 
* which is delivered to testbench.
*
* STUDENTS MUST CONTROL LOGICAL BEHAVIORS of THIS SIGNAL.
*
* inst_retired (70-bit): detailed information of the retired instruction,
* mainly including (in order) 
* { 
*   reg_file write-back enable  (69:69,  1-bit),
*   reg_file write-back address (68:64,  5-bit), 
*   reg_file write-back data    (63:32, 32-bit),  
*   retired PC                  (31: 0, 32-bit)
* }
*
*/

// TODO: Please add your custom CPU code here

	//多周期中间寄存器堆
	reg  [31:0]		IR;		  //指令寄存器
	reg  [31:0]		MDR;		  //内存数据寄存器
	reg  [31:0]		A;		  //寄存器堆rs读出
	reg  [31:0]		B;		  //寄存器堆rt读出
	reg  [31:0]		ALUOut;		  //ALU运算结果
	reg  [31:0] 		BranchTarget;	  //分值计算结果
	reg  [31:0] 		PC4_temp; 	  //用于锁存当前指令的下一条地址(PC+4)

	//指令相关
	wire [5:0] 		opcode; 	  //指令31-26位
	wire [4:0] 		rs; 		  //指令25-21位
	wire [4:0] 		rt; 		  //指令20-16位
	wire [4:0] 		rd; 		  //指令15-11位
	wire [4:0] 		shmat; 		  //指令10-6位
	wire [5:0] 		func; 		  //指令5-0位

	wire [15:0]		immediate;	  //I-type指令15-0位

	wire [25:0]		instr_index;      //J-type指令26-0位

	wire [31:0]		se_immediate;	  //符号位扩展后的立即数
	wire [31:0]		zo_immediate;	  //零扩展后的立即数
	wire [31:0]		lm_immediate;	  //左移16位后的立即数

	wire [15:0]		offset;		  //I-type分支/内存读/内存写/REGIMM指令15-0位
	wire [17:0]		target_offset;	  //I-type分支offset左移2位
	wire [31:0]		se_target_offset; //I-type分支扩展后的offset
	wire [31:0]		se_offset;	  //I-type内存读写offset部分符号位扩展

	wire [4:0]		base;		  //I-type内存读写指令25-21位


	assign			opcode		=	IR[31:26];
	assign			rs		=	IR[25:21];
	assign			rt		=	IR[20:16];
	assign			rd		=	IR[15:11];
	assign			shmat		=	IR[10:6];
	assign			func		=	IR[5:0];

	assign			immediate	=	IR[15:0];

	assign			instr_index	=	IR[25:0];

	assign			se_immediate	=	{{16{immediate[15]}},immediate}; 	//符号位扩展
	assign			zo_immediate	=	{{16{1'b0}},immediate};		 	//零扩展
	assign			lm_immediate	=	{immediate,{16{1'b0}}};		 	//左移16位

	assign			offset		=	IR[15:0];
	assign			target_offset	=	{offset,{2{1'b0}}};		 	 //左移2位
	assign			se_target_offset=	{{14{target_offset[17]}},target_offset}; //符号位扩展
	assign			se_offset	=	{{16{offset[15]}},offset};	 	 //符号位扩展

	assign			base		=	IR[25:21];

	//译码相关
	wire 			isRtype;	//R-type
	wire			isItypec;	//I-type计算
	wire			isItypel;	//I-type内存读
	wire			isItypes;	//I-type内存写
	wire			isItypeb;	//I-type分支
	wire			isREGIMM;	//REGIMM
	wire			islui;		//lui
	wire			isItypecnl;	//I-type非逻辑计算
	wire			isItypecl;	//I-type逻辑计算
	wire			islwlr;		//lwl/lwr
	wire			isj;		//j指令
	wire			isjr;		//jr指令
	wire			isjal;		//jal指令
	wire			isjalr;		//jalr指令
	wire			ismov;		//位移指令
	wire			isshift;	//位移指令
	wire			isnop;		//空指令

	assign			isRtype		=	(opcode == 6'b000000);
	assign			isREGIMM	=	(opcode == 6'b000001);
	assign			isItypeb	=	(opcode[5:2] == 4'b0001);
	assign			isItypec 	= 	(opcode[5:3] == 3'b001) && !islui;
	assign			isItypel	=	(opcode[5] & (~opcode[3]));
	assign			isItypes	=	(opcode[5] & opcode[3]);
	assign			islui		=	(opcode == 6'b001111);
	assign			isItypecnl	=	(opcode[5:2] == 4'b0010);
	assign			isItypecl	=	(opcode[5:2] == 4'b0011);
	assign			islwlr		=	(opcode == 6'b100010 || opcode == 6'b100110);
	assign			isj		=	opcode == 6'b000010;
	assign			isjr		=	(isRtype) && (func == 6'b001000);
	assign			isjalr		=	(isRtype) && (func == 6'b001001);	
	assign			isjal		=	opcode == 6'b000011;
	assign			ismov		=	((isRtype && func == 6'b001011) || (isRtype && func == 6'b001010));
	assign			isshift		=	((isRtype) &&(func[5:3] == 3'b000));
	assign			isnop		=	IR == 32'b0;

	wire 			movn;		//movn使能
	wire 			movz;		//movz使能
	wire [31:0]		alu_result;	//alu运算结果
	wire [31:0]		RF_rdata1;	//寄存器堆一号端口读出
	wire [31:0]		RF_rdata2;	//寄存器堆二号端口读出


	//多周期处理器新增变量
	wire			RF_wen;		//寄存器堆写使能
	wire			IRWrite;	//IR写使能,1写入
	wire			PCWrite;	//PC更新使能，1写入
	wire			PCWriteCond;	//PC条件更新使能，1写入，若ALUZero为1
	wire			RegWrite;	//寄存器堆写使能，1写入
	wire			MemWrite_reg;	//内存写使能，1写入
	wire			MemRead_reg;	//内存读使能，1读出
	wire			ALUSrcA;	//ALU第一个操作数选择，0为PC，1为寄存器A
	wire [1:0]		ALUSrcB;	//ALU第二个操作数选择，00为B，01为4，10为符号位扩展立即数，11为左移符号位扩展立即数
	wire [1:0]		RegDst;		//寄存器堆写入，00写入rt，01写入rd,10写入31号寄存器
	wire [1:0]		MemtoReg;	//寄存器堆写入端口，00写ALUOut，01写MDR,10写PC+4/PC+8,11条件移动
	wire [1:0]		topALUop;	//ALUop，00加法，01减法，10根据func决定
	wire [1:0]		PCSource;	//PC接收数据，00PC+4，01分支，10跳转，11A
	wire 			UseLui;		//是否为Lui指令
	wire			UseShift;	//是否为移位指令

	//多周期处理器状态机
	localparam 		INIT= 9'b000000001,	//初始状态
				IF  = 9'b000000010,	//取指
				IW  = 9'b000000100,	//指令等待
           			ID  = 9'b000001000,	//译码
           			EX  = 9'b000010000,	//执行
           			ST  = 9'b000100000,	//内存写
				LD  = 9'b001000000,	//内存读
				RDW = 9'b010000000,	//读数据等待
           			WB  = 9'b100000000;	//写回

	reg [8:0] 		current_state;	//现阶段
	reg [8:0]		next_state;	//下一阶段

	always @(posedge clk) begin		//第一段状态机
		if (rst == 1'b1) begin
			current_state <= INIT;
		end
		else begin
			current_state <= next_state;
		end
	end

	always @(*) begin			//第二段状态机
		case (current_state)
			INIT: begin
				if (rst == 1'b0) begin
				next_state = IF;
				end
				else begin
				next_state = INIT;
				end
			end
			IF: begin
				if (Inst_Req_Ready == 1'b1) begin
				next_state = IW;		//取指完成进入译码
				end
				else begin 
				next_state = IF;
				end
			end

			IW: begin
				if (Inst_Valid == 1'b1) begin
				next_state = ID;
				end
				else begin
				next_state = IW;
				end
			end 

			ID: begin
				if (isnop) begin
				next_state = IF;		//空指令直接结束
				end
				else begin
				next_state = EX;		//译码完成进入执行
				end
			end

			EX: begin
				if(isj || isREGIMM || isItypeb) begin
					next_state = IF;	//分支指令,j指令进入取指阶段
				end
				else if(isItypel) begin
					next_state = LD;	//load指令进入内存读
				end
				else if(isItypes) begin
					next_state = ST;	//store指令进入内存写
				end
				else begin
					next_state = WB;	//其他指令写回
				end
			end

			ST: begin
				if(Mem_Req_Ready == 1'b1) begin
					next_state = IF;
				end
				else begin
					next_state = ST;
				end
			end

			LD: begin
				if(Mem_Req_Ready == 1'b1) begin
					next_state = RDW;
				end
				else begin
					next_state = LD;
				end
			end

			RDW: begin
				if(Read_data_Valid == 1'b1) begin
					next_state = WB;
				end
				else begin
					next_state = RDW;
				end
			end

			WB: begin
				next_state = IF;		//写回完成回到取指
			end

			default: begin
				next_state = IF;
			end
		endcase			
	end

	//第三段状态机
	assign  IRWrite 	= 	!rst && (current_state == IW) && (Inst_Valid == 1'b1);
	assign  PCWrite 	= 	!rst && ((current_state == IW && Inst_Valid == 1'b1) || (current_state == EX && isj) || (current_state == EX && isjr) || (current_state == EX && isjal) || (current_state == EX && isjalr));
	assign  PCWriteCond	=	!rst && ((current_state == EX && isItypeb) || (current_state == EX && isREGIMM));
	assign  RegWrite	=	!rst && ((current_state == WB && islui) || (current_state == WB && isItypel) || (current_state == WB && ismov && (movn || movz)) || (current_state == WB && isjal) || (current_state == WB && isjalr) || (current_state == WB && isRtype && !ismov && !isjr && !isjalr) || (current_state == WB && isItypec));
	assign	MemWrite_reg	=	!rst && (current_state == ST);
	assign  MemRead_reg	=	!rst && (current_state == LD);
	assign  ALUSrcA         =       !rst  && !(current_state == IF) && !(current_state == ID) && ((current_state == EX) && (isItypel || isItypes || islui || isItypeb || (isRtype && !isjalr) || isItypec || isREGIMM));
	assign  ALUSrcB[1] 	= 	!rst && ((current_state == ID) || (current_state == EX && (isItypel || isItypes || islui || isItypec)));
	assign  ALUSrcB[0]      =       !rst && ((current_state == IF) || (current_state == IW) || (current_state == ID) || (current_state == EX && (isjal || isjalr)));
	assign  RegDst[1] 	= 	(current_state == WB && isjal) && !rst;
	assign  RegDst[0] 	= 	(current_state == WB && (isRtype || isjalr)) && !rst;
	assign  MemtoReg[1]     =       (current_state == WB && ismov) && !rst;
	assign  MemtoReg[0] 	= 	(current_state == WB && (isItypel || ismov)) && !rst;
	assign  PCSource[1] 	= 	(current_state == EX && (isj || isjal || isjr || isjalr)) && !rst;
	assign  PCSource[0] 	= 	(current_state == EX && (isItypeb || isjr || isjalr || isREGIMM)) && !rst;
	assign  topALUop[1]     =       (current_state == EX && ((isRtype && !isjalr) || isItypec)) && !rst;
	assign  topALUop[0] 	= 	(current_state == EX && (isItypeb || isREGIMM)) && !rst;
	assign  UseLui		=	!rst && (current_state == EX && islui);
	assign	UseShift	=	!rst && (current_state == WB && isshift);
	assign	Inst_Req_Valid	=	!rst && (current_state == IF);
	assign	Inst_Ready	=	!rst && ((current_state == IW) || (current_state == INIT));
	assign	Read_data_Ready	=	!rst && ((current_state == RDW) || (current_state == INIT));

	//中间寄存器相关
	wire 	A_B_write; 		
	assign  A_B_write		= 	(current_state == ID);
	wire 	ALUOut_write;	
	assign  ALUOut_write 		= 	(current_state == EX) && !isItypeb && !isREGIMM;
	wire 	MDR_write; 	
	assign	MDR_write		= 	(Read_data_Valid == 1'b1) && (current_state == RDW);
	wire	BranchTarget_write;
	assign	BranchTarget_write	=	(current_state == ID);


	always @(posedge clk) begin
		if (rst) begin	//重置
			IR <= 32'b0;
			MDR <= 32'b0;
			A <= 32'b0;
			B <= 32'b0;
			ALUOut <= 32'b0;
			PC4_temp <= 32'b0;
			BranchTarget <= 32'b0;
		end
		else begin
			if (IRWrite) begin
				IR	 <= Instruction; 
				PC4_temp <= alu_result;
			end
			if (MDR_write) begin
				MDR <= Read_data;
			end
			if (A_B_write) begin
				A <= RF_rdata1;
				B <= RF_rdata2;
			end
			if (ALUOut_write) begin
				ALUOut <= alu_result;
			end
			if (BranchTarget_write) begin
				BranchTarget <= alu_result;
			end
		end
	end

	//寄存器堆相关
	wire [4:0]		RF_raddr1;	//寄存器堆一号端口读出地址
	wire [4:0]		RF_raddr2;	//寄存器堆二号端口读出地址

	wire [4:0]		RF_waddr; 	//寄存器堆写入地址

	wire [31:0]		RF_wdata;	//寄存器堆写入数据

	//数据移动指令处理
	assign			movn 		= 	((isRtype && func == 6'b001011) && B != 32'b0)	?	1'b1 :	//movn指令rt读出内容不为0，将rs作为写入数据
									     					1'b0;
	assign			movz		=	((isRtype && func == 6'b001010) && B == 32'b0) 	?	1'b1 : //movz指令rt读出内容为0，将rs作为写入数据
									     					1'b0;

	//alu相关
	wire [31:0] 		alu_A;		//alu中的A
	wire [31:0] 		alu_B; 		//alu中的B

	wire [2:0] 		temp_alu_op; 	//根据func字段生成的alu操作码
	wire [2:0]		alu_op;

	wire 			alu_overflow; 	//alu有符号数溢出
	wire			alu_carryout; 	//alu无符号数进位
	wire			alu_zero; 	//alu结果为0

	

	assign 			temp_alu_op 	  =	isItypel || isItypes			   ? 3'b010			: //内存读写地址计算
							isRtype & (func[3:2] == 2'b00) 		   ? {func[1],2'b10}	    	: //add/sub
							isRtype & (func[3:2] == 2'b01) 		   ? {func[1],1'b0,func[0]} 	: //逻辑运算
							isRtype & (func[3:2] == 2'b10) 		   ? {~func[0],2'b11} 	    	: //比较运算
							opcode[2:1]	==	2'b00 		   ? {opcode[1],2'b10} 	   	: //立即数加减法
							opcode[2]	==	1'b1  		   ? {opcode[1],1'b0,opcode[0]} : //立即数逻辑运算
							opcode[2:1]	==	2'b01 		   ? {~opcode[0],2'b11}         : //立即数比较
												     3'b000;

	//I-type内存读写指令处理
	wire [31:0]		temp_address;		//未对齐的内存地址

	wire [3:0]		temp_read_strb;		//不考虑lwl/lwr的read_strb

	wire [3:0]		read_strb;		//类似于Write_strb

	wire [31:0]		mem_data;		//处理后的从内存中读出的数据
	
	wire [3:0]		temp_Write_strb;	//不考虑swl/swr的Write_strb

	assign			temp_address	=	(isItypel || isItypes)  ?   ALUOut : //读写地址均为立即数+寄存器base
								   		    32'b0;

	assign 			Address 	= 	{temp_address[31:2], 2'b0}; //地址对齐	

	assign			temp_read_strb	=	opcode[2:0] == 3'b011					?	4'b1111 : //lw指令，读取完整数据
							opcode[1:0] == 2'b01 & (temp_address[1:0] == 2'b00)	?	4'b0011 : //lh指令，读取两个字节，低两位
							opcode[1:0] == 2'b01 & (temp_address[1:0] == 2'b10) 	?	4'b1100 : //高两位
							opcode[1:0] == 2'b00 & (temp_address[1:0] == 2'b00) 	? 	4'b0001 : //lb指令，读取一个字节，低8位
							opcode[1:0] == 2'b00 & (temp_address[1:0] == 2'b01) 	? 	4'b0010 : //次低8位
							opcode[1:0] == 2'b00 & (temp_address[1:0] == 2'b10) 	? 	4'b0100 : //次高8位
							opcode[1:0] == 2'b00 & (temp_address[1:0] == 2'b11) 	? 	4'b1000 : //高8位
															4'b0000;

        assign                  read_strb       = 	(opcode[2:0] == 3'b010)       ? ( // LWL
                                                  	(temp_address[1:0] == 2'b00)  ? 4'b0001 : // 偏移0,仅读0字节
                                                  	(temp_address[1:0] == 2'b01)  ? 4'b0011 : // 偏移1,读1, 0字节
                                                  	(temp_address[1:0] == 2'b10)  ? 4'b0111 : // 偏移2,读2, 1, 0字节
                                                                                 	4'b1111   // 偏移3,读3, 2, 1, 0字节
                                                  				              ) :
                                                  	(opcode[2:0] == 3'b110)       ? ( // LWR
                                                  	(temp_address[1:0] == 2'b00)  ? 4'b1111 : // 偏移0,读3, 2, 1, 0字节
                                                  	(temp_address[1:0] == 2'b01)  ? 4'b1110 : // 偏移1,读3, 2, 1字节
                                                  	(temp_address[1:0] == 2'b10)  ? 4'b1100 : // 偏移2,读3, 2字节
                                                                                  	4'b1000   // 偏移3,仅读3字节
                                                  					      ) : 
                                                  					temp_read_strb;

        assign                  mem_data        = (opcode[2:0] == 3'b010)                         ? ( // LWL
                                                  (temp_address[1:0] == 2'b00)                    ? {MDR[7:0],  B[23:0]}   : // 把总线最低8位移到寄存器最高8位
                                                  (temp_address[1:0] == 2'b01)                    ? {MDR[15:0], B[15:0]}   : // 把总线低16位移到寄存器高16位
                                                  (temp_address[1:0] == 2'b10)                    ? {MDR[23:0], B[7:0]}    : // 把总线低24位移到寄存器高24位
                                                                                                    B                        // 满字直接存入
                                                  ) :
                                                  (opcode[2:0] == 3'b110)                         ? ( // LWR
                                                  (temp_address[1:0] == 2'b00)                    ? MDR                    : // 满字直接存入
                                                  (temp_address[1:0] == 2'b01)                    ? {B[31:24], MDR[31:8]}  : // 把总线高24位移到寄存器低24位
                                                  (temp_address[1:0] == 2'b10)                    ? {B[31:16], MDR[31:16]} : // 把总线高16位移到寄存器低16位
                                                                                                    {B[31:8],  MDR[31:24]}   // 把总线最高8位移到寄存器最低8位
                                                  ) :
                                                  // 常规指令逻辑
                                                  read_strb == 4'b1111                            ? MDR 				:
                                                  read_strb == 4'b0011 & opcode[2:0] != 3'b101    ? {{16{MDR[15]}},MDR[15:0]}  		: //lh
                                                  read_strb == 4'b0011 & opcode[2:0] == 3'b101    ? {{16{1'b0}},MDR[15:0]}            	: //lhu
                                                  read_strb == 4'b1100 & opcode[2:0] != 3'b101    ? {{16{MDR[31]}},MDR[31:16]}  	: //lh
                                                  read_strb == 4'b1100 & opcode[2:0] == 3'b101    ? {{16{1'b0}},MDR[31:16]}          	: //lhu
                                                  read_strb == 4'b0001 & opcode[2:0] != 3'b100    ? {{24{MDR[7]}},MDR[7:0]}     	: //lb
                                                  read_strb == 4'b0001 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[7:0]}             	: //lbu
                                                  read_strb == 4'b0010 & opcode[2:0] != 3'b100    ? {{24{MDR[15]}},MDR[15:8]}   	: 
                                                  read_strb == 4'b0010 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[15:8]}            	: 
                                                  read_strb == 4'b0100 & opcode[2:0] != 3'b100    ? {{24{MDR[23]}},MDR[23:16]}  	: 
                                                  read_strb == 4'b0100 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[23:16]}           	: 
                                                  read_strb == 4'b1000 & opcode[2:0] != 3'b100    ? {{24{MDR[31]}},MDR[31:24]}  	: 
                                                  read_strb == 4'b1000 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[31:24]}           	: 
                                                                                                    32'b0;

        assign                  Write_strb      = (opcode[2:0] == 3'b010)                         ? ( 	      // SWL
                                                  (temp_address[1:0] == 2'b00)                    ? 4'b0001 : // 偏移0: 只写0字节
                                                  (temp_address[1:0] == 2'b01)                    ? 4'b0011 : // 偏移1: 写1, 0字节
                                                  (temp_address[1:0] == 2'b10)                    ? 4'b0111 : // 偏移2: 写2, 1, 0字节
                                                                                                    4'b1111   // 偏移3: 写全字
                                                  							  ) :
                                                  (opcode[2:0] == 3'b110)                         ? (         // SWR
                                                  (temp_address[1:0] == 2'b00)                    ? 4'b1111 : // 偏移0: 写全字
                                                  (temp_address[1:0] == 2'b01)                    ? 4'b1110 : // 偏移1: 写3, 2, 1字节
                                                  (temp_address[1:0] == 2'b10)                    ? 4'b1100 : // 偏移2: 写3, 2字节
                                                                                                    4'b1000   // 偏移3: 只写3字节
                                                  						 	  ) : 
                                                  temp_Write_strb; // 默认常规 sb/sh/sw 逻辑

        assign                  Write_data      = (opcode[2:0] == 3'b010)                         ? ( 				  // SWL
                                                  (temp_address[1:0] == 2'b00)                    ? {24'b0, B[31:24]} 		: // 寄存器最高位-内存最低位
                                                  (temp_address[1:0] == 2'b01)                    ? {16'b0, B[31:16]} 		: // 寄存器高16位-内存低16位
                                                  (temp_address[1:0] == 2'b10)                    ? {8'b0,  B[31:8]}  		: // 寄存器高24位-内存低24位
                                                                                                    B                   	  // 全字对齐
                                                  									    ) 	:
                                                  (opcode[2:0] == 3'b110)                         ? ( 				  // SWR
                                                  (temp_address[1:0] == 2'b00)                    ? B                		: // 全字
                                                  (temp_address[1:0] == 2'b01)                    ? {B[23:0], 8'b0}   		: // 寄存器低24位-内存高24位
                                                  (temp_address[1:0] == 2'b10)                    ? {B[15:0], 16'b0}  		: // 寄存器低16位-内存高16位
                                                                                                    {B[7:0],  24'b0}    	  // 寄存器最低位-内存最高位
                                                  									    ) 	:
                                                  // 常规指令逻辑
                                                  (Write_strb == 4'b1111)                         ? B 		            	: //sw
                                                  (Write_strb == 4'b0011)                         ? {16'b0, B[15:0]}        	: //sh
                                                  (Write_strb == 4'b1100)                         ? {B[15:0], 16'b0}        	: //sh
                                                  (Write_strb == 4'b0001)                         ? {24'b0, B[7:0]}  	    	: //sb
                                                  (Write_strb == 4'b0010)                         ? {16'b0, B[7:0],  8'b0}  	: //sb
                                                  (Write_strb == 4'b0100)                         ? {8'b0,  B[7:0], 16'b0}  	: //sb
                                                  (Write_strb == 4'b1000)                         ? {B[7:0], 24'b0}  	    	: //sb
                                                                                                    32'b0;

        assign                  temp_Write_strb = (opcode[2:0] == 3'b011)                         ? 				  4'b1111 : //sw
                                                  (opcode[2:0] == 3'b001)                         ? (temp_address[1] ? 4'b1100 : 4'b0011) : //sh
                                                  (opcode[2:0] == 3'b000)                         ? (
                                                  (temp_address[1:0] == 2'b00) 			  ? 4'b0001 				  :
                                                  (temp_address[1:0] == 2'b01) 			  ? 4'b0010 				  :
                                                  (temp_address[1:0] == 2'b10) 			  ? 4'b0100 				  : 
						  						    4'b1000
                                                 											) : 
												    4'b0000;

	//移位器相关
	wire [31:0]		shifter_A;	//移位器操作数
	wire [4:0]		shifter_B;	//移位长度

	wire [1:0]		shifter_op;	//移位器操作码

	wire [31:0]		shifter_result; //移位结果

	assign			shifter_A 	=	B;			   	   //寄存器堆一号端口读出作为被位移数
	assign			shifter_B	=	func[2] == 1'b1 ? A[4:0]: 	   //sllv等，用寄存器堆一号端口的读出前五位做位移长度
									  shmat;	   //sll等，用shmat（sa）做位移长度
	assign			shifter_op	=	func[1:0];

	//寄存器堆相关										
	//对于仅需一个读出端口的指令，使用1号端口
	assign			RF_raddr1	=	isRtype 						? rs 		:	//R-type
							isREGIMM 						? rs		:	//REGIMM
							isItypeb						? rs		:	//I-type分支
							isItypec						? rs		:	//I-type计算
							isItypel						? base		:	//I-type内存读地址
							isItypes						? base		:	//I-type内存写
														  5'b00000;

	assign			RF_raddr2	=	isRtype 					     	? rt 		:	//R-type
							isREGIMM 					      	? 5'b00000	:	//REGIMM
							islwlr 							? rt 		:	//lwl/lwr
							isItypeb						? rt		:	//I-type分支
							isItypes						? rt		:	//I-type内存写数据
														  5'b00000;

	assign 			RF_waddr  	=	RegDst == 2'b00						? rt		:
							RegDst == 2'b01 					? rd 		:	
							RegDst == 2'b10						? 5'b11111	:
														  5'b00000;

	assign 			RF_wdata	= 	(MemtoReg ==2'b00) && (UseShift == 1'b1)		? shifter_result:
							MemtoReg == 2'b00					? ALUOut	:
							MemtoReg == 2'b01					? mem_data	:
							MemtoReg == 2'b10					? PC4_temp	:
							MemtoReg == 2'b11					? A 		:
														  32'b0;

	reg_file cpu_reg_file	(
		.clk 	 	(clk),
		.waddr   	(RF_waddr),
		.raddr1  	(RF_raddr1),
		.raddr2  	(RF_raddr2),
		.wen	 	(RF_wen),
		.wdata	 	(RF_wdata),
		.rdata1  	(RF_rdata1),
		.rdata2  	(RF_rdata2)
	); //寄存器堆实例化

	alu cpu_alu	      	(
		.A	 	(alu_A),
		.B	 	(alu_B),
		.ALUop   	(alu_op),
		.Overflow	(alu_overflow),
		.CarryOut	(alu_carryout),
		.Zero		(alu_zero),
		.Result		(alu_result)
	); //ALU实例化

	shifter cpu_shifter    	(
		.A		(shifter_A),
		.B		(shifter_B),
		.Shiftop	(shifter_op),
		.Result		(shifter_result)
	); //移位器实例化

	//分支指令处理
	wire			branch;		//branch命令，1表示执行分支，0表示不执行

	assign			branch		=	(opcode == 6'b000101 && (A != B)) 						? 1'b1 : //bne
							(opcode == 6'b000100 && (A == B))				  		? 1'b1 : //beq
							(opcode == 6'b000110 && (A == 32'b0 || A[31] == 1'b1))  			? 1'b1 : //blez
							(opcode == 6'b000111 && (A[31] == 1'b0 && A != 0))				? 1'b1 : //bgtz
							((opcode == 6'b000001 && rt == 5'b00000) && (A[31] == 1'b1))			? 1'b1 : //bltz
							((opcode == 6'b000001 && rt == 5'b00001) && (A[31] == 1'b0 || A == 32'b0))	? 1'b1 : //bgez
																	  1'b0;

	assign			MemWrite 	= 	MemWrite_reg;

	assign			MemRead  	= 	MemRead_reg;

	assign			RF_wen		=	RegWrite;

	assign			alu_A		=	UseLui			?	32'b0		: //Lui0 + 左移后的立即数
							ALUSrcA == 1'b0 	? 	PC 		: //0用PC
							ALUSrcA == 1'b1 	?	A		: //1用rs
											32'b0;

	assign			alu_B		=	UseLui			?	lm_immediate	: //Lui用左移的立即数
							ALUSrcB == 2'b00	?	B		: //00用rt
							ALUSrcB	== 2'b01	?	32'd4		: //01用4
							ALUSrcB == 2'b10	?	(isItypecl ? zo_immediate : se_immediate)	: //10用符号位扩展立即数
							ALUSrcB == 2'b11	?	se_target_offset: //11用左移两位的符号位扩展立即数
											32'b0;

	assign			alu_op		=	(topALUop == 2'b00) 	?	3'b010 		: //00做加法
							(topALUop == 2'b01) 	? 	3'b110 		: //01做减法
							(topALUop == 2'b10) 	? 	temp_alu_op	: //10根据func字段
											3'b000;		  //PC更新使能，1写入

	reg [31:0] current_pc;
	assign PC = current_pc; // 驱动到地址总线或指令内存

	always @(posedge clk) begin
		if (rst) begin
			current_pc <= 32'b0;
			end
			else begin
				if (PCWrite || (PCWriteCond && branch)) begin
					case (PCSource)
					2'b00: current_pc <= alu_result;       				// 来自ALU直接输出（用于ID阶段的PC+4）
	           			2'b01: current_pc <= BranchTarget;           			// 来自ALUOut寄存器（用于Branch目标地址）
					2'b10: current_pc <= {current_pc[31:28], instr_index, 2'b00}; 	// J型指令跳转地址
					2'b11: current_pc <= A;                				// 用于jr/jalr(从寄存器rs读出的值)
					endcase
					end
				end
	end

	//性能计数器
	reg [31:0]	cycle_count; //周期计数
	assign		cpu_perf_cnt_0		=	cycle_count;
	always @ (posedge clk) begin
		if(rst == 1'b1) begin
			cycle_count <= 32'b0;
		end
		else begin
			cycle_count <= cycle_count + 32'd1;
		end
	end

	assign 			inst_retire 	= 	{RF_wen,RF_waddr,RF_wdata,current_pc};

	reg [31:0]	instruction_count; //指令计数
	assign		cpu_perf_cnt_1		=	instruction_count;
	always @ (posedge clk)	begin
		if(rst == 1'b1) begin
			instruction_count <= 32'b0;
		end
		else begin
			if(current_state == IF && Inst_Req_Ready == 1'b1) begin
				instruction_count <= instruction_count + 32'd1;
			end
		end
	end

endmodule
