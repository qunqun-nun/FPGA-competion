"""Compile unchanged memio.c and test only allocated local RAM, never MMIO.

FY_HOST_CC/FY_AARCH64_CC may name GCC-compatible compiler executables.
AArch64 compilation is checked locally but target code is never executed here.
"""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import sys
import unittest

RUNTIME=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(RUNTIME))
import pl_runtime as pl
EVIDENCE=Path(__file__).resolve().parent/'evidence'
SOURCE=RUNTIME/'native/memio.c'


def run(command):
    r=subprocess.run([str(x) for x in command],capture_output=True,text=True,timeout=60)
    if r.returncode:
        raise RuntimeError('Compiler/tool failed: '+repr(command)+'\n'+r.stdout+r.stderr)
    return r.stdout+r.stderr


def body(assembly, name):
    after=assembly.split(name+':',1)[1]
    return re.split(r'\n\s*\.(?:size|seh_endproc)\b',after,maxsplit=1)[0]


class NativeMemoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        EVIDENCE.mkdir(exist_ok=True)
        cc=os.environ.get('FY_HOST_CC') or shutil.which('gcc')
        if not cc: raise unittest.SkipTest('No host GCC; native checks NOT RUN')
        cls.cc=cc
        cls.suffix='win64' if os.name=='nt' else platform.machine()+'_host'
        cls.library_path=EVIDENCE/('memio_'+cls.suffix+('.dll' if os.name=='nt' else '.so'))
        cls.assembly_path=EVIDENCE/('memio_'+cls.suffix+'.s')
        flags=['-std=c11','-O2','-Wall','-Wextra','-Werror']
        if os.name!='nt': flags+=['-fPIC']
        commands=[[cc]+flags+['-shared',SOURCE,'-o',cls.library_path],
                  [cc]+flags+['-S',SOURCE,'-o',cls.assembly_path]]
        for command in commands: run(command)
        cls.lib=ctypes.CDLL(str(cls.library_path))
        cls.lib.fy_read32.argtypes=[ctypes.c_void_p,ctypes.c_size_t]
        cls.lib.fy_read32.restype=ctypes.c_uint32
        cls.lib.fy_write32.argtypes=[ctypes.c_void_p,ctypes.c_size_t,ctypes.c_uint32]
        cls.lib.fy_write32.restype=None
        cls.lib.fy_copy.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_size_t]
        cls.lib.fy_copy.restype=None
        metadata={'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                  'host_compiler':run([cc,'--version']).splitlines()[0],
                  'host_commands':[[str(v) for v in cmd] for cmd in commands],
                  'host_platform':platform.platform(),'pointer_bits':ctypes.sizeof(ctypes.c_void_p)*8,
                  'test_scope':'allocated host RAM only, not real DMA/MMIO/cache coherency'}
        (EVIDENCE/'native_build.json').write_text(json.dumps(metadata,indent=2),encoding='utf-8')

    def test_full_width_pointer_unsigned_read_write_and_offset(self):
        storage=(ctypes.c_uint32*1024)()
        pointer=ctypes.addressof(storage)
        if ctypes.sizeof(ctypes.c_void_p)==8:
            self.assertGreater(pointer,0xffffffff,'Need a >4GiB virtual pointer to exercise truncation')
        for index,value in ((0,0),(1,0xffffffff),(17,0x80000000),(1023,0xaabbccdd)):
            self.lib.fy_write32(pointer,index*4,value)
            self.assertEqual(storage[index],value)
            self.assertEqual(self.lib.fy_read32(pointer,index*4),value)
        self.assertEqual(storage[16],0)
        (EVIDENCE/'pointer_test.json').write_text(json.dumps({'virtual_pointer_hex':hex(pointer),
            'above_4gib':pointer>0xffffffff,'unsigned_and_offset_roundtrip':'PASS'},indent=2),encoding='utf-8')

    def test_copy_bytes_and_guards(self):
        src=(ctypes.c_ubyte*4100)(*[i%256 for i in range(4100)])
        dst=(ctypes.c_ubyte*4100)(*[0x5a]*4100)
        self.lib.fy_copy(ctypes.addressof(dst)+2,ctypes.addressof(src)+1,4096)
        self.assertEqual(bytes(dst)[2:4098],bytes(src)[1:4097])
        self.assertEqual(bytes(dst)[:2],b'ZZ'); self.assertEqual(bytes(dst)[4098:],b'ZZ')
        before=bytes(dst)
        self.lib.fy_copy(ctypes.addressof(dst),ctypes.addressof(src),0)
        self.assertEqual(bytes(dst),before)

    def test_region_checks_alignment_and_bounds(self):
        storage=(ctypes.c_uint32*1024)()
        region=pl.Region.__new__(pl.Region)
        region.ptr=ctypes.addressof(storage); region.length=4096; region.lib=self.lib
        region.write(4092,0xfedcba98); self.assertEqual(region.read(4092),0xfedcba98)
        for offset in (-4,1,4093,4096):
            with self.subTest(offset=offset):
                with self.assertRaises(ValueError): region.read(offset)
                with self.assertRaises(ValueError): region.write(offset,1)

    def test_host_barrier_instructions_surround_accesses(self):
        asm=self.assembly_path.read_text()
        machine=platform.machine().lower()
        if machine in ('amd64','x86_64'):
            fence=r'(?:mfence|lock[^\n]*)'
            access={'fy_read32':r'movl\s+\(','fy_write32':r'movl\s+%[^\n]*\(','fy_copy':r'call\s+memcpy'}
        elif machine in ('arm64','aarch64'):
            fence=r'dmb\s+ish'
            access={'fy_read32':r'ldr\s','fy_write32':r'str\s','fy_copy':r'bl\s+memcpy'}
        else: self.skipTest('Assembly patterns not implemented for '+machine)
        for name,operation in access.items():
            segment=body(asm,name)
            self.assertRegex(segment,r'(?s)'+fence+'.*'+operation+'.*'+fence)


class Aarch64BuildTests(unittest.TestCase):
    def test_cross_compile_elf_and_barriers(self):
        candidates=[os.environ.get('FY_AARCH64_CC'),shutil.which('aarch64-linux-gnu-gcc'),
            'F:/Xilinx/Vitis/2022.2/gnu/aarch64/nt/aarch64-linux/bin/aarch64-linux-gnu-gcc.exe']
        cc=next((str(p) for p in candidates if p and Path(p).is_file()),None)
        if not cc: self.skipTest('No AArch64 Linux compiler; target build NOT RUN')
        shared=EVIDENCE/'libmemio_aarch64.so'
        assembly=EVIDENCE/'memio_aarch64.s'
        flags=['-std=c11','-O2','-Wall','-Wextra','-Werror','-fPIC']
        commands=[[cc]+flags+['-shared',SOURCE,'-o',shared],
                  [cc]+flags+['-S',SOURCE,'-o',assembly]]
        for command in commands: run(command)
        raw=shared.read_bytes()
        self.assertEqual(raw[:6],b'\x7fELF\x02\x01')  # ELF64 little-endian
        self.assertEqual(struct.unpack_from('<H',raw,16)[0],3)  # ET_DYN
        self.assertEqual(struct.unpack_from('<H',raw,18)[0],183)  # EM_AARCH64
        asm=assembly.read_text()
        for name,access in [('fy_read32',r'ldr\s'),('fy_write32',r'str\s'),('fy_copy',r'bl\s+memcpy')]:
            self.assertRegex(body(asm,name),r'(?s)dmb\s+ish.*'+access+r'.*dmb\s+ish')
        (EVIDENCE/'aarch64_build.json').write_text(json.dumps({
            'compiler':run([cc,'--version']).splitlines()[0],
            'commands':[[str(v) for v in c] for c in commands],
            'format':'ELF64 little-endian AArch64 shared object',
            'barriers':'two dmb ish per function around load/store/memcpy',
            'board_execution':'NOT_RUN'},indent=2),encoding='utf-8')


if __name__=='__main__': unittest.main(verbosity=2)
