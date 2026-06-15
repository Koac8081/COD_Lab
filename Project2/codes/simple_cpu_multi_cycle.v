`timescale 10ns / 1ns

module simple_cpu(
	input             	clk, 		//处理器时钟
	input             	rst, 		//复位信号

	output [31:0]     	PC, 		//程序计数器
	input  [31:0]     	Instruction, 	//从内存中读取的指令

	output [31:0]     	Address, 	//访存指令使用的内存地址
	output           	MemWrite, 	//内存访问的写使能信号
	output [31:0]    	Write_data, 	//内存写操作数据
	output [3:0]     	Write_strb, 	//内存写操作字节有效信号

	input  [31:0]     	Read_data, 	//从内存中读取的数据
	output            	MemRead 	//内存访问的读使能信号
);
	//多周期中间寄存器堆
	reg  [31:0]		IR;		//指令寄存器
	reg  [31:0]		MDR;		//内存数据寄存器
	reg  [31:0]		A;		//寄存器堆rs读出
	reg  [31:0]		B;		//寄存器堆rt读出
	reg  [31:0]		ALUOut;		//ALU运算结果
	reg  [31:0] 		PC4_temp; 	// 用于锁存当前指令的下一条地址(PC+4)

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

	assign			isRtype		=	(opcode == 6'b000000);
	assign			isREGIMM	=	(opcode == 6'b000001);
	assign			isItypeb	=	(opcode[5:2] == 4'b0001);
	assign			isItypec	=	(opcode[5:3] == 3'b001);
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

	wire 			movn;
	wire 			movz;
	wire [31:0]		alu_result;	//alu运算结果
	wire [31:0]		RF_rdata1;	//寄存器堆一号端口读出
	wire [31:0]		RF_rdata2;	//寄存器堆二号端口读出


	//多周期处理器新增变量
	wire			RF_wen;
	reg			IRWrite;	//IR写使能,1写入
	reg			PCWrite;	//PC更新使能，1写入
	reg			PCWriteCond;	//PC条件更新使能，1写入，若ALUZero为1
	reg			RegWrite;	//寄存器堆写使能，1写入
	reg			MemWrite_reg;	//内存写使能，1写入
	reg			MemRead_reg;	//内存读使能，1读出
	reg			ALUSrcA;	//ALU第一个操作数选择，0为PC，1为寄存器A
	reg [1:0]		ALUSrcB;	//ALU第二个操作数选择，00为B，01为4，10为符号位扩展立即数，11为左移符号位扩展立即数
	reg [1:0]		RegDst;		//寄存器堆写入，00写入rt，01写入rd,10写入31号寄存器
	reg [1:0]		MemtoReg;	//寄存器堆写入端口，00写ALUOut，01写MDR,10写PC+4/PC+8,11条件移动
	reg [1:0]		topALUop;	//ALUop，00加法，01减法，10根据func决定
	reg [1:0]		PCSource;	//PC接收数据，00PC+4，01分支，10跳转，11A
	reg 			UseLui;		//是否为Lui指令
	reg			UseShift;	//是否为移位指令

	//多周期处理器状态机
	localparam 		IF  = 3'b000,
           			ID  = 3'b001,
           			EX  = 3'b010,
           			MEM = 3'b011,
           			WB  = 3'b100;
	reg [4:0] 		current_state;	//现阶段
	reg [4:0]		next_state;	//下一阶段

	always @(posedge clk) begin		//第一段状态机
		if (rst == 1'b1) begin
			current_state <= IF;
		end
		else begin
			current_state <= next_state;
		end
	end

	always @(*) begin			//第二段状态机
		case (current_state)
			IF: begin
				next_state = ID;		//取指完成进入译码
			end

			ID: begin
				next_state = EX;		//译码完成进入执行
			end

			EX: begin
				if(isj || isREGIMM || isItypeb || isjr) begin
					next_state = IF;	//分支指令,j指令，jr指令进入取指阶段
				end
				else if(isItypel || isItypes) begin
					next_state = MEM;	//访存指令进入访存阶段
				end
				else begin
					next_state = WB;	//其他指令写回
				end
			end

			MEM: begin
				if(isItypel) begin
					next_state = WB;	//load指令访存后写回
				end
				else begin
					next_state = IF;	//store指令访存后取指
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

	always @(*) begin	//第三段状态机
		if (rst) begin //初始状态
		IRWrite 	= 0;	
		PCWrite		= 0;	
		PCWriteCond	= 0;	
		RegWrite	= 0;	
		MemWrite_reg	= 0;	
		MemRead_reg	= 0;	
		ALUSrcA		= 0;	
		ALUSrcB		= 0;	
		RegDst		= 0;		
		MemtoReg	= 0;	
		topALUop	= 0;		
		PCSource	= 0;	
		UseLui		= 0;
		UseShift	= 0;
		end 
		else begin
		IRWrite 	= 0;	
		PCWrite		= 0;	
		PCWriteCond	= 0;	
		RegWrite	= 0;	
		MemWrite_reg	= 0;	
		MemRead_reg	= 0;	
		ALUSrcA		= 0;	
		ALUSrcB		= 0;	
		RegDst		= 0;		
		MemtoReg	= 0;	
		topALUop	= 0;		
		PCSource	= 0;	
		UseLui		= 0;
		UseShift	= 0;
			case (current_state)
			IF: begin
                		IRWrite  = 1'b1;       	// 指令写入IR
                		ALUSrcA  = 1'b0;       	// ALU第一个操作数选PC
               	 		ALUSrcB  = 2'b01;     	// ALU第二个操作数选4
                		topALUop = 2'b00;     	// ALU执行加法
                		PCSource = 2'b00;      	// PC接受PC + 4
                		PCWrite  = 1'b1;       	// PC写使能
			end

            		ID: begin
                		ALUSrcA  = 1'b0;       	// ALU第一个操作数选PC
                		ALUSrcB  = 2'b11;      	// ALU第二个操作数选经过左移2位的立即数
                		topALUop = 2'b00;     	// 执行加法
            		end

            		EX: begin
				if (isItypel || isItypes) begin 	// load/store指令
				ALUSrcA 	= 1'b1;    		// ALU第一个操作数选寄存器rs
                    		ALUSrcB 	= 2'b10;   		// ALU第二个操作数选符号扩展后的立即数
                    		topALUop 	= 2'b00;  		// 执行加法
				end
				else if (islui) begin			//lui指令
				ALUSrcA		= 1'b1;
				ALUSrcB		= 2'b10;
				topALUop	= 2'b00;
				UseLui		= 1'b1;
				end 
                		else if (isItypeb) begin 		// 分支指令
                    		ALUSrcA    	= 1'b1; 		// 选rs
                    		ALUSrcB     	= 2'b00; 		// 选rt
                    		topALUop   	= 2'b01; 		// 执行减法
                    		PCSource    	= 2'b01; 		// 若跳转，地址选自ALUOut
                    		PCWriteCond 	= 1'b1; 		// 开启条件写使能，由ALU的Zero信号决定是否写PC
                		end
				else if (isj) begin			//j指令
				PCWrite		= 1'b1;			//开启PC写使能
				PCSource	= 2'b10;		//PC接受跳转地址
				end
				else if (isjr) begin 			//jr指令
        			PCSource 	= 2'b11;        	// PC接受A
        			PCWrite  	= 1'b1;         	// 立即更新PC
    				end
    				else if (isjal) begin 			//jal指令
        			PCWrite  	= 1'b1;
        			PCSource 	= 2'b10;        	// 接受跳转地址
    				end
    				else if (isjalr) begin 			//jalr指令
        			PCSource 	= 2'b11;       		// PC接受A
        			PCWrite  	= 1'b1;
    				end
				else if (isRtype) begin			// R-type指令
                    		ALUSrcA 	= 1'b1;    		// 选rs
                    		ALUSrcB 	= 2'b00;   		// 选寄存器rt
                    		topALUop  	= 2'b10;  		// 根据func字段生成的具体操作码
               			end
				else if (isItypec) begin		//I-type计算类指令
				ALUSrcA		= 1'b1;
				ALUSrcB		= 2'b10;
				topALUop	= 2'b10;
				end
				else if (isREGIMM) begin		// bltz/bgez
				ALUSrcA     = 1'b1;
				ALUSrcB     = 2'b00;
				topALUop    = 2'b01;
				PCSource    = 2'b01;
				PCWriteCond = 1'b1;
				end
			end

            		MEM: begin
                		if (isItypel) 
                    		MemRead_reg = 1'b1;    		// lw: 将内存数据读入MDR寄存器
                		else if (isItypes) 
                    		MemWrite_reg = 1'b1;    		// sw: 将rt的值写入内存
            		end

            		WB: begin
				if (islui) begin //Lui指令
				RegWrite	= 1'b1;
				RegDst 		= 2'b00;
				MemtoReg	= 2'b00;
				end
                		else if (isItypel) begin	//load指令
                    		RegDst   	= 2'b00;  	// 00: 目标寄存器是rt
                    		MemtoReg 	= 2'b01;  	// 01: 数据来源是MDR(内存数据)
                    		RegWrite  	= 1'b1;   	// 开启写使能
                		end
				else if ((isRtype && func == 6'b001011) || (isRtype && func == 6'b001010)) begin //mov指令
        			RegDst   = 2'b01;          	// 目标寄存器是rd
        			MemtoReg = 2'b11;          	// 指向寄存器A
        			RegWrite = (movn || movz); 	// 只有当条件满足时，才写使能
    				end
                		else if (isjal) begin //jal指令
                    		RegDst   	= 2'b10;  	// 10: 固定写入31号寄存器
                    		MemtoReg 	= 2'b10;  	// 10: 写入PC+4或PC+8(返回地址)
                    		RegWrite   	= 1'b1;
                		end
				else if (isjalr) begin //jalr指令
                    		RegDst   	= 2'b01;  	// 01: 写入rd号寄存器
                    		MemtoReg 	= 2'b10;  	// 10: 写入PC+4或PC+8(返回地址)
                    		RegWrite   	= 1'b1;
                		end
				else if (isRtype) begin		//R-type指令
                    		RegDst   	= 2'b01;  	// 01: 目标寄存器是rd
                    		MemtoReg 	= 2'b00;  	// 00: 数据来源是ALUOut(运算结果)
                    		RegWrite 	= 1'b1; 	// 普通 R-type
				UseShift	= ((isRtype) &&(func[5:3] == 3'b000)); //是否为移位指令
                		end
				else if (isItypec) begin 	  //I-type 运算指令
        			RegDst   	= 2'b00;          // 目标寄存器是rt
        			MemtoReg 	= 2'b00;          // 数据来源是ALUOut
        			RegWrite 	= 1'b1;
    				end
			end
			endcase
    		end
	end

	wire 	A_B_write; 	
	assign  A_B_write	= 	(current_state == ID);
	wire 	ALUOut_write;	
	assign	ALUOut_write	= 	(current_state == ID) || (current_state == EX);
	wire 	MDR_write; 	
	assign	MDR_write	= 	(current_state == MEM) && MemRead_reg;


	always @(posedge clk) begin
		if (rst) begin
			IR <= 32'b0;
			MDR <= 32'b0;
			A <= 32'b0;
			B <= 32'b0;
			ALUOut <= 32'b0;
			PC4_temp <= 32'b0;
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
		end
	end

	//寄存器堆相关
	wire [4:0]		RF_raddr1;	//寄存器堆一号端口读出地址
	wire [4:0]		RF_raddr2;	//寄存器堆二号端口读出地址

	wire [4:0]		RF_waddr; 	//寄存器堆写入地址

	wire [31:0]		RF_wdata;	//寄存器堆写入数据

	//数据移动指令处理
	assign			movn 		= 	((isRtype && func == 6'b001011) && B != 32'b0)	?	 1'b1 :	//movn指令rt读出内容不为0，将rs作为写入数据
									     								 1'b0;
	assign			movz		=	((isRtype && func == 6'b001010) && B == 32'b0) 	?	 1'b1 : //movz指令rt读出内容为0，将rs作为写入数据
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

        assign                  read_strb       = 	(opcode[2:0] == 3'b010)       ? ( // LWL小端序
                                                  	(temp_address[1:0] == 2'b00)  ? 4'b0001 : // 偏移0: 仅读byte 0
                                                  	(temp_address[1:0] == 2'b01)  ? 4'b0011 : // 偏移1: 读byte 1, 0
                                                  	(temp_address[1:0] == 2'b10)  ? 4'b0111 : // 偏移2: 读byte 2, 1, 0
                                                                                 	4'b1111   // 偏移3: 读byte 3, 2, 1, 0
                                                  				              ) :
                                                  	(opcode[2:0] == 3'b110)       ? ( // LWR小端序
                                                  	(temp_address[1:0] == 2'b00)  ? 4'b1111 : // 偏移0: 读byte 3, 2, 1, 0
                                                  	(temp_address[1:0] == 2'b01)  ? 4'b1110 : // 偏移1: 读byte 3, 2, 1
                                                  	(temp_address[1:0] == 2'b10)  ? 4'b1100 : // 偏移2: 读byte 3, 2
                                                                                  	4'b1000   // 偏移3: 仅读byte 3
                                                  					      ) : 
                                                  					temp_read_strb;

        assign                  mem_data        = (opcode[2:0] == 3'b010)                         ? ( // LWL小端序拼接
                                                  (temp_address[1:0] == 2'b00)                    ? {MDR[7:0],  B[23:0]}   : // 把总线最低8位移到寄存器最高8位
                                                  (temp_address[1:0] == 2'b01)                    ? {MDR[15:0], B[15:0]}   : // 把总线低16位移到寄存器高16位
                                                  (temp_address[1:0] == 2'b10)                    ? {MDR[23:0], B[7:0]}    : // 把总线低24位移到寄存器高24位
                                                                                                    MDR                              // 满字直接存入
                                                  ) :
                                                  (opcode[2:0] == 3'b110)                         ? ( // LWR小端序拼接
                                                  (temp_address[1:0] == 2'b00)                    ? MDR                            : // 满字直接存入
                                                  (temp_address[1:0] == 2'b01)                    ? {B[31:24], MDR[31:8]}  : // 把总线高24位移到寄存器低24位
                                                  (temp_address[1:0] == 2'b10)                    ? {B[31:16], MDR[31:16]} : // 把总线高16位移到寄存器低16位
                                                                                                    {B[31:8],  MDR[31:24]}   // 把总线最高8位移到寄存器最低8位
                                                  ) :
                                                  // 常规指令逻辑
                                                  read_strb == 4'b1111                            ? MDR 				:
                                                  read_strb == 4'b0011 & opcode[2:0] != 3'b101    ? {{16{MDR[15]}},MDR[15:0]}  		: //lh
                                                  read_strb == 4'b0011 & opcode[2:0] == 3'b101    ? {{16{1'b0}},MDR[15:0]}            	: //lhu
                                                  read_strb == 4'b1100 & opcode[2:0] != 3'b101    ? {{16{MDR[31]}},MDR[31:16]}  	: //lh (高半字)
                                                  read_strb == 4'b1100 & opcode[2:0] == 3'b101    ? {{16{1'b0}},MDR[31:16]}          	: //lhu (高半字)
                                                  read_strb == 4'b0001 & opcode[2:0] != 3'b100    ? {{24{MDR[7]}},MDR[7:0]}     	: //lb
                                                  read_strb == 4'b0001 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[7:0]}             	: //lbu
                                                  read_strb == 4'b0010 & opcode[2:0] != 3'b100    ? {{24{MDR[15]}},MDR[15:8]}   	: 
                                                  read_strb == 4'b0010 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[15:8]}            	: 
                                                  read_strb == 4'b0100 & opcode[2:0] != 3'b100    ? {{24{MDR[23]}},MDR[23:16]}  	: 
                                                  read_strb == 4'b0100 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[23:16]}           	: 
                                                  read_strb == 4'b1000 & opcode[2:0] != 3'b100    ? {{24{MDR[31]}},MDR[31:24]}  	: 
                                                  read_strb == 4'b1000 & opcode[2:0] == 3'b100    ? {{24{1'b0}},MDR[31:24]}           	: 
                                                                                                    32'b0;

        assign                  Write_strb      = (opcode[2:0] == 3'b010)                         ? ( 	      // SWL小端序
                                                  (temp_address[1:0] == 2'b00)                    ? 4'b0001 : // 偏移0: 只写byte 0
                                                  (temp_address[1:0] == 2'b01)                    ? 4'b0011 : // 偏移1: 写byte 1, 0
                                                  (temp_address[1:0] == 2'b10)                    ? 4'b0111 : // 偏移2: 写byte 2, 1, 0
                                                                                                    4'b1111   // 偏移3: 写全字
                                                  							  ) :
                                                  (opcode[2:0] == 3'b110)                         ? (         // SWR小端序
                                                  (temp_address[1:0] == 2'b00)                    ? 4'b1111 : // 偏移0: 写全字
                                                  (temp_address[1:0] == 2'b01)                    ? 4'b1110 : // 偏移1: 写byte 3, 2, 1
                                                  (temp_address[1:0] == 2'b10)                    ? 4'b1100 : // 偏移2: 写byte 3, 2
                                                                                                    4'b1000   // 偏移3: 只写byte 3
                                                  						 	  ) : 
                                                  temp_Write_strb; // 默认常规 sb/sh/sw 逻辑

        assign                  Write_data      = (opcode[2:0] == 3'b010)                         ? ( 				  // SWL拼接
                                                  (temp_address[1:0] == 2'b00)                    ? {24'b0, B[31:24]} 		: // 寄存器最高位 -> 内存最低位
                                                  (temp_address[1:0] == 2'b01)                    ? {16'b0, B[31:16]} 		: // 寄存器高16位 -> 内存低16位
                                                  (temp_address[1:0] == 2'b10)                    ? {8'b0,  B[31:8]}  		: // 寄存器高24位 -> 内存低24位
                                                                                                    B                   	  // 全字对齐
                                                  									    ) 	:
                                                  (opcode[2:0] == 3'b110)                         ? ( 				  // SWR拼接
                                                  (temp_address[1:0] == 2'b00)                    ? B                		: // 全字对齐
                                                  (temp_address[1:0] == 2'b01)                    ? {B[23:0], 8'b0}   		: // 寄存器低24位 -> 内存高24位
                                                  (temp_address[1:0] == 2'b10)                    ? {B[15:0], 16'b0}  		: // 寄存器低16位 -> 内存高16位
                                                                                                    {B[7:0],  24'b0}    	  // 寄存器最低位 -> 内存最高位
                                                  									    ) 	:
                                                  // 常规指令逻辑
                                                  (Write_strb == 4'b1111)                         ? B 		            	:
                                                  (Write_strb == 4'b0011)                         ? {16'b0, B[15:0]}        	: //sh (低半字)
                                                  (Write_strb == 4'b1100)                         ? {B[15:0], 16'b0}        	: //sh (高半字)
                                                  (Write_strb == 4'b0001)                         ? {24'b0, B[7:0]}  	    	: //sb (byte 0)
                                                  (Write_strb == 4'b0010)                         ? {16'b0, B[7:0],  8'b0}  	: //sb (byte 1)
                                                  (Write_strb == 4'b0100)                         ? {8'b0,  B[7:0], 16'b0}  	: //sb (byte 2)
                                                  (Write_strb == 4'b1000)                         ? {B[7:0], 24'b0}  	    	: //sb (byte 3)
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
									  shmat;	           //sll等，用shmat（sa）做位移长度
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
					2'b00: current_pc <= alu_result;       				// 来自ALU直接输出（用于IF阶段的PC+4）
	           			2'b01: current_pc <= ALUOut;           				// 来自ALUOut寄存器（用于Branch目标地址）
					2'b10: current_pc <= {current_pc[31:28], instr_index, 2'b00}; 	// J型指令跳转地址
					2'b11: current_pc <= A;                				// 用于jr/jalr(从寄存器rs读出的值)
					endcase
					end
				end
	end
endmodule
