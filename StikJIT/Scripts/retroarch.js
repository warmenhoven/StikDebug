// retroarch.js - iOS 26 TXM JIT Support Script for RetroArch
//
// Stays attached for the entire RetroArch session to handle brk #0x69
// from any libretro core as they load/unload.
//
// Uses QSetIgnoredExceptions to tell debugserver to NOT intercept
// EXC_BAD_ACCESS (SIGSEGV/SIGBUS). These go straight to the process's
// own fault handlers with zero debugger overhead. Only EXC_BREAKPOINT
// (brk #0x69) causes a stop, which we handle here.

function littleEndianHexStringToNumber(hexStr) {
    const bytes = [];
    for (let i = 0; i < hexStr.length; i += 2) {
        bytes.push(parseInt(hexStr.substr(i, 2), 16));
    }
    let num = 0n;
    for (let i = 4; i >= 0; i--) {
        num = (num << 8n) | BigInt(bytes[i]);
    }
    return num;
}

function numberToLittleEndianHexString(num) {
    const bytes = [];
    for (let i = 0; i < 5; i++) {
        bytes.push(Number(num & 0xFFn));
        num >>= 8n;
    }
    while (bytes.length < 8) {
        bytes.push(0);
    }
    return bytes.map(b => b.toString(16).padStart(2, '0')).join('');
}

function littleEndianHexToU32(hexStr) {
    return parseInt(hexStr.match(/../g).reverse().join(''), 16);
}

function extractBrkImmediate(u32) {
    return (u32 >> 5) & 0xFFFF;
}

function formatSize(size) {
    if (size >= 1024 * 1024) {
        return `${(size / (1024 * 1024)).toFixed(2)} MB`;
    } else if (size >= 1024) {
        return `${(size / 1024).toFixed(2)} KB`;
    }
    return `${size} bytes`;
}

let pid = get_pid();
log(`[RetroArch] pid=${pid}`);

// Tell debugserver to ignore EXC_BAD_ACCESS (SIGSEGV/SIGBUS).
// This MUST be sent before vAttach. The kernel will deliver these
// exceptions directly to the process's signal handlers, bypassing
// the debugger entirely. Only EXC_BREAKPOINT will cause stops.
let ignoreResponse = send_command("QSetIgnoredExceptions:EXC_BAD_ACCESS|EXC_SOFTWARE");
log(`[RetroArch] QSetIgnoredExceptions: ${ignoreResponse}`);

let attachResponse = send_command(`vAttach;${pid.toString(16)}`);
log(`[RetroArch] Attached`);

let jitRequests = 0;
let totalMemoryMapped = 0n;

log(`[RetroArch] Listening for brk #0x69 (EXC_BAD_ACCESS handled in-process)`);

while (true) {
    let brkResponse = send_command(`c`);

    let tidMatch = /T[0-9a-f]+thread:(?<tid>[0-9a-f]+);/.exec(brkResponse);
    let tid = tidMatch ? tidMatch.groups['tid'] : null;
    let pcMatch = /20:(?<reg>[0-9a-f]{16});/.exec(brkResponse);
    let pc = pcMatch ? pcMatch.groups['reg'] : null;

    if (!tid || !pc) {
        log(`[RetroArch] Unexpected stop response, continuing...`);
        continue;
    }

    const pcNum = littleEndianHexStringToNumber(pc);

    // With QSetIgnoredExceptions, we should only see EXC_BREAKPOINT stops.
    // Verify it's a BRK instruction.
    let instructionResponse = send_command(`m${pcNum.toString(16)},4`);
    let instrU32 = littleEndianHexToU32(instructionResponse);

    if ((instrU32 >>> 16) !== 0xD420) {
        // Not a BRK - shouldn't happen with QSetIgnoredExceptions active.
        let metypeMatch = /metype:(\d+)/.exec(brkResponse);
        let metype = metypeMatch ? metypeMatch[1] : "?";
        log(`[RetroArch] Non-BRK stop: pc=0x${pcNum.toString(16)} instr=0x${instrU32.toString(16)} metype=${metype}, forwarding`);
        let sigMatch = /^T(?<sig>[a-z0-9]{2})/.exec(brkResponse);
        let signum = sigMatch ? sigMatch.groups['sig'] : null;
        if (signum) {
            send_command(`vCont;S${signum}:${tid}`);
        } else {
            send_command(`c`);
        }
        continue;
    }

    let brkImmediate = extractBrkImmediate(instrU32);

    if (brkImmediate === 0x69) {
        let x0Match = /00:(?<reg>[0-9a-f]{16});/.exec(brkResponse);
        let x1Match = /01:(?<reg>[0-9a-f]{16});/.exec(brkResponse);
        let x0 = x0Match ? littleEndianHexStringToNumber(x0Match.groups['reg']) : 0n;
        let x1 = x1Match ? littleEndianHexStringToNumber(x1Match.groups['reg']) : 0n;
        let size = x1 > 0n ? x1 : 0x10000n;

        // Round up to at least 16KB (one page) - StikDebug's
        // prepare_memory_region works in 16KB chunks and sends zero
        // commands for sizes smaller than that.
        // Also round up sizes >4MB to 16MB to trigger proper batching
        // (StikDebug deadlocks on >~256 unbatched commands).
        let prepSize = size < 0x4000n ? 0x4000n : size;
        if (prepSize > 0x400000n) {
            const GRANULARITY = 0x1000000n; // 16MB
            prepSize = (prepSize + GRANULARITY - 1n) & ~(GRANULARITY - 1n);
        }

        jitRequests++;
        log(`[RetroArch] JIT #${jitRequests}: addr=0x${x0.toString(16)} size=${formatSize(Number(size))} (preparing ${formatSize(Number(prepSize))})`);

        let result = prepare_memory_region(Number(x0), Number(prepSize));
        log(`[RetroArch] JIT #${jitRequests}: ${result}`);

        totalMemoryMapped += size;

        // Advance PC past the brk
        let pcPlus4 = numberToLittleEndianHexString(pcNum + 4n);
        send_command(`P20=${pcPlus4};thread:${tid};`);
    } else {
        // Other BRK, skip past it
        log(`[RetroArch] brk #0x${brkImmediate.toString(16)}, skipping`);
        let pcPlus4 = numberToLittleEndianHexString(pcNum + 4n);
        send_command(`P20=${pcPlus4};thread:${tid};`);
    }
}
