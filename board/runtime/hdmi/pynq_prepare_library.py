#!/usr/bin/env python3
"""Build the real PYNQ Linux HDMI wrapper against V0.16's final HWH.

No hardware access. Does not install/replace PYNQ's stock library. Requires a
PYNQ v3.0.1 source tree, Xilinx 2022.2 embeddedsw and an AArch64 Linux compiler.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
LIBS = 'v_hdmi_common v_hdmirxss v_hdmirx v_hdmitxss v_hdmitx video_common vphy vtc'.split()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def hwh_profile(path):
    doc = ET.parse(path)
    modules = {m.get('INSTANCE'): m for m in doc.findall('.//MODULE')}
    tx, phy, iic = [modules[n] for n in ['v014_hdmi_tx_ss', 'v014_vid_phy', 'v014_fmch_iic']]
    values = lambda m: {p.get('NAME'): p.get('VALUE') for p in m.findall('./PARAMETERS/PARAMETER')}
    t, v, i = values(tx), values(phy), values(iic)
    def number(value):
        if value in ['true', 'false']:
            return int(value == 'true')
        return int(value, 0) if value.lower().startswith('0x') else int(float(value))
    txkeys = {'BASEADDR': 'C_BASEADDR', 'HIGHADDR': 'C_HIGHADDR', 'INPUT_PIXELS_PER_CLOCK': 'C_INPUT_PIXELS_PER_CLOCK',
              'MAX_BITS_PER_COMPONENT': 'C_MAX_BITS_PER_COMPONENT', 'INCLUDE_LOW_RESO_VID': 'C_INCLUDE_LOW_RESO_VID',
              'INCLUDE_YUV420_SUP': 'C_INCLUDE_YUV420_SUP'}
    phykeys = {'BASEADDR': 'C_BASEADDR', 'TX_NO_OF_CHANNELS': 'C_Tx_No_Of_Channels', 'RX_NO_OF_CHANNELS': 'C_Rx_No_Of_Channels',
               'TX_PROTOCOL': 'C_Tx_Protocol', 'RX_PROTOCOL': 'C_Rx_Protocol', 'TX_REFCLK_SEL': 'C_TX_REFCLK_SEL',
               'RX_REFCLK_SEL': 'C_RX_REFCLK_SEL', 'TX_PLL_SELECTION': 'C_TX_PLL_SELECTION', 'RX_PLL_SELECTION': 'C_RX_PLL_SELECTION',
               'NIDRU': 'C_NIDRU', 'NIDRU_REFCLK_SEL': 'C_NIDRU_REFCLK_SEL', 'INPUT_PIXELS_PER_CLOCK': 'C_INPUT_PIXELS_PER_CLOCK',
               'TX_BUFFER_BYPASS': 'Tx_Buffer_Bypass', 'HDMI_FAST_SWITCH': 'C_Hdmi_Fast_Switch',
               'TRANSCEIVER_WIDTH': 'Transceiver_Width', 'ERR_IRQ_EN': 'C_Err_Irq_En', 'USE_GT_CH4_HDMI': 'C_Use_GT_CH4_HDMI'}
    txcfg = {k: number(t[v]) for k, v in txkeys.items()}
    phycfg = {k: number(v[key]) for k, key in phykeys.items()}
    if v['Transceiver'] != 'GTHE4':
        raise ValueError('Only the audited GTHE4 design is supported')
    clock = next(p for p in phy.findall('./PORTS/PORT') if p.get('NAME') == 'vid_phy_axi4lite_aclk')
    frequency = int(clock.get('CLKFREQUENCY'))
    phycfg.update(TRANSCEIVER=5, AXI_LITE_FREQ_HZ=frequency, DRPCLK_FREQ=frequency)
    txcfg['AXI_LITE_FREQ_HZ'] = frequency
    if (txcfg['BASEADDR'], txcfg['HIGHADDR'], phycfg['BASEADDR'], number(i['C_BASEADDR'])) != (0x82000000, 0x8201ffff, 0x82020000, 0x82030000):
        raise ValueError('HWH addresses do not match the V0.16 final design')
    if (txcfg['INPUT_PIXELS_PER_CLOCK'], txcfg['MAX_BITS_PER_COMPONENT'], phycfg['RX_PROTOCOL'], phycfg['NIDRU']) != (2, 8, 3, 0):
        raise ValueError('HWH does not describe the audited 2PPC/8BPC/TX-only/no-NIDRU configuration')
    if any(number(t[k]) for k in ['C_INCLUDE_HDCP_1_4', 'C_INCLUDE_HDCP_2_2']):
        raise ValueError('HDCP configuration is unsupported')
    reset = dict(constant_one=False)
    output = next((p for p in doc.findall('./EXTERNALPORTS/PORT') if p.get('NAME') == 'IDT_8T49N241_RST_OUT'), None)
    if output is not None and output.get('DIR') == 'O':
        for module in modules.values():
            if module.get('MODTYPE') == 'xlconstant':
                params = values(module)
                if number(params.get('CONST_VAL', '0')) == 1 and number(params.get('CONST_WIDTH', '0')) == 1:
                    if any(p.get('DIR') == 'O' and p.get('SIGNAME') == output.get('SIGNAME') for p in module.findall('./PORTS/PORT')):
                        reset = dict(constant_one=True, net=output.get('SIGNAME'), source=module.get('INSTANCE'))
    return dict(schema=1, pynq='3.0.1', embeddedsw='2022.2', hwh_sha256=sha(path), tx=txcfg, phy=phycfg,
                iic_base=number(i['C_BASEADDR']), mode=[1280, 720, 60], reset_control=reset)


def patch_parameters(text, profile):
    replacements = {}
    for suffix, value in profile['tx'].items():
        for prefix in ['XPAR_V_HDMI_TX_SS_', 'XPAR_XV_HDMITXSS_0_']:
            replacements[prefix + suffix] = str(value)
    for suffix, value in profile['phy'].items():
        for prefix in ['XPAR_VID_PHY_CONTROLLER_', 'XPAR_VPHY_0_']:
            replacements[prefix + suffix] = str(value)
    replacements['XPAR_V_HDMI_TX_SS_V_HDMI_TX_AXI_LITE_FREQ_HZ'] = str(profile['tx']['AXI_LITE_FREQ_HZ'])
    for key, value in replacements.items():
        text, count = re.subn(r'(?m)^(#define\s+' + re.escape(key) + r'\s+)[^\r\n]+', lambda m: m[1] + value, text)
        if key.startswith(('XPAR_VID_PHY_CONTROLLER_', 'XPAR_V_HDMI_TX_SS_')) and count != 1:
            raise ValueError('Required PYNQ configuration macro missing/duplicated: ' + key)
    return text, replacements


def driver_directory(parent, name):
    exact = parent / name
    if exact.is_dir():
        return exact
    candidates = list(parent.glob(name + '_v*'))
    if not candidates:
        raise ValueError('Missing embeddedsw component: ' + name)
    return max(candidates, key=lambda p: tuple(map(int, p.name.split('_v')[-1].split('_'))))


def inspect_elf(library, readelf):
    results = {}
    for label, option in [('dynamic', '-d'), ('versions', '--version-info'), ('symbols', '-Ws')]:
        result = subprocess.run([str(readelf), option, str(library)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        if result.returncode:
            raise ValueError('readelf failed: ' + result.stderr.decode(errors='replace'))
        text = result.stdout.decode('utf-8', errors='replace')
        library.with_name('readelf-' + label + '.txt').write_text(text, encoding='utf-8')
        results[label] = text
    needed = re.findall(r'Shared library: \[([^]]+)\]', results['dynamic'])
    versions = sorted(set(re.findall(r'Name:\s+([A-Za-z0-9_.]+)', results['versions'])))
    glibc = [v for v in versions if v.startswith('GLIBC_')]
    if needed != ['libc.so.6'] or not glibc or any(not v.startswith('GLIBC_') for v in versions):
        raise ValueError('Unexpected native runtime dependency/version: ' + repr((needed, versions)))
    if any(tuple(map(int, v.split('_')[1].split('.'))) > (2, 31) for v in glibc):
        raise ValueError('Library requires newer than target baseline GLIBC 2.31')
    required = ['FengyanHdmi_profile', 'FengyanHdmi_refclk', 'FengyanHdmi_pll_locked',
                'HdmiPhy_new', 'HdmiTx_new', 'HdmiTx_set_format', 'HdmiTx_start', 'HdmiTx_stop']
    if any(not re.search(r'\b' + name + r'\b', results['symbols']) for name in required):
        raise ValueError('Required native symbol missing')
    return dict(needed=needed, version_needs=versions, glibcxx_required=False, cxxabi_required=False,
                language='C', target_baseline_glibc='2.31', baseline_version_compatible=True)


def build(pynq_source, esw, hwh, output, cc):
    output = Path(output).resolve()
    if output.exists():
        raise ValueError('Choose a new, nonexistent build directory')
    profile = hwh_profile(hwh)
    src = Path(pynq_source).resolve() / 'pynq/lib/_pynq'
    for f in ['_xhdmi/hdmi_functions.c', 'common/aarch64/xparameters.h', 'common/xil_stubs.c']:
        reference = HERE / 'pynq-reference-v3.0.1/pynq/lib/_pynq' / f
        if (src / f).read_bytes().replace(b'\r\n', b'\n') != reference.read_bytes().replace(b'\r\n', b'\n'):
            raise ValueError('PYNQ v3.0.1 reference mismatch: ' + f)
    drivers = Path(esw).resolve() / 'XilinxProcessorIPLib/drivers'
    dirs = [driver_directory(drivers, name) / 'src' for name in LIBS]
    standalone = driver_directory(Path(esw).resolve() / 'lib/bsp', 'standalone') / 'src'
    cma = Path(pynq_source).resolve() / 'sdbuild/packages/libsds/libcma'
    if not (cma / 'libxlnk_cma.h').is_file():
        raise ValueError('Missing official PYNQ libxlnk_cma.h')
    output.mkdir(parents=True)
    # Stage all source/include inputs locally. Besides making the receipt
    # relocatable, this avoids older Windows GCC's Unicode path limitation.
    original_dirs = list(dirs)
    dirs = []
    for directory in original_dirs:
        destination = output / 'esw-drivers' / directory.parent.name / 'src'
        shutil.copytree(directory, destination)
        dirs.append(destination)
    shutil.copytree(standalone, output / 'standalone/src')
    standalone = output / 'standalone/src'
    shutil.copytree(src / 'common', output / 'common')
    shutil.copy2(cma / 'libxlnk_cma.h', output / 'common/libxlnk_cma.h')
    shutil.copytree(src / '_xhdmi', output / '_xhdmi')
    header = output / 'common/aarch64/xparameters.h'
    text, replacements = patch_parameters(header.read_text(), profile)
    header.write_text(text, encoding='utf-8')
    # Same translation unit as official HdmiPhy type; no guessed ctypes layouts.
    shim = '\n#include <xvphy_i.h>\nconst char* FengyanHdmi_profile(void) { return ' + json.dumps(json.dumps(profile, sort_keys=True)) + '; }\n'
    for key, value in replacements.items():
        if re.search(r'(?m)^#define\s+' + re.escape(key) + r'\s+', text):
            shim += '_Static_assert(' + key + ' == ' + value + ', "HWH config mismatch");\n'
    shim += '''
unsigned int FengyanHdmi_refclk(void* h) {
    return XVphy_ClkDetGetRefClkFreqHz(&((HdmiPhy*)h)->Vphy, XVPHY_DIR_TX);
}
unsigned int FengyanHdmi_version(void* h) { return XVphy_GetVersion(&((HdmiPhy*)h)->Vphy); }
int FengyanHdmi_pll_locked(void* h) {
    XVphy* p = &((HdmiPhy*)h)->Vphy;
    XVphy_PllType type = XVphy_GetPllType(p, 0, XVPHY_DIR_TX, XVPHY_CHANNEL_ID_CH1);
    XVphy_ChannelId ch = type == XVPHY_PLL_TYPE_CPLL ? XVPHY_CHANNEL_ID_CH1 :
        ((type == XVPHY_PLL_TYPE_QPLL || type == XVPHY_PLL_TYPE_QPLL0) ? XVPHY_CHANNEL_ID_CMN0 : XVPHY_CHANNEL_ID_CMN1);
    return XVphy_IsPllLocked(p, 0, ch) == XST_SUCCESS;
}
'''
    wrapper = output / '_xhdmi/hdmi_functions.c'
    wrapper.write_text(wrapper.read_text() + shim, encoding='utf-8')
    sources = sorted((output / '_xhdmi').glob('*.c')) + sorted((output / 'common').glob('*.c'))
    for d in dirs:
        sources += sorted(p for p in d.glob('*.c') if not p.name.endswith('_g.c'))
    includes = [output / 'common/aarch64', output / 'common'] + dirs + [
        standalone / 'common', standalone / 'arm/common/gcc', standalone / 'arm/common',
        standalone / 'arm/ARMv8/64bit', standalone / 'arm/ARMv8/64bit/platform/ZynqMP']
    library = output / 'libfengyan_xhdmi.so'
    def compiler_path(path):
        try:
            return path.relative_to(output).as_posix()
        except ValueError:
            return path.as_posix()
    command = [str(cc), '-shared', '-fPIC', '-O2', '-Wl,-z,defs', '-Werror=implicit-function-declaration', '-Werror=incompatible-pointer-types',
               '-o', library.name] + ['-I' + compiler_path(d) for d in includes] + [compiler_path(p) for p in sources]
    # Response file avoids Windows command-line length limits; arguments remain quoted.
    response = output / 'compile.rsp'
    response.write_text('\n'.join('"' + arg.replace('\\', '/').replace('"', '\\"') + '"' for arg in command[1:]), encoding='utf-8')
    result = subprocess.run([str(cc), '@compile.rsp'], cwd=str(output), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=240)
    (output / 'compile.log').write_bytes(result.stdout)
    if result.returncode:
        raise ValueError('Native compilation failed; see ' + str(output / 'compile.log'))
    data = library.read_bytes()
    if data[:6] != b'\x7fELF\x02\x01' or int.from_bytes(data[18:20], 'little') != 183:
        raise ValueError('Compiler did not produce an ELF64 little-endian AArch64 library')
    compiler = Path(shutil.which(str(cc)) or cc)
    readelf_name = re.sub(r'gcc(?=\.exe$|$)', 'readelf', compiler.name)
    readelf = compiler.with_name(readelf_name)
    if not readelf.is_file():
        readelf = shutil.which('readelf')
    if not readelf:
        raise ValueError('Need readelf to verify dynamic dependencies and GLIBC baseline')
    dynamic_abi = inspect_elf(library, readelf)
    receipt = dict(profile=profile, library_sha256=sha(library), compiler=str(cc),
                   driver_directories=[compiler_path(d) for d in dirs], sources={compiler_path(p): sha(p) for p in sources},
                   generated_xparameters_sha256=sha(header), board_tested=False)
    receipt['dynamic_abi'] = dynamic_abi
    (output / 'build-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    return library


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--pynq-source', type=Path, required=True)
    ap.add_argument('--embeddedsw', type=Path, required=True)
    ap.add_argument('--hwh', type=Path, required=True)
    ap.add_argument('--output-dir', type=Path, required=True)
    ap.add_argument('--cc', required=True, help='AArch64 Linux compiler executable (not bare-metal gcc)')
    args = ap.parse_args()
    try:
        print(build(args.pynq_source, args.embeddedsw, args.hwh, args.output_dir, args.cc))
    except (OSError, ValueError, ET.ParseError, KeyError, subprocess.TimeoutExpired) as e:
        print('ERROR: ' + str(e), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
