"""Read V0.16 BD/HWH; write evidence only next to this script. Python >=3.8."""
import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET

OUT = Path(__file__).resolve().parent
DEFAULT = OUT.parents[2] / 'V0.16_复位修复_20261031'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1048576), b''):
            h.update(block)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--source', type=Path, default=DEFAULT)
    args = ap.parse_args()
    root = args.source.resolve()
    bd = root / 'build/link/_x/link/vivado/vpl/prj/prj.srcs/sources_1/bd/design_1/design_1.bd'
    hwh = root / 'V0.16_给丙上板包/hardware/fengyan_v016_dpu.hwh'
    other = [root / 'build/link/_x/link/vivado/vpl/prj/prj.gen/sources_1/bd/design_1/hw_handoff/design_1.hwh',
             root / 'V0.16_给丙上板包/hardware/fengyan_v016_dpu.bit',
             root / 'V0.16_给丙上板包/hardware/fengyan_v016_dpu.xclbin']
    refs = root / 'v014_unified_work_20261024/third_party/delivery_to_b_20261011/HDMI_DISPLAY_C_20261011'
    inputs = [bd, hwh] + other + [
        refs / 'rtl/c_hdmi_display_pipeline.sv',
        refs / 'rtl/video_timing_720p_axis.sv',
        refs / 'official_reference/firmware/TxOnly/xhdmi_example.c',
        refs / 'official_reference/firmware/TxOnly/xhdmi_example.h',
        root / 'build/link/_x/link/vivado/vpl/prj/prj.srcs/constrs_1/imports/constraints/hdmi_zcu104_tx_v014.xdc']
    before = {str(p): digest(p) for p in inputs}
    b = json.loads(bd.read_text(encoding='utf-8'))['design']
    x = ET.parse(hwh)
    names = ['v014_hdmi_tx_ss', 'v014_vid_phy', 'v014_fmch_iic']
    addresses = {n: [e.attrib for e in x.findall('.//MEMRANGE') if e.get('INSTANCE') == n] for n in names}
    params = {m.get('INSTANCE'): {e.get('NAME'): e.get('VALUE') for e in m.findall('./PARAMETERS/PARAMETER')}
              for m in x.findall('.//MODULE') if m.get('INSTANCE') in names}
    ports = {m.get('INSTANCE'): {e.get('NAME'): e.attrib for e in m.findall('./PORTS/PORT')}
             for m in x.findall('.//MODULE') if m.get('INSTANCE') in names + ['dpu_irq_concat', 'zynq_ultra_ps_e_0']}
    for instance, pin in [('v014_hdmi_tx_ss', 'In2'), ('v014_vid_phy', 'In3'), ('v014_fmch_iic', 'In4')]:
        irq = 'iic2intc_irpt' if instance.endswith('iic') else 'irq'
        assert ports[instance][irq]['SIGNAME'] == ports['dpu_irq_concat'][pin]['SIGNAME']
    assert ports['dpu_irq_concat']['dout']['SIGNAME'] == ports['zynq_ultra_ps_e_0']['pl_ps_irq0']['SIGNAME']
    assert b['components'][names[0]]['vlnv'] == 'xilinx.com:ip:v_hdmi_tx_ss:3.2'
    assert b['components'][names[1]]['vlnv'] == 'xilinx.com:ip:vid_phy_controller:2.2'
    for n, base in zip(names, ['0x82000000', '0x82020000', '0x82030000']):
        assert addresses[n] and all(a['BASEVALUE'].lower() == base for a in addresses[n]), n
    assert before[str(hwh)] == before[str(other[0])], 'Delivery HWH differs from final linked HWH'
    expected = {'v014_hdmi_tx_ss/irq': 'dpu_irq_concat/In2',
                'v014_vid_phy/irq': 'dpu_irq_concat/In3',
                'v014_fmch_iic/iic2intc_irpt': 'dpu_irq_concat/In4',
                'dpu_irq_concat/dout': 'zynq_ultra_ps_e_0/pl_ps_irq0'}
    for src, dst in expected.items():
        assert any(src in n.get('ports', []) and dst in n.get('ports', []) for n in b['nets'].values()), (src, dst)
    selected = lambda nets: {n: v for n, v in nets.items() if any(k in str(v) for k in names + ['dpu_irq_concat', 'hdmi_axis_pack', 'c_hdmi_display'])}
    after = {str(p): digest(p) for p in inputs}
    assert before == after, 'Source changed during audit'
    result = dict(status='PASS_STATIC_AUDIT_ONLY', source_hashes=before,
                  source_unchanged_during_audit=True, addresses=addresses, hwh_parameters=params, hwh_ports=ports,
                  components={n: b['components'][n] for n in names}, nets=selected(b['nets']),
                  interface_nets=selected(b['interface_nets']),
                  gic=dict(tx_spi=91, phy_spi=92, iic_spi=93, tx_hwirq=123, phy_hwirq=124, iic_hwirq=125),
                  note='GIC SPI cells omit architectural +32. Linux virq allocation is dynamic. No board verification.')
    (OUT / 'hardware-audit.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('PASS: final BD/address/IRQ topology, identical delivered HWH, input hashes unchanged')


if __name__ == '__main__':
    main()
