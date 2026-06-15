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
	//此处PC声明为wire,需要转换
	reg  [31:0]		PC_reg;	

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


	assign			opcode		=	Instruction[31:26];
	assign			rs		=	Instruction[25:21];
	assign			rt		=	Instruction[20:16];
	assign			rd		=	Instruction[15:11];
	assign			shmat		=	Instruction[10:6];
	assign			func		=	Instruction[5:0];

	assign			immediate	=	Instruction[15:0];

	assign			instr_index	=	Instruction[25:0];

	assign			se_immediate	=	{{16{immediate[15]}},immediate}; 	//符号位扩展
	assign			zo_immediate	=	{{16{1'b0}},immediate};		 	//零扩展
	assign			lm_immediate	=	{immediate,{16{1'b0}}};		 	//左移16位

	assign			offset		=	Instruction[15:0];
	assign			target_offset	=	{offset,{2{1'b0}}};		 	 //左移2位
	assign			se_target_offset=	{{14{target_offset[17]}},target_offset}; //符号位扩展
	assign			se_offset	=	{{16{offset[15]}},offset};	 	 //符号位扩展

	assign			base		=	Instruction[25:21];

	//译码相关
	wire 			isRtype;	//R-type
	wire			isItypec;	//I-type计算
	wire			isItypel;	//I-type内存读
	wire			isItypes;	//I-type内存写
	wire			isItypeb;	//I-type分支
	wire			isREGIMM;	//REGIMM
	wire			isJtype;	//J-type
	wire			islui;		//lui
	wire			isjalr;		//jr/jalr
	wire			isItypecnl;	//I-type非逻辑计算
	wire			isItypecl;	//I-type逻辑计算
	wire			islwlr;		//lwl/lwr
	wire			isj;		//j/jal

	assign			isRtype		=	(opcode == 6'b000000);
	assign			isREGIMM	=	(opcode == 6'b000001);
	assign			isJtype		=	(opcode[5:1] == 5'b00001);
	assign			isItypeb	=	(opcode[5:2] == 4'b0001);
	assign			isItypec	=	(opcode[5:3] == 3'b001);
	assign			isItypel	=	(opcode[5] & (~opcode[3]));
	assign			isItypes	=	(opcode[5] & opcode[3]);
	assign			islui		=	(opcode == 6'b001111);
	assign			isjalr		=	((isRtype && func == 6'b001001) || opcode == 6'b000011);
	assign			isItypecnl	=	(opcode[5:2] == 4'b0010);
	assign			isItypecl	=	(opcode[5:2] == 4'b0011);
	assign			islwlr		=	(opcode == 6'b100010 || opcode == 6'b100110);
	assign			isj		=	(opcode == 6'b000010 || opcode == 6'b000011);

	//寄存器堆相关
	wire [4:0]		RF_raddr1;	//寄存器堆一号端口读出地址
	wire [4:0]		RF_raddr2;	//寄存器堆二号端口读出地址

	wire [31:0]		RF_rdata1;	//寄存器堆一号端口读出
	wire [31:0]		RF_rdata2;	//寄存器堆二号端口读出

	wire			RF_wen;		//寄存器堆写使能

	wire [4:0]		RF_waddr; 	//寄存器堆写入地址

	wire [31:0]		RF_wdata;	//寄存器堆写入数据

	//数据移动指令处理
	wire 			movn;
	wire 			movz;

	assign			movn 		= 	((isRtype && func == 6'b001011) && RF_rdata2 != 32'b0)	?	 1'b1 :	//movn指令rt读出内容不为0，将rs作为写入数据
									     								 1'b0;
	assign			movz		=	((isRtype && func == 6'b001010) && RF_rdata2 == 32'b0) 	?	 1'b1 : //movz指令rt读出内容为0，将rs作为写入数据
									     								 1'b0;

	//alu相关
	wire [31:0] 		alu_A;		//alu中的A
	wire [31:0] 		alu_B; 		//alu中的B

	wire [2:0] 		alu_op; 	//alu操作码

	wire 			alu_overflow; 	//alu有符号数溢出
	wire			alu_carryout; 	//alu无符号数进位
	wire			alu_zero; 	//alu结果为0

	wire [31:0]		alu_result;	//alu运算结果

	assign 			alu_A	  	= 	RF_rdata1; 
	assign 			alu_B	  	= 	isItypecnl 	     ? se_immediate : //I-type非逻辑类运算指令，与符号位扩展立即数运算
							isItypecl  	     ? zo_immediate : //I-type逻辑运算指令，与零扩展立即数运算
							isItypel || isItypes ? se_offset    : //I-type内存读写指令
								     	       RF_rdata2;     //其他计算，取寄存器二号读出端口	

	assign 			alu_op 	  	=	isItypel || isItypes			   ? 3'b010			: //内存读写地址计算
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

	assign			temp_address	=	(isItypel || isItypes)  ?   alu_result : //读写地址均为立即数+寄存器base
								   		    32'b0;

	assign 			Address 	= 	{temp_address[31:2], 2'b0}; //地址对齐	

	assign			MemRead		=	isItypel;

	assign			MemWrite	=	isItypes;

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
                                                  (temp_address[1:0] == 2'b00)                    ? {Read_data[7:0],  RF_rdata2[23:0]}   : // 把总线最低8位移到寄存器最高8位
                                                  (temp_address[1:0] == 2'b01)                    ? {Read_data[15:0], RF_rdata2[15:0]}   : // 把总线低16位移到寄存器高16位
                                                  (temp_address[1:0] == 2'b10)                    ? {Read_data[23:0], RF_rdata2[7:0]}    : // 把总线低24位移到寄存器高24位
                                                                                                    Read_data                              // 满字直接存入
                                                  ) :
                                                  (opcode[2:0] == 3'b110)                         ? ( // LWR小端序拼接
                                                  (temp_address[1:0] == 2'b00)                    ? Read_data                            : // 满字直接存入
                                                  (temp_address[1:0] == 2'b01)                    ? {RF_rdata2[31:24], Read_data[31:8]}  : // 把总线高24位移到寄存器低24位
                                                  (temp_address[1:0] == 2'b10)                    ? {RF_rdata2[31:16], Read_data[31:16]} : // 把总线高16位移到寄存器低16位
                                                                                                    {RF_rdata2[31:8],  Read_data[31:24]}   // 把总线最高8位移到寄存器最低8位
                                                  ) :
                                                  // 常规指令逻辑
                                                  read_strb == 4'b1111                            ? Read_data 				    :
                                                  read_strb == 4'b0011 & opcode[2:0] != 3'b101    ? {{16{Read_data[15]}},Read_data[15:0]}   : //lh
                                                  read_strb == 4'b0011 & opcode[2:0] == 3'b101    ? {{16{1'b0}},Read_data[15:0]}            : //lhu
                                                  read_strb == 4'b1100 & opcode[2:0] != 3'b101    ? {{16{Read_data[31]}},Read_data[31:16]}  : //lh (高半字)
                                                  read_strb == 4'b1100 & opcode[2:0] == 3'b101    ? {{16{1'b0}},Read_data[31:16]}           : //lhu (高半字)
                                                  read_strb == 4'b0001 & opcode[2:0] != 3'b100    ? {{24{Read_data[7]}},Read_data[7:0]}     : //lb
                                                  read_strb == 4'b0001 & opcode[2:0] == 3'b100    ? {{24{1'b0}},Read_data[7:0]}             : //lbu
                                                  read_strb == 4'b0010 & opcode[2:0] != 3'b100    ? {{24{Read_data[15]}},Read_data[15:8]}   : 
                                                  read_strb == 4'b0010 & opcode[2:0] == 3'b100    ? {{24{1'b0}},Read_data[15:8]}            : 
                                                  read_strb == 4'b0100 & opcode[2:0] != 3'b100    ? {{24{Read_data[23]}},Read_data[23:16]}  : 
                                                  read_strb == 4'b0100 & opcode[2:0] == 3'b100    ? {{24{1'b0}},Read_data[23:16]}           : 
                                                  read_strb == 4'b1000 & opcode[2:0] != 3'b100    ? {{24{Read_data[31]}},Read_data[31:24]}  : 
                                                  read_strb == 4'b1000 & opcode[2:0] == 3'b100    ? {{24{1'b0}},Read_data[31:24]}           : 
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

        assign                  Write_data      = (opcode[2:0] == 3'b010)                         ? ( 				// SWL拼接
                                                  (temp_address[1:0] == 2'b00)                    ? {24'b0, RF_rdata2[31:24]} : // 寄存器最高位 -> 内存最低位
                                                  (temp_address[1:0] == 2'b01)                    ? {16'b0, RF_rdata2[31:16]} : // 寄存器高16位 -> 内存低16位
                                                  (temp_address[1:0] == 2'b10)                    ? {8'b0,  RF_rdata2[31:8]}  : // 寄存器高24位 -> 内存低24位
                                                                                                    RF_rdata2                   // 全字对齐
                                                  									    ) :
                                                  (opcode[2:0] == 3'b110)                         ? ( 				// SWR拼接
                                                  (temp_address[1:0] == 2'b00)                    ? RF_rdata2                 : // 全字对齐
                                                  (temp_address[1:0] == 2'b01)                    ? {RF_rdata2[23:0], 8'b0}   : // 寄存器低24位 -> 内存高24位
                                                  (temp_address[1:0] == 2'b10)                    ? {RF_rdata2[15:0], 16'b0}  : // 寄存器低16位 -> 内存高16位
                                                                                                    {RF_rdata2[7:0],  24'b0}    // 寄存器最低位 -> 内存最高位
                                                  									    ) :
                                                  // 常规指令逻辑
                                                  (Write_strb == 4'b1111)                         ? RF_rdata2 		            :
                                                  (Write_strb == 4'b0011)                         ? {16'b0, RF_rdata2[15:0]}        : //sh (低半字)
                                                  (Write_strb == 4'b1100)                         ? {RF_rdata2[15:0], 16'b0}        : //sh (高半字)
                                                  (Write_strb == 4'b0001)                         ? {24'b0, RF_rdata2[7:0]}  	    : //sb (byte 0)
                                                  (Write_strb == 4'b0010)                         ? {16'b0, RF_rdata2[7:0],  8'b0}  : //sb (byte 1)
                                                  (Write_strb == 4'b0100)                         ? {8'b0,  RF_rdata2[7:0], 16'b0}  : //sb (byte 2)
                                                  (Write_strb == 4'b1000)                         ? {RF_rdata2[7:0], 24'b0}  	    : //sb (byte 3)
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

	assign			shifter_A 	=	RF_rdata2;			   	   //寄存器堆一号端口读出作为被位移数
	assign			shifter_B	=	func[2] == 1'b1 ? RF_rdata1[4:0]: 	   //sllv等，用寄存器堆一号端口的读出前五位做位移长度
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
							
	assign 			RF_wen    	= 	(movn == 1) || (movz == 1)				? 1'b1		:	//数据移动指令
							isRtype && (func[5] == 1'b1 || func[5:3] == 3'b000) 	? 1'b1		:	//R-type运算/位移指令
							isjalr							? 1'b1		:	//J-type jal/jalr指令
							islui							? 1'b1		:	//lui
							isItypec						? 1'b1		:	//I-type计算
							isItypel						? 1'b1		:	//I-type内存读
														  1'b0;

	assign 			RF_waddr  	=	(movn == 1) || (movz == 1)				? rd		:	//数据移动指令
							isRtype 						? rd 		:	//R-type
							isjalr							? 5'b11111	:	//J-type jal/jalr指令
							islui							? rt		:	//lui
							isItypec						? rt		:	//I-type计算
							isItypel						? rt		:	//I-type内存读
														  5'b00000;

	assign 			RF_wdata	= 	isjalr							? PC + 8	:       //jal或jalr写入PC + 8
							isItypel						? mem_data	: 	//I-type内存读
							(movn == 1) || (movz == 1)				? RF_rdata1	:	//位移指令处理
							islui			       				? lm_immediate 	: 	//lui单独处理
							(isItypec || (isRtype && func[5:3] != 3'b0)) 		? alu_result	: 	//计算类非位移指令，alu计算结果作为写入数据
							isRtype && func[5:3] == 3'b0				? shifter_result:	//计算类位移指令
														  32'b0;

	//分支指令处理
	wire			branch;		//branch命令，1表示执行分支，0表示不执行

	assign			branch		=	(opcode == 6'b000101 && (RF_rdata1 != RF_rdata2)) 						? 1'b1 : //bne
							(opcode == 6'b000100 && (RF_rdata1 == RF_rdata2))				  		? 1'b1 : //beq
							(opcode == 6'b000110 && (RF_rdata1 == 32'b0 || RF_rdata1[31] == 1'b1))  			? 1'b1 : //blez
							(opcode == 6'b000111 && (RF_rdata1[31] == 1'b0 && RF_rdata1 != 0))						? 1'b1 : //bgtz
							((opcode == 6'b000001 && rt == 5'b00000) && (RF_rdata1[31] == 1'b1))				? 1'b1 : //bltz
							((opcode == 6'b000001 && rt == 5'b00001) && (RF_rdata1[31] == 1'b0 || RF_rdata1 == 32'b0))	? 1'b1 : //bgez
																			  1'b0;

	//跳转指令处理
	wire			jump;		//jump命令，1表示执行跳转，0表示不执行

	wire [31:0]		jump_address;	//跳转的目标地址

	wire [31:0]		PC_plus4;	//用于跳转地址拼接

	assign			PC_plus4	=	PC_reg + 4;

	assign			jump		=	isJtype || (isRtype && (func == 6'b001000 || func == 6'b001001)); //R-type的跳转指令或J-type的跳转指令

	assign			jump_address	=	isj 			? {PC_plus4[31:28],instr_index,2'b00} : //j指令/jal指令，写入计算后的地址
							isRtype 		? RF_rdata1			      : //jr/jalr指令，写入寄存器堆rs处的地址
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

	always @(posedge clk) begin //程序计数器
		if (rst == 1'b1) begin
			PC_reg <= 32'b0;
		end
		else begin
			if (branch == 1'b1) begin //分支处理
				PC_reg <= PC_reg + 4 + se_target_offset;
			end
			else if (jump == 1'b1) begin //跳转处理
				PC_reg <= jump_address;
			end
			else begin
				PC_reg <= PC_reg + 4;
			end
		end 
	end
	assign PC = PC_reg;

endmodule
