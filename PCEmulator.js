/*
JSLinux-deobfuscated - An annotated version of the original JSLinux.

Original is Copyright (c) 2011-2012 Fabrice Bellard
Redistribution or commercial use is prohibited without the author's permission.

Main PC Emulator Routine
*/

// used as callback wrappers for emulated PIT and PIC chips
function set_hard_irq_wrapper(irq) { this.hard_irq = irq;}
function return_cycle_count() { return this.cycle_count; }
//add by hao have no idea begin 
function unix_array(n) {
    return new Uint8Array(n);
}
//add by hao have no idea end

//add by hao sector begin
//////////////pc_disk
pc_disk.prototype.identify = function() {
    function rh(sh, v) {
        th[sh * 2] = v & 0xff;
        th[sh * 2 + 1] = (v >> 8) & 0xff;
    }

    function uh(begin, str, len) {
        var i, v;
        for (i = 0; i < len; i++) {
            if (i < str.length) {
                v = str.charCodeAt(i) & 0xff;
            } else {
                v = 32;
            }
            th[begin * 2 + (i ^ 1)] = v;
        }
    }
    var th, i, vh;
    th = this.io_buffer;//hao importent
    for (i = 0; i < 512; i++) th[i] = 0;
    rh(0, 0x0040);
    rh(1, this.cylinders);
    rh(3, this.heads);
    rh(4, 512 * this.sectors);
    rh(5, 512);
    rh(6, this.sectors);
    rh(20, 3);
    rh(21, 512);
    rh(22, 4);
    uh(27, "JSLinux HARDDISK", 40); //hao display memeray?
    rh(47, 0x8000 | 128);
    rh(48, 0);
    rh(49, 1 << 9);
    rh(51, 0x200);
    rh(52, 0x200);
    rh(54, this.cylinders);
    rh(55, this.heads);
    rh(56, this.sectors);
    vh = this.cylinders * this.heads * this.sectors;
    rh(57, vh);
    rh(58, vh >> 16);
    if (this.mult_sectors) rh(59, 0x100 | this.mult_sectors);
    rh(60, this.nb_sectors);
    rh(61, this.nb_sectors >> 16);
    rh(80, (1 << 1) | (1 << 2));
    rh(82, (1 << 14));
    rh(83, (1 << 14));
    rh(84, (1 << 14));
    rh(85, (1 << 14));
    rh(86, 0);
    rh(87, (1 << 14));
};
pc_disk.prototype.set_signature = function() {
    this.select &= 0xf0;
    this.nsector = 1;
    this.sector = 1;
    this.lcyl = 0;
    this.hcyl = 0;
};
pc_disk.prototype.abort_command = function() {
    this.status = 0x40 | 0x01;
    this.error = 0x04;
};
pc_disk.prototype.set_irq = function() {
    if (! (this.cmd & 0x02)) {
        this.ide_if.set_irq_func(1);
    }
};
pc_disk.prototype.transfer_start = function(wh, xh) {
    this.end_transfer_func = xh;
    this.data_index = 0;
    this.data_end = wh;
};
pc_disk.prototype.transfer_stop = function() {
    this.end_transfer_func = this.transfer_stop.bind(this);
    this.data_index = 0;
    this.data_end = 0;
};
pc_disk.prototype.get_sector = function() {
    var yh;
    if (this.select & 0x40) {
        yh = ((this.select & 0x0f) << 24) | (this.hcyl << 16) | (this.lcyl << 8) | this.sector;
    } else {
        yh = ((this.hcyl << 8) | this.lcyl) * this.heads * this.sectors + (this.select & 0x0f) * this.sectors + (this.sector - 1);
    }
    return yh;
};
pc_disk.prototype.set_sector = function(yh) {
    var zh, r;
    if (this.select & 0x40) {
        this.select = (this.select & 0xf0) | ((yh >> 24) & 0x0f);
        this.hcyl = (yh >> 16) & 0xff;
        this.lcyl = (yh >> 8) & 0xff;
        this.sector = yh & 0xff;
    } else {
        zh = yh / (this.heads * this.sectors);
        r = yh % (this.heads * this.sectors);
        this.hcyl = (zh >> 8) & 0xff;
        this.lcyl = zh & 0xff;
        this.select = (this.select & 0xf0) | ((r / this.sectors) & 0x0f);
        this.sector = (r % this.sectors) + 1;
    }
};
pc_disk.prototype.sector_read = function() {
    var yh, n, Mg;
    yh = this.get_sector();
    n = this.nsector;
    if (n == 0) n = 256;
    if (n > this.req_nb_sectors) n = this.req_nb_sectors;
    this.io_nb_sectors = n;
    Mg = this.bs.read_async(yh, this.io_buffer, n, this.sector_read_cb.bind(this));
    if (Mg < 0) {
        this.abort_command();
        this.set_irq();
    } else if (Mg == 0) {
        this.sector_read_cb();
    } else {
        this.status = 0x40 | 0x10 | 0x80;
        this.error = 0;
    }
};
pc_disk.prototype.sector_read_cb = function() {
    var n, Ah;
    n = this.io_nb_sectors;
    this.set_sector(this.get_sector() + n);
    this.nsector = (this.nsector - n) & 0xff;
    if (this.nsector == 0) Ah = this.sector_read_cb_end.bind(this);
    else Ah = this.sector_read.bind(this);
    this.transfer_start(512 * n, Ah);
    this.set_irq();
    this.status = 0x40 | 0x10 | 0x08;
    this.error = 0;
};
pc_disk.prototype.sector_read_cb_end = function() {
    this.status = 0x40 | 0x10;
    this.error = 0;
    this.transfer_stop();
};
pc_disk.prototype.sector_write_cb1 = function() {
    var yh, Mg;
    this.transfer_stop();
    yh = this.get_sector();
    Mg = this.bs.write_async(yh, this.io_buffer, this.io_nb_sectors, this.sector_write_cb2.bind(this));
    if (Mg < 0) {
        this.abort_command();
        this.set_irq();
    } else if (Mg == 0) {
        this.sector_write_cb2();
    } else {
        this.status = 0x40 | 0x10 | 0x80;
    }
};
pc_disk.prototype.sector_write_cb2 = function() {
    var n;
    n = this.io_nb_sectors;
    this.set_sector(this.get_sector() + n);
    this.nsector = (this.nsector - n) & 0xff;
    if (this.nsector == 0) {
        this.status = 0x40 | 0x10;
    } else {
        n = this.nsector;
        if (n > this.req_nb_sectors) n = this.req_nb_sectors;
        this.io_nb_sectors = n;
        this.transfer_start(512 * n, this.sector_write_cb1.bind(this));
        this.status = 0x40 | 0x10 | 0x08;
    }
    this.set_irq();
};
pc_disk.prototype.sector_write = function() {
    var n;
    n = this.nsector;
    if (n == 0) n = 256;
    if (n > this.req_nb_sectors) n = this.req_nb_sectors;
    this.io_nb_sectors = n;
    this.transfer_start(512 * n, this.sector_write_cb1.bind(this));
    this.status = 0x40 | 0x10 | 0x08;
};
pc_disk.prototype.identify_cb = function() {
    this.transfer_stop();
    this.status = 0x40;
};
pc_disk.prototype.exec_cmd = function(ga) {
    var n;
    switch (ga) {
    case 0xA1:
    case 0xEC:
        this.identify();
        this.status = 0x40 | 0x10 | 0x08;
        this.transfer_start(512, this.identify_cb.bind(this));
        this.set_irq();
        break;
    case 0x91:
    case 0x10:
        this.error = 0;
        this.status = 0x40 | 0x10;
        this.set_irq();
        break;
    case 0xC6:
        if (this.nsector > 128 || (this.nsector & (this.nsector - 1)) != 0) {
            this.abort_command();
        } else {
            this.mult_sectors = this.nsector;
            this.status = 0x40;
        }
        this.set_irq();
        break;
    case 0x20:
    case 0x21:
        this.req_nb_sectors = 1;
        this.sector_read();
        break;
    case 0x30:
    case 0x31:
        this.req_nb_sectors = 1;
        this.sector_write();
        break;
    case 0xC4:
        if (!this.mult_sectors) {
            this.abort_command();
            this.set_irq();
        } else {
            this.req_nb_sectors = this.mult_sectors;
            this.sector_read();
        }
        break;
    case 0xC5:
        if (!this.mult_sectors) {
            this.abort_command();
            this.set_irq();
        } else {
            this.req_nb_sectors = this.mult_sectors;
            this.sector_write();
        }
        break;
    case 0xF8:
        this.set_sector(this.nb_sectors - 1);
        this.status = 0x40;
        this.set_irq();
        break;
    default:
        this.abort_command();
        this.set_irq();
        break;
    }
};
//add by hao sector end

//add by hao ide0 begin
//////////////ide_driver
ide_driver.prototype.ioport_write = function(fa, ga) {
    var s = this.cur_drive;
    var Ch;
    fa &= 7;
    switch (fa) {
    case 0:
        break;
    case 1:
        if (s) {
            s.feature = ga;
        }
        break;
    case 2:
        if (s) {
            s.nsector = ga;
        }
        break;
    case 3:
        if (s) {
            s.sector = ga;
        }
        break;
    case 4:
        if (s) {
            s.lcyl = ga;
        }
        break;
    case 5:
        if (s) {
            s.hcyl = ga;
        }
        break;
    case 6:
        s = this.cur_drive = this.drives[(ga >> 4) & 1];
        if (s) {
            s.select = ga;
        }
        break;
    default:
    case 7:
        if (s) {
            s.exec_cmd(ga);
        }
        break;
    }
};
ide_driver.prototype.ioport_read = function(fa) {
    var s = this.cur_drive;
    var Mg;
    fa &= 7;
    if (!s) {
        Mg = 0xff;
    } else {
        switch (fa) {
        case 0:
            Mg = 0xff;
            break;
        case 1:
            Mg = s.error;
            break;
        case 2:
            Mg = s.nsector;
            break;
        case 3:
            Mg = s.sector;
            break;
        case 4:
            Mg = s.lcyl;
            break;
        case 5:
            Mg = s.hcyl;
            break;
        case 6:
            Mg = s.select;
            break;
        default:
        case 7:
            Mg = s.status;
            this.set_irq_func(0);
            break;
        }
    }
    return Mg;
};
ide_driver.prototype.status_read = function(fa) {
    var s = this.cur_drive;
    var Mg;
    if (s) {
        Mg = s.status;
    } else {
        Mg = 0;
    }
    return Mg;
};
ide_driver.prototype.cmd_write = function(fa, ga) {
    var i, s;
    if (! (this.cmd & 0x04) && (ga & 0x04)) {
        for (i = 0; i < 2; i++) {
            s = this.drives[i];
            if (s) {
                s.status = 0x80 | 0x10;
                s.error = 0x01;
            }
        }
    } else if ((this.cmd & 0x04) && !(ga & 0x04)) {
        for (i = 0; i < 2; i++) {
            s = this.drives[i];
            if (s) {
                s.status = 0x40 | 0x10;
                s.set_signature();
            }
        }
    }
    for (i = 0; i < 2; i++) {
        s = this.drives[i];
        if (s) {
            s.cmd = ga;
        }
    }
};
ide_driver.prototype.data_writew = function(fa, ga) {
    var s = this.cur_drive;
    var p, th;
    if (!s) return;
    p = s.data_index;
    th = s.io_buffer;
    th[p] = ga & 0xff;
    th[p + 1] = (ga >> 8) & 0xff;
    p += 2;
    s.data_index = p;
    if (p >= s.data_end) s.end_transfer_func();
};
ide_driver.prototype.data_readw = function(fa) {
    var s = this.cur_drive;
    var p, Mg, th;
    if (!s) {
        Mg = 0;
    } else {
        p = s.data_index;
        th = s.io_buffer;
        Mg = th[p] | (th[p + 1] << 8);
        p += 2;
        s.data_index = p;
        if (p >= s.data_end) s.end_transfer_func();
    }
    return Mg;
};
ide_driver.prototype.data_writel = function(fa, ga) {
    var s = this.cur_drive;
    var p, th;
    if (!s) return;
    p = s.data_index;
    th = s.io_buffer;
    th[p] = ga & 0xff;
    th[p + 1] = (ga >> 8) & 0xff;
    th[p + 2] = (ga >> 16) & 0xff;
    th[p + 3] = (ga >> 24) & 0xff;
    p += 4;
    s.data_index = p;
    if (p >= s.data_end) s.end_transfer_func();
};
ide_driver.prototype.data_readl = function(fa) {
    var s = this.cur_drive;
    var p, Mg, th;
    if (!s) {
        Mg = 0;
    } else {
        p = s.data_index;
        th = s.io_buffer;
        Mg = th[p] | (th[p + 1] << 8) | (th[p + 2] << 16) | (th[p + 3] << 24);
        p += 4;
        s.data_index = p;
        if (p >= s.data_end) s.end_transfer_func();
    }
    return Mg;
};

function pc_disk(that, b_list) {
    var Fh, Gh;
    this.ide_if = that;
    this.bs = b_list;
    Gh = b_list.get_sector_count();
    Fh = Gh / (16 * 63);
    if (Fh > 16383) Fh = 16383;
    else if (Fh < 2) Fh = 2;
    this.cylinders = Fh;
    this.heads = 16;
    this.sectors = 63;
    this.nb_sectors = Gh;
    this.mult_sectors = 128;
    this.feature = 0;
    this.error = 0;
    this.nsector = 0;
    this.sector = 0;
    this.lcyl = 0;
    this.hcyl = 0;
    this.select = 0xa0;
    this.status = 0x40 | 0x10;
    this.cmd = 0;
    this.io_buffer = unix_array(128 * 512 + 4);//hao
    this.data_index = 0;
    this.data_end = 0;
    this.end_transfer_func = this.transfer_stop.bind(this);//hao
    this.req_nb_sectors = 0;
    this.io_nb_sectors = 0;
}
//ide_driver(this, 0x1f0, 0x3f6, this.pic.set_irq.bind(this.pic, 14), block_list);
//http://wiki.osdev.org/PCI_IDE_Controller
function ide_driver(this_pc, fa, Hh, set_irq_function, block_list) {//ide0
    var i, disk_drive;
    this.set_irq_func = set_irq_function;
    this.drives = [];
    for (i = 0; i < 2; i++) {
        if (block_list[i]) {
            disk_drive = new pc_disk(this, block_list[i]);//hao
        } else {
            disk_drive = null;
        }
        this.drives[i] = disk_drive;
    }
    this.cur_drive = this.drives[0];
    this_pc.register_ioport_write(fa, 8, 1, this.ioport_write.bind(this));
    this_pc.register_ioport_read(fa, 8, 1, this.ioport_read.bind(this));
    if (Hh) {
        this_pc.register_ioport_read(Hh, 1, 1, this.status_read.bind(this));
        this_pc.register_ioport_write(Hh, 1, 1, this.cmd_write.bind(this));
    }
    this_pc.register_ioport_write(fa, 2, 2, this.data_writew.bind(this));
    this_pc.register_ioport_read(fa, 2, 2, this.data_readw.bind(this));
    this_pc.register_ioport_write(fa, 4, 4, this.data_writel.bind(this));
    this_pc.register_ioport_read(fa, 4, 4, this.data_readl.bind(this));
}
//add by hao ide0 end
//add by hao read disk begin
//block_size nb_blocks
function create_block_list(block_url, block_size, nb_blocks) {
    if (block_url.indexOf("%d") < 0) throw "Invalid URL";
    if (nb_blocks <= 0 || block_size <= 0) throw "Invalid parameters";
    this.block_sectors = block_size * 2;
    this.nb_sectors = this.block_sectors * nb_blocks;
    this.url = block_url;
    this.max_cache_size = Math.max(1, Math.ceil(2536 / block_size));
    this.cache = new Array();
    this.sector_num = 0;
    this.sector_index = 0;
    this.sector_count = 0;
    this.sector_buf = null;
    this.sector_cb = null;
}
create_block_list.prototype.get_sector_count = function() {
    return this.nb_sectors;
};
create_block_list.prototype.get_time = function() {
    return + new Date();
};
create_block_list.prototype.get_cached_block = function(Nh) {
    var Oh, i, Ph = this.cache;
    for (i = 0; i < Ph.length; i++) {
        Oh = Ph[i];
        if (Oh.block_num == Nh) return Oh;
    }
    return null;
};
create_block_list.prototype.new_cached_block = function(Nh) {
    var Oh, Qh, i, j, Rh, Ph = this.cache;
    Oh = new Object();
    Oh.block_num = Nh;
    Oh.time = this.get_time();
    if (Ph.length < this.max_cache_size) {
        j = Ph.length;
    } else {
        for (i = 0; i < Ph.length; i++) {
            Qh = Ph[i];
            if (i == 0 || Qh.time < Rh) {
                Rh = Qh.time;
                j = i;
            }
        }
    }
    Ph[j] = Oh;
    return Oh;
};
create_block_list.prototype.get_url = function(this_url, number) {
    var p, s;
    s = number.toString();
    while (s.length < 9) s = "0" + s;
    p = this_url.indexOf("%d");
    return this_url.substr(0, p) + s + this_url.substring(p + 2, this_url.length);
};
create_block_list.prototype.read_async_cb = function(Sh) {
    var Nh, l, ue, Oh, i, Th, Uh, Vh, Wh;
    var Xh, Dg;
    while (this.sector_index < this.sector_count) {
        Nh = Math.floor(this.sector_num / this.block_sectors);
        Oh = this.get_cached_block(Nh);
        if (Oh) {
            ue = this.sector_num - Nh * this.block_sectors;
            l = Math.min(this.sector_count - this.sector_index, this.block_sectors - ue);
            Th = l * 512;
            Uh = this.sector_buf;
            Vh = this.sector_index * 512;
            Wh = Oh.buf;
            Xh = ue * 512;
            for (i = 0; i < Th; i++) {
                Uh[i + Vh] = Wh[i + Xh];
            }
            this.sector_index += l;
            this.sector_num += l;
        } else {
            Dg = this.get_url(this.url, Nh);
            //load_binary(Dg, this.read_async_cb2.bind(this));
            load_binary_remote(Dg, this.read_async_cb2.bind(this));
            return;
        }
    }
    this.sector_buf = null;
    if (!Sh) {
        this.sector_cb(0);
    }
};
create_block_list.prototype.add_block = function(num, data, data_len) {
    var Oh, Yh, i;
    Oh = this.new_cached_block(num);
    Yh = Oh.buf = unix_array(this.block_sectors * 512);
    if (typeof data == "string") {
        for (i = 0; i < data_len; i++) Yh[i] = data.charCodeAt(i) & 0xff;
    } else {
        for (i = 0; i < data_len; i++) Yh[i] = data[i];
    }
};
create_block_list.prototype.read_async_cb2 = function(Gg, ng) {
    var Nh;
    if (ng < 0 || ng != (this.block_sectors * 512)) {
        this.sector_cb( - 1);
    } else {
        Nh = Math.floor(this.sector_num / this.block_sectors);
        this.add_block(Nh, Gg, ng);
        this.read_async_cb(false);
    }
};
create_block_list.prototype.read_async = function(yh, Yh, n, Zh) {
    if ((yh + n) > this.nb_sectors) return - 1;
    var hdd_debug = document.getElementById('hdd_debug');
    hdd_debug.innerHTML = 'r - reading ' + n + ' sectors after sector ' + yh;
    this.sector_num = yh;
    this.sector_buf = Yh;
    this.sector_index = 0;
    this.sector_count = n;
    this.sector_cb = Zh;
    this.read_async_cb(true);
    if (this.sector_index >= this.sector_count) {
        return 0;
    } else {
        return 1;
    }
};
create_block_list.prototype.preload = function(block_list, next_func) {
    var i, block_name, num;
    if (block_list.length == 0) {
        setTimeout(next_func, 0);
    } else {
        this.preload_cb2 = next_func;
        this.preload_count = block_list.length;
        for (i = 0; i < block_list.length; i++) {
            num = block_list[i];
            block_name = this.get_url(this.url, num);
            //load_binary(block_name, this.preload_cb.bind(this, num));
            load_binary_remote(block_name, this.preload_cb.bind(this, num));
        }
    }
};
create_block_list.prototype.preload_cb = function(num, data, data_len) {//hao
    console.log("preload_cb:"+data_len);
    if (data_len < 0) {} else {
        this.add_block(num, data, data_len);
        this.preload_count--;
        if (this.preload_count == 0) {
            this.preload_cb2(0);
        }
    }
};
create_block_list.prototype.write_async = function(yh, Yh, n, Zh) { //hao
    var hdd_debug = document.getElementById('hdd_debug');
    hdd_debug.innerHTML = 'w - writing ' + n + ' sectors after sector ' + ide_driver;
    // 
    // dd if=/dev/zero of=/dev/hda bs=512 count=4 seek=1268 && sync
    // yh = first sector
    // n = sector count
    // Yh = data
    // Zh = callback - determine: what for?
    return - 1;
};
//add by hao read disk end

//add by hao net0 begin
network_driver.prototype.reset = function() {
    this.isr = 0x80;
};
network_driver.prototype.update_irq = function() {
    var bi;
    bi = (this.isr & this.imr) & 0x7f;
    if (bi) this.set_irq_func(1);
    else this.set_irq_func(0);
};
network_driver.prototype.compute_mcast_idx = function(ci) {
    var di, ac, i, j, b;
    di = -1;
    for (i = 0; i < 6; i++) {
        b = ci[i];
        for (j = 0; j < 8; j++) {
            ac = (di >>> 31) ^ (b & 0x01);
            di <<= 1;
            b >>= 1;
            if (ac) di = (di ^ 0x04c11db6) | ac;
        }
    }
    return di >>> 26;
};
network_driver.prototype.buffer_full = function() {
    var ei, Rb, fi;
    Rb = this.curpag << 8;
    fi = this.boundary << 8;
    if (Rb < fi) ei = fi - Rb;
    else ei = (this.stop - this.start) - (Rb - fi);
    return (ei < (1514 + 4));
};
network_driver.prototype.receive_packet = function(Yh) {//hao
    // http://compbio.cs.toronto.edu/repos/snowflock/xen-3.0.3/tools/ioemu/hw/ne2000.c
    var gi, hi, ng, Rb, ii, wh, ji, fa;
    var ki, i;

    wh = Yh.length;
    console.log("ne2000: receiving " + wh + " bytes");
    if (this.cmd & 0x01 || this.buffer_full() || wh < 6) {
        console.log("ne2000: either stop command, or buffer full, or received less than 6 bytes");
        return;
    }

    // what does RX configuration register contain?
    if (this.rxcr & 0x10) {
        // promiscuous: receive all
    } else {
        if (Yh[0] == 0xff && Yh[1] == 0xff && Yh[2] == 0xff && Yh[3] == 0xff && Yh[4] == 0xff && Yh[5] == 0xff) {
            console.log("ne2000: broadcast mac address");
            if (! (this.rxcr & 0x04)) {
                console.log("ne2000: rxcr not set up to receive broadcast");
                return;
            }
        } else if (Yh[0] & 0x01) {
            // multicast address
            console.log("ne2000: multicast mac address");
            if (! (this.rxcr & 0x08)) {
                console.log("ne2000: rxcr not set up to receive multicast");
                return;
            }
            ii = li(Yh);
            if (! (this.mult[ii >> 3] & (1 << (ii & 7)))) return;
        } else if (this.phys[0] == Yh[0] && this.phys[1] == Yh[1] && this.phys[2] == Yh[2] && this.phys[3] == Yh[3] && this.phys[4] == Yh[4] && this.phys[5] == Yh[5]) {
            console.log("ne2000: mac address is correct");
        } else {
            console.log("ne2000: ignoring wrong mac address");
            return;
        }
    }
    if (wh < 60) wh = 60; // grow min buffer
    Rb = this.curpag << 8;
    ji = this.mem;//hao 
    gi = wh + 4; // 4 bytes for header
    hi = Rb + ((gi + 4 + 255) & ~0xff); // address for next packet
    if (hi >= this.stop) hi -= (this.stop - this.start);
    this.rsr = 0x01; // receive status: enrsr_rxok
    if (Yh[0] & 0x01) this.rsr |= 0x20; // rsr |= enrsr_phy
    fa = Rb & 0x7fff; // fa = index & 0x7fff (not in ne2000.c!)
    if (fa >= 0x4000) { // not under if in ne2000.c
        ji[fa] = this.rsr & 0xff;
        ji[fa + 1] = (hi >> 8) & 0xff;
        ji[fa + 2] = gi & 0xff;
        ji[fa + 3] = (gi >> 8) & 0xff;
    }
    Rb += 4; // index += 4
    ki = 0; // This was missing! not sure what's the difference from Rb
    while (wh > 0) { // write packet data
        if (Rb >= this.stop) break;
        ng = Math.min(wh, this.stop - Rb);
        if (ki < Yh.length) ng = Math.min(ng, Yh.length - ki);
        ng = Math.min(ng, 0x4000 - (Rb & 0x3fff));
        fa = Rb & 0x7fff;
        if (fa >= 0x4000) {
            if (ki < Yh.length) {
                for (i = 0; i < ng; i++) ji[fa + i] = Yh[ki + i];
                console.log("ne2000: wrote " + ng + " bytes");
            } else {
                for (i = 0; i < ng; i++) ji[fa + i] = 0;
                console.log("ne2000: wrote " + ng + " zeroes");
            }
        }
        ki += ng;
        Rb += ng;
        if (Rb == this.stop) Rb = this.start;
        wh -= ng;
    }
    this.curpag = hi >> 8;
    this.isr |= 0x01;
    this.update_irq();
    console.log("ne2000: packet has been received");
};
network_driver.prototype.send_packet = function() {
    var Rb;
    Rb = (this.tpsr << 8) & 0x7fff;
    if (Rb + this.tcnt <= (32 * 1024)) {
        this.send_packet_func(this.mem, Rb, this.tcnt);
    }
    this.tsr = 0x01;//hao (Terminate and Stay Resident Program) ?
    this.isr |= 0x02;//Interrupt Service Routines 
    this.cmd &= ~0x04;
    this.update_irq();
};
network_driver.prototype.ioport_write = function(fa, ga) {
    var ue, mi;
    fa &= 0xf;
    if (fa == 0x00) {
        this.cmd = ga;
        if (! (ga & 0x01)) {
            this.isr &= ~0x80;
            if ((ga & (0x08 | 0x10)) && this.rcnt == 0) {
                this.isr |= 0x40;
                this.update_irq();
            }
            if (ga & 0x04) {
                this.send_packet();
            }
        }
    } else {
        mi = this.cmd >> 6;
        ue = fa | (mi << 4);
        switch (ue) {
        case 0x01:
            this.start = ga << 8;
            break;
        case 0x02:
            this.stop = ga << 8;
            break;
        case 0x03:
            this.boundary = ga;
            break;
        case 0x0f:
            this.imr = ga;
            this.update_irq();
            break;
        case 0x04:
            this.tpsr = ga;
            break;
        case 0x05:
            this.tcnt = (this.tcnt & 0xff00) | ga;
            break;
        case 0x06:
            this.tcnt = (this.tcnt & 0x00ff) | (ga << 8);
            break;
        case 0x08:
            this.rsar = (this.rsar & 0xff00) | ga;
            break;
        case 0x09:
            this.rsar = (this.rsar & 0x00ff) | (ga << 8);
            break;
        case 0x0a:
            this.rcnt = (this.rcnt & 0xff00) | ga;
            break;
        case 0x0b:
            this.rcnt = (this.rcnt & 0x00ff) | (ga << 8);
            break;
        case 0x0c:
            this.rxcr = ga;
            break;
        case 0x0e:
            this.dcfg = ga;
            break;
        case 0x07:
            this.isr &= ~ (ga & 0x7f);
            this.update_irq();
            break;
        case 0x11:
        case 0x11 + 1 : case 0x11 + 2 : case 0x11 + 3 : case 0x11 + 4 : case 0x11 + 5 : this.phys[ue - 0x11] = ga;
            break;
        case 0x17:
            this.curpag = ga;
            break;
        case 0x18:
        case 0x18 + 1 : case 0x18 + 2 : case 0x18 + 3 : case 0x18 + 4 : case 0x18 + 5 : case 0x18 + 6 : case 0x18 + 7 : this.mult[ue - 0x18] = ga;
            break;
        }
    }
};
network_driver.prototype.ioport_read = function(fa) {
    var ue, mi, Mg;
    fa &= 0xf;
    if (fa == 0x00) {
        Mg = this.cmd;
    } else {
        mi = this.cmd >> 6;
        ue = fa | (mi << 4);
        switch (ue) {
        case 0x04:
            Mg = this.tsr;
            break;
        case 0x03:
            Mg = this.boundary;
            break;
        case 0x07:
            Mg = this.isr;
            break;
        case 0x08:
            Mg = this.rsar & 0x00ff;
            break;
        case 0x09:
            Mg = this.rsar >> 8;
            break;
        case 0x11:
        case 0x11 + 1 : case 0x11 + 2 : case 0x11 + 3 : case 0x11 + 4 : case 0x11 + 5 : Mg = this.phys[ue - 0x11];
            break;
        case 0x17:
            Mg = this.curpag;
            break;
        case 0x18:
        case 0x18 + 1 : case 0x18 + 2 : case 0x18 + 3 : case 0x18 + 4 : case 0x18 + 5 : case 0x18 + 6 : case 0x18 + 7 : Mg = this.mult[ue - 0x18];
            break;
        case 0x0c:
            Mg = this.rsr;
            break;
        case 0x21:
            Mg = this.start >> 8;
            break;
        case 0x22:
            Mg = this.stop >> 8;
            break;
        case 0x0a:
            Mg = 0x50;
            break;
        case 0x0b:
            Mg = 0x43;
            break;
        case 0x33:
            Mg = 0;
            break;
        case 0x35:
            Mg = 0x40;
            break;
        case 0x36:
            Mg = 0x40;
            break;
        default:
            Mg = 0x00;
            break;
        }
    }
    return Mg;
};
network_driver.prototype.dma_update = function(ng) {
    this.rsar += ng;
    if (this.rsar == this.stop) this.rsar = this.start;
    if (this.rcnt <= ng) {
        this.rcnt = 0;
        this.isr |= 0x40;
        this.update_irq();
    } else {
        this.rcnt -= ng;
    }
};
network_driver.prototype.asic_ioport_write = function(fa, ga) {
    var fa;
    if (this.rcnt == 0) return;
    if (this.dcfg & 0x01) {
        fa = (this.rsar & ~1) & 0x7fff;
        if (fa >= 0x4000) {
            this.mem[fa] = ga & 0xff;
            this.mem[fa + 1] = (ga >> 8) & 0xff;
        }
        this.dma_update(2);
    } else {
        fa = this.rsar & 0x7fff;
        if (fa >= 0x4000) {
            this.mem[fa] = ga & 0xff;
        }
        this.dma_update(1);
    }
};
network_driver.prototype.asic_ioport_read = function(fa) {
    var fa, Mg;
    if (this.dcfg & 0x01) {
        fa = (this.rsar & ~1) & 0x7fff;
        Mg = this.mem[fa] | (this.mem[fa + 1] << 8);
        this.dma_update(2);
    } else {
        fa = this.rsar & 0x7fff;
        Mg = this.mem[fa];
        this.dma_update(1);
    }
    return Mg;
};
network_driver.prototype.asic_ioport_writel = function(fa, ga) {
    var fa;
    if (this.rcnt == 0) return;
    fa = (this.rsar & ~1) & 0x7fff;
    if (fa >= 0x4000) {
        this.mem[fa] = ga & 0xff;
        this.mem[fa + 1] = (ga >> 8) & 0xff;
    }
    fa = (fa + 2) & 0x7fff;
    if (fa >= 0x4000) {
        this.mem[fa] = (ga >> 16) & 0xff;
        this.mem[fa + 1] = (ga >> 24) & 0xff;
    }
    this.dma_update(4);
};
network_driver.prototype.asic_ioport_readl = function(fa) {
    var fa, Mg;
    fa = (this.rsar & ~1) & 0x7fff;
    Mg = this.mem[fa] | (this.mem[fa + 1] << 8);
    fa = (fa + 2) & 0x7fff;
    Mg |= (this.mem[fa] << 16) | (this.mem[fa + 1] << 24);
    this.dma_update(4);
    return Mg;
};
network_driver.prototype.reset_ioport_write = function(fa, ga) {};
network_driver.prototype.reset_ioport_read = function(fa) {
    this.reset();
};

function network_driver(this_pc, base, set_irq_function, arr, send_function) {//hao network
    var i;
    this.set_irq_func = set_irq_function;
    this.send_packet_func = send_function;
    this_pc.register_ioport_write(base, 16, 1, this.ioport_write.bind(this));
    this_pc.register_ioport_read(base, 16, 1, this.ioport_read.bind(this));
    this_pc.register_ioport_write(base + 0x10, 1, 1, this.asic_ioport_write.bind(this));
    this_pc.register_ioport_read(base + 0x10, 1, 1, this.asic_ioport_read.bind(this));
    this_pc.register_ioport_write(base + 0x10, 2, 2, this.asic_ioport_write.bind(this));
    this_pc.register_ioport_read(base + 0x10, 2, 2, this.asic_ioport_read.bind(this));
    this_pc.register_ioport_write(base + 0x1f, 1, 1, this.reset_ioport_write.bind(this));
    this_pc.register_ioport_read(base + 0x1f, 1, 1, this.reset_ioport_read.bind(this));
    this.cmd = 0;
    this.start = 0;
    this.stop = 0;
    this.boundary = 0;
    this.tsr = 0;
    this.tpsr = 0;
    this.tcnt = 0;
    this.rcnt = 0;
    this.rsar = 0;
    this.rsr = 0;
    this.rxcr = 0;
    this.isr = 0;
    this.dcfg = 0;
    this.imr = 0;
    this.phys = unix_array(6);
    this.curpag = 0;
    this.mult = unix_array(8);
    this.mem = unix_array((32 * 1024));
    for (i = 0; i < 6; i++) this.mem[i] = arr[i];
    this.mem[14] = 0x57;
    this.mem[15] = 0x57;
    for (i = 15; i >= 0; i--) {
        this.mem[2 * i] = this.mem[i];
        this.mem[2 * i + 1] = this.mem[i];
    }
    this.reset();
}
//function net_send_packet(Yh, Rb, ng) {//hao net0
function net_send_packet(mem_block, send_offset, send_bytes) {//hao net0
    // eth0: sending ng bytes, starting from offset Rb in memory block Yh
    console.error("hao net0 net_send_packet ne2000: send packet len=" + send_bytes);//not used ? hao
    if (0) {
        var withPrefix = mem_block.subarray(send_offset - 2, send_offset + ng); // provide 2 more prefix bytes. we'll probably start with Rb=16384 anyway.
        withPrefix[0] = parseInt(parseInt(send_bytes) / 256);
        withPrefix[1] = parseInt(send_bytes) % 256;
        tuntap_sendData(withPrefix);
    } else {
        // TODO: tuntap_sendData() should handle Uint8Array() too.
        var withPrefix = "";
        withPrefix += String.fromCharCode(parseInt(parseInt(send_bytes) / 256));
        withPrefix += String.fromCharCode(parseInt(send_bytes) % 256);

        tcpdump_uint8array(mem_block.subarray(send_offset, send_offset + send_bytes));

        for (var i = send_offset; i < send_offset + send_bytes; i++) {
            withPrefix += String.fromCharCode(mem_block[i]);
        }
        tuntap_sendData(withPrefix);
    }
}
//add by hao net0 end

function PCEmulator(params) {
    var hard_disk,block_list;//add by hao
    var cpu;
    cpu = new CPU_X86();
    this.cpu = cpu;
    cpu.phys_mem_resize(params.mem_size);
    this.init_ioports();
    this.register_ioport_write(0x80, 1, 1, this.ioport80_write);
    this.pic    = new PIC_Controller(this, 0x20, 0xa0, set_hard_irq_wrapper.bind(cpu));
    this.pit    = new PIT(this, this.pic.set_irq.bind(this.pic, 0),  return_cycle_count.bind(cpu));
    this.cmos   = new CMOS(this);
    this.serial = new Serial(this, 0x3f8, this.pic.set_irq.bind(this.pic, 4), params.serial_write);//hao gh
    
    this.serial2 = new Serial(this, 0x2f8, this.pic.set_irq.bind(this.pic, 3), params.serial2_write);//add by hao gh
    
    this.kbd    = new KBD(this, this.reset.bind(this));
    this.reset_request = 0;
// add by hao for ide and net begin
    hard_disk = ["hda", "hdb"];
    block_list = new Array();
    for (i = 0; i < hard_disk.length; i++) {
        p = params[hard_disk[i]];//hao
        block_list[i] = null;
        if (p) {
            block_list[i] = new create_block_list(p.url, p.block_size, p.nb_blocks);
        }
    }
    this.ide0 = new ide_driver(this, 0x1f0, 0x3f6, this.pic.set_irq.bind(this.pic, 14), block_list); //hao
    this.net0 = new network_driver(this, 0x300, this.pic.set_irq.bind(this.pic, 9), [0x62, 0xb9, 0xe8, 0x01, 0x02,
    /*0x03*/
    new Date().getTime() % 255], net_send_packet);//hao
    
// add by hao for ide and net end
    if (params.clipboard_get && params.clipboard_set) {
        this.jsclipboard = new clipboard_device(this, 0x3c0, params.clipboard_get, params.clipboard_set, params.get_boot_time);
    }
    cpu.ld8_port       = this.ld8_port.bind(this);
    cpu.ld16_port      = this.ld16_port.bind(this);
    cpu.ld32_port      = this.ld32_port.bind(this);
    cpu.st8_port       = this.st8_port.bind(this);
    cpu.st16_port      = this.st16_port.bind(this);
    cpu.st32_port      = this.st32_port.bind(this);
    cpu.get_hard_intno = this.pic.get_hard_intno.bind(this.pic);
}

/*
//hao modify
PCEmulator.prototype.load_binary = function(binary_array, mem8_loc) { 
    return this.cpu.load_binary(binary_array, mem8_loc); 
};
*/
PCEmulator.prototype.load_binary = function(Dg, ha, Eg) {
    return this.cpu.load_binary(Dg, ha, Eg);
};
PCEmulator.prototype.start = function() { 
    setTimeout(this.timer_func.bind(this), 10); 
};

PCEmulator.prototype.timer_func = function() {
    var exit_status, Ncycles, do_reset, err_on_exit, PC, cpu;
    PC = this;
    cpu = PC.cpu;
    Ncycles = cpu.cycle_count + 100000;

    do_reset = false;
    err_on_exit = false;

    exec_loop: while (cpu.cycle_count < Ncycles) {
    	//add by hao begin
    	PC.serial.write_tx_fifo();
        PC.serial2.write_tx_fifo();//hao ¡ï¡ï¡ï¡ï
    	//add by hao end
        PC.pit.update_irq();
        exit_status = cpu.exec(Ncycles - cpu.cycle_count);
        if (exit_status == 256) {
            if (PC.reset_request) {
                do_reset = true;
                break;
            }
        } else if (exit_status == 257) {
            err_on_exit = true;
            break;
        } else {
            do_reset = true;
            break;
        }
    }
    if (!do_reset) {
        if (err_on_exit) {
            setTimeout(this.timer_func.bind(this), 10);
        } else {
            setTimeout(this.timer_func.bind(this), 0);
        }
    }
};

PCEmulator.prototype.init_ioports = function() {
    var i, readw, writew;
    this.ioport_readb_table = new Array();
    this.ioport_writeb_table = new Array();
    this.ioport_readw_table = new Array();
    this.ioport_writew_table = new Array();
    this.ioport_readl_table = new Array();
    this.ioport_writel_table = new Array();
    readw = this.default_ioport_readw.bind(this);
    writew = this.default_ioport_writew.bind(this);
    for (i = 0; i < 1024; i++) {
        this.ioport_readb_table[i] = this.default_ioport_readb;
        this.ioport_writeb_table[i] = this.default_ioport_writeb;
        this.ioport_readw_table[i] = readw;
        this.ioport_writew_table[i] = writew;
        this.ioport_readl_table[i] = this.default_ioport_readl;
        this.ioport_writel_table[i] = this.default_ioport_writel;
    }
};

PCEmulator.prototype.default_ioport_readb = function(port_num) {
    var x;
    x = 0xff;
    return x;
};

PCEmulator.prototype.default_ioport_readw = function(port_num) {
    var x;
    x = this.ioport_readb_table[port_num](port_num);
    port_num = (port_num + 1) & (1024 - 1);
    x |= this.ioport_readb_table[port_num](port_num) << 8;
    return x;
};

PCEmulator.prototype.default_ioport_readl = function(port_num) {
    var x;
    x = -1;
    return x;
};

PCEmulator.prototype.default_ioport_writeb = function(port_num, x) {};

PCEmulator.prototype.default_ioport_writew = function(port_num, x) {
    this.ioport_writeb_table[port_num](port_num, x & 0xff);
    port_num = (port_num + 1) & (1024 - 1);
    this.ioport_writeb_table[port_num](port_num, (x >> 8) & 0xff);
};

PCEmulator.prototype.default_ioport_writel = function(port_num, x) {};

PCEmulator.prototype.ld8_port = function(port_num) {
    var x;
    x = this.ioport_readb_table[port_num & (1024 - 1)](port_num);
    return x;
};

PCEmulator.prototype.ld16_port = function(port_num) {
    var x;
    x = this.ioport_readw_table[port_num & (1024 - 1)](port_num);
    return x;
};

PCEmulator.prototype.ld32_port = function(port_num) {
    var x;
    x = this.ioport_readl_table[port_num & (1024 - 1)](port_num);
    return x;
};

PCEmulator.prototype.st8_port  = function(port_num, x) { this.ioport_writeb_table[port_num & (1024 - 1)](port_num, x); };
PCEmulator.prototype.st16_port = function(port_num, x) { this.ioport_writew_table[port_num & (1024 - 1)](port_num, x); };
PCEmulator.prototype.st32_port = function(port_num, x) { this.ioport_writel_table[port_num & (1024 - 1)](port_num, x); };

PCEmulator.prototype.register_ioport_read = function(start, len, iotype, io_callback) {
    var i;
    switch (iotype) {
        case 1:
            for (i = start; i < start + len; i++) {
                this.ioport_readb_table[i] = io_callback;
            }
            break;
        case 2:
            for (i = start; i < start + len; i += 2) {
                this.ioport_readw_table[i] = io_callback;
            }
            break;
        case 4:
            for (i = start; i < start + len; i += 4) {
                this.ioport_readl_table[i] = io_callback;
            }
            break;
    }
};

PCEmulator.prototype.register_ioport_write = function(start, len, iotype, io_callback) {
    var i;
    switch (iotype) {
        case 1:
            for (i = start; i < start + len; i++) {
                this.ioport_writeb_table[i] = io_callback;
            }
            break;
        case 2:
            for (i = start; i < start + len; i += 2) {
                this.ioport_writew_table[i] = io_callback;
            }
            break;
        case 4:
            for (i = start; i < start + len; i += 4) {
                this.ioport_writel_table[i] = io_callback;
            }
            break;
    }
};

PCEmulator.prototype.ioport80_write = function(mem8_loc, data) {}; //POST codes! Seem to be ignored?
PCEmulator.prototype.reset = function() { this.request_request = 1; };



