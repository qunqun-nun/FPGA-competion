"""Runtime PL0 divider adaptation. Never edit HWH or retune a shared PS PLL."""
import json
import math
import time
import xml.etree.ElementTree as ET
from pathlib import Path


def target_mhz(hwh):
    root = ET.parse(str(hwh)).getroot()
    modules = [m for m in root.findall('.//MODULE') if m.get('MODTYPE') == 'zynq_ultra_ps_e']
    if len(modules) != 1:
        raise RuntimeError('Expected one MPSoC PS in HWH')
    port = modules[0].find("./PORTS/PORT[@NAME='pl_clk0']")
    target = float(port.get('CLKFREQUENCY')) / 1e6
    if not math.isfinite(target) or abs(target - 100.0) > 0.01:
        raise RuntimeError('This repair only supports the verified 100 MHz design')
    return target


def snapshot():
    from pynq import Clocks, MMIO
    crl = MMIO(0xFF5E0000, 0x100)
    pl0 = int(crl.read(0xC0))
    return dict(time=time.time(), fclk0_mhz=float(Clocks.fclk0_mhz),
                source=pl0 & 7, div0=(pl0 >> 8) & 63, div1=(pl0 >> 16) & 63,
                active=bool(pl0 & (1 << 24)),
                registers={hex(o):hex(int(crl.read(o))) for o in
                           (0x20,0x24,0x28,0x30,0x34,0x38,0x40,0xC0,0xC4,0xC8,0xCC)},
                frequency_kind='PYNQ register-derived; not oscilloscope measurement')


def choose_dividers(state, target):
    if int(state.get('registers',{}).get('0x28','0'),16) & (1 << 31):
        raise RuntimeError('Fractional IOPLL unsupported by pinned PYNQ frequency calculation')
    if state['source'] != 0 or not state['div0'] or not state['div1']:
        raise RuntimeError('Expected IOPLL source and nonzero PL0 dividers; capture diagnostics first')
    # No assumption that the running boot image used this XSA's IOPLL setup.
    source = state['fclk0_mhz'] * state['div0'] * state['div1']
    if not math.isfinite(source) or source <= 0:
        raise RuntimeError('Invalid running PLL frequency')
    d0,d1 = min(((a,b) for a in range(1,64) for b in range(1,64)),
                key=lambda d:(abs(source/(d[0]*d[1])-target), d[1],d[0]))
    if abs(source/(d0*d1) - target) > target * 0.001:
        raise RuntimeError('Cannot achieve target with running PLL; do not modify shared PLL')
    return d0,d1


def prepare_download(overlay, hwh, read=snapshot):
    state = read()
    target = target_mhz(hwh)
    d0,d1 = choose_dividers(state,target)
    # Overlay.download() subsequently applies this dictionary. Fix that input,
    # rather than setting Clocks before a parent download overwrites it.
    if 0 not in overlay.clock_dict or not overlay.clock_dict[0].get('enable'):
        raise RuntimeError('PL0 is not enabled in parsed PYNQ clock metadata')
    overlay.clock_dict[0].update(divisor0=d0, divisor1=d1)
    return dict(before=state, target_mhz=target, applied_dividers=[d0,d1])


def assert_clock(hwh, read=snapshot):
    state = read()
    target = target_mhz(hwh)
    if not state['active'] or state['source'] != 0 or not math.isfinite(state['fclk0_mhz']) or abs(state['fclk0_mhz']-target)>target*0.001:
        raise RuntimeError('PL0 mismatch; stop workload, do not retune during DMA: '+json.dumps(state))
    return state


def record(stage, state):
    folder = Path(__file__).resolve().parent.parent / 'state'
    folder.mkdir(exist_ok=True)
    with (folder/'pl_clock.jsonl').open('a') as out:
        out.write(json.dumps(dict(stage=stage, data=state))+'\n')
