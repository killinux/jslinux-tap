/*
JSLinux-tap - An annotated version of the original JSLinux.

Original is Copyright (c) 2011-2012 Fabrice Bellard
Redistribution or commercial use is prohibited without the author's permission.

Serial Controller Emulator
add by hao:
     串口的驱动,设备/dev/clipboard 用串口驱动链接浏览器部分的代码,参考编译内核的jsclipboard部分
*/

function Serial(Ng, mem8_loc, kh, lh) {
    this.divider = 0;
    this.rbr = 0;
    this.ier = 0;
    this.iir = 0x01;
    this.lcr = 0;
    this.mcr = 0; //modify by hao
    this.lsr = 0x40 | 0x20;
    this.msr = 0;
    this.scr = 0;
    this.fcr = 0;//add by hao
    this.set_irq_func = kh;
    this.write_func = lh;
    //this.receive_fifo = "";
//add by hao begin
    this.tx_fifo = "";
    this.rx_fifo = "";
    this.myOwnFA = mem8_loc;
//add by hao end
    //Ng.register_ioport_write(0x3f8, 8, 1, this.ioport_write.bind(this));
    //Ng.register_ioport_read(0x3f8, 8, 1, this.ioport_read.bind(this));
    
    Ng.register_ioport_write(mem8_loc, 8, 1, this.ioport_write.bind(this));
    Ng.register_ioport_read(mem8_loc, 8, 1, this.ioport_read.bind(this));
}
Serial.prototype.update_irq = function() {
    if ((this.lsr & 0x01) && (this.ier & 0x01)) {
        this.iir = 0x04;
    } else if ((this.lsr & 0x20) && (this.ier & 0x02)) {
        this.iir = 0x02;
    } else {
        this.iir = 0x01;
    }
    if (this.iir != 0x01) {
        this.set_irq_func(1);
    } else {
        this.set_irq_func(0);
    }
};

//add by hao write_tx_fifo begin
Serial.prototype.write_tx_fifo = function() {
    if (this.tx_fifo != "") {
        this.write_func(this.tx_fifo);
        this.tx_fifo = "";
        this.lsr |= 0x20;
        this.lsr |= 0x40;
        this.update_irq();
    }
};

var __testserial2_toggle = false;//hao
//add by hao write_tx_fifo end
Serial.prototype.ioport_write = function(mem8_loc, x) {
    mem8_loc &= 7;
//add by hao for serial2 color change begin
    if (this.myOwnFA == 0x2f8) {
        if (__testserial2_toggle) document.getElementById("test_serial2").style.backgroundColor = "red";
        else document.getElementById("test_serial2").style.backgroundColor = "white";
        __testserial2_toggle = !__testserial2_toggle;
    }
//add by hao for serial2 color change end
    switch (mem8_loc) {
        default:
        case 0:
            if (this.lcr & 0x80) {
                this.divider = (this.divider & 0xff00) | x;
            } else {
            	//add by hao have no idea begin
            	if (this.fcr & 0x01) { //hao ?
	                this.tx_fifo += String.fromCharCode(x);
	                this.lsr &= ~0x20;
	                this.update_irq();
	                if (this.tx_fifo.length >= 16) {
	                    this.write_tx_fifo();
	                }
	            } else {
	           	//add by hao have no idea end
	                this.lsr &= ~0x20;
	                this.update_irq();
	                this.write_func(String.fromCharCode(x));
	                this.lsr |= 0x20;
	                this.lsr |= 0x40;
	                this.update_irq();
	            }
	       }// add by hao
            break;
        case 1:
            if (this.lcr & 0x80) {
                this.divider = (this.divider & 0x00ff) | (x << 8);
            } else {
                this.ier = x;
                this.update_irq();
            }
            break;
        case 2:
        	//add by hao have no idea begin
        	if ((this.fcr ^ x) & 0x01) {
	            x |= 0x04 | 0x02;
	        }
	        if (x & 0x04) this.tx_fifo = "";
	        if (x & 0x02) this.rx_fifo = "";
	        this.fcr = x & 0x01;
        	//add by hao have no idea end
            break;
        case 3:
            this.lcr = x;
            break;
        case 4:
            this.mcr = x;
            break;
        case 5:
            break;
        case 6:
            this.msr = x;
            break;
        case 7:
            this.scr = x;
            break;
    }
};
Serial.prototype.ioport_read = function(mem8_loc) {
    var Pg;
    mem8_loc &= 7;
    switch (mem8_loc) {
        default:
        case 0:
            if (this.lcr & 0x80) {
                Pg = this.divider & 0xff;
            } else {
                Pg = this.rbr;
                this.lsr &= ~(0x01 | 0x10);
                this.update_irq();
                this.send_char_from_fifo();
            }
            break;
        case 1:
            if (this.lcr & 0x80) {
                Pg = (this.divider >> 8) & 0xff;
            } else {
                Pg = this.ier;
            }
            break;
        case 2:
            Pg = this.iir;
            if (this.fcr & 0x01) Pg |= 0xC0;//add by hao
            break;
        case 3:
            Pg = this.lcr;
            break;
        case 4:
            Pg = this.mcr;
            break;
        case 5:
            Pg = this.lsr;
            break;
        case 6:
            Pg = this.msr;
            break;
        case 7:
            Pg = this.scr;
            break;
    }
    return Pg;
};
Serial.prototype.send_break = function() {
    this.rbr = 0;
    this.lsr |= 0x10 | 0x01;
    this.update_irq();
};
Serial.prototype.send_char = function(mh) {
    this.rbr = mh;
    this.lsr |= 0x01;
    this.update_irq();
};
/*
//hao modify
Serial.prototype.send_char_from_fifo = function() {
    var nh;
    nh = this.receive_fifo;
    if (nh != "" && !(this.lsr & 0x01)) {
        this.send_char(nh.charCodeAt(0));
        this.receive_fifo = nh.substr(1, nh.length - 1);
    }
};
Serial.prototype.send_chars = function(na) {
    this.receive_fifo += na;
    this.send_char_from_fifo();
};
*/
Serial.prototype.send_char_from_fifo = function() { //hao weijiejue
    var kh;
    kh = this.rx_fifo;
    if (kh != "" && !(this.lsr & 0x01)) {
        this.send_char(kh.charCodeAt(0));
        this.rx_fifo = kh.substr(1, kh.length - 1);
    }
};
Serial.prototype.send_chars = function(na) { //hao weijiejue
    this.rx_fifo += na;
    this.send_char_from_fifo();
};
