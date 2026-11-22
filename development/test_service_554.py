import os
import struct
from pathlib import Path

import pefile
import pytest
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE
from unicorn.x86_const import *

ROOT = Path(__file__).parent
SOURCE = Path(os.environ['ICUE_SERVICE_REFERENCE'])
IMAGE = Path(os.environ.get('ICUE_TEST_IMAGE', str(SOURCE)))
CALLS = (0xF098, 0xF1C8, 0xF3FB, 0xF51B, 0xFD2B, 0x1033B, 0x1064B, 0x1077B, 0x108AB, 0x10D5D, 0x1100B)
COPY = 0xE090
FAILURE = 0x10A5C
MOCK, STACK, DATA = 0x2000000, 0x3000000, 0x4000000
NV = (UC_X86_REG_RBX, UC_X86_REG_RBP, UC_X86_REG_RSI, UC_X86_REG_RDI, UC_X86_REG_R12, UC_X86_REG_R13, UC_X86_REG_R14, UC_X86_REG_R15)
VOLATILE = (UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_R9, UC_X86_REG_R10, UC_X86_REG_R11)


def fixture():
    pe = pefile.PE(str(IMAGE))
    free = [i.address for e in pe.DIRECTORY_ENTRY_IMPORT for i in e.imports if i.name == b'SysFreeString']
    assert len(free) == 1, 'New service must import the matching BSTR deallocator'
    m = Uc(UC_ARCH_X86, UC_MODE_64)
    base = pe.OPTIONAL_HEADER.ImageBase
    m.mem_map(base, pe.OPTIONAL_HEADER.SizeOfImage)
    m.mem_write(base, pe.get_memory_mapped_image())
    for address, size in ((MOCK, 0x1000), (STACK, 0x10000), (DATA, 0x2000)):
        m.mem_map(address, size)
    m.mem_write(free[0], struct.pack('<Q', MOCK))
    kept = {reg: DATA + 0x1000 if reg == UC_X86_REG_RDI else 0x110000000 + n * 17 for n, reg in enumerate(NV)}
    for reg, value in kept.items():
        m.reg_write(reg, value)
    m.reg_write(UC_X86_REG_RSP, STACK + 0x8000)
    return pe, m, base, kept


def returning(m, value):
    rsp = m.reg_read(UC_X86_REG_RSP)
    target = struct.unpack('<Q', m.mem_read(rsp, 8))[0]
    for reg in VOLATILE:
        m.reg_write(reg, 0xDEAD)
    m.reg_write(UC_X86_REG_RAX, value)
    m.reg_write(UC_X86_REG_RSP, rsp + 8)
    m.reg_write(UC_X86_REG_RIP, target)


@pytest.mark.parametrize('call', CALLS)
@pytest.mark.parametrize('null', (False, True))
def test_owned_string_copied_before_exactly_one_free(call, null):
    pe, m, base, kept = fixture()
    pointer = 0 if null else DATA + 0x100
    obj = DATA + 0x400
    content = b'CPU Package Sensor\0'
    if pointer:
        m.mem_write(pointer, content)
    m.reg_write(UC_X86_REG_RCX, obj)
    m.reg_write(UC_X86_REG_RDX, pointer)
    state = dict(copied=False, freed=[])

    def hook(uc, address, size, unused):
        if address not in (base + COPY, MOCK):
            return
        assert uc.reg_read(UC_X86_REG_RSP) % 16 == 8
        if address == base + COPY:
            # Mock boundary: preserve the vendor converter's input/return ABI.
            # Returning for null here does not assert native null safety.
            assert uc.reg_read(UC_X86_REG_RCX) == obj
            assert uc.reg_read(UC_X86_REG_RDX) == pointer
            assert not state['freed']
            if pointer:
                assert bytes(uc.mem_read(pointer, len(content))) == content
            state['copied'] = True
            returning(uc, obj)
        else:
            assert state['copied'], 'String released before conversion'
            assert uc.reg_read(UC_X86_REG_RCX) == pointer
            state['freed'].append(pointer)
            returning(uc, 0xBAD)

    m.hook_add(UC_HOOK_CODE, hook)
    m.emu_start(base + call, base + call + 5, count=160)
    assert state == dict(copied=True, freed=[pointer])
    assert m.reg_read(UC_X86_REG_RAX) == obj
    assert m.reg_read(UC_X86_REG_RSP) == STACK + 0x8000
    assert all(m.reg_read(reg) == value for reg, value in kept.items())


@pytest.mark.parametrize('returned', (0, 1, 0x102))
@pytest.mark.parametrize('has_output', (False, True))
@pytest.mark.parametrize('writes_name', (False, True))
def test_query_failure_preserves_status_and_ten_arguments(returned, has_output, writes_name):
    pe, m, base, kept = fixture()
    output, pointer = (DATA + 0x300 if has_output else 0), DATA + 0x700
    args = [DATA + 0x100, output, DATA + 0x400, DATA + 0x500, DATA + 0x600, DATA + 0x800]
    sp = STACK + 0x8000
    for n, value in enumerate(args):
        m.mem_write(sp + 0x20 + 8*n, struct.pack('<Q', value))
    if output:
        m.mem_write(output, struct.pack('<Q', 0xBAD))
    m.mem_write(kept[UC_X86_REG_RDI] + 0x28, struct.pack('<Q', 0x1111))
    for reg, value in zip((UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_R9, UC_X86_REG_R10), (0xBAD, 0x2222, 0x3333, 0x4444, MOCK + 0x100)):
        m.reg_write(reg, value)
    freed = []

    def hook(uc, address, size, unused):
        if address not in (MOCK, MOCK + 0x100):
            return
        rsp = uc.reg_read(UC_X86_REG_RSP)
        assert rsp % 16 == 8
        if address == MOCK + 0x100:
            assert [uc.reg_read(r) for r in (UC_X86_REG_RCX, UC_X86_REG_RDX, UC_X86_REG_R8, UC_X86_REG_R9)] == [0x1111, 0x2222, 0x3333, 0x4444]
            assert [struct.unpack('<Q', uc.mem_read(rsp + 0x28 + 8*n, 8))[0] for n in range(6)] == args
            if output:
                assert struct.unpack('<Q', uc.mem_read(output, 8))[0] == 0
                if writes_name:
                    uc.mem_write(output, struct.pack('<Q', pointer))
            returning(uc, returned)
        else:
            freed.append(uc.reg_read(UC_X86_REG_RCX))
            returning(uc, 0xBAD)

    m.hook_add(UC_HOOK_CODE, hook)
    m.emu_start(base + FAILURE, base + FAILURE + 7, count=240)
    assert m.reg_read(UC_X86_REG_RAX) == returned
    assert m.reg_read(UC_X86_REG_RSP) == sp
    assert all(m.reg_read(reg) == value for reg, value in kept.items())
    if output:
        assert struct.unpack('<Q', m.mem_read(output, 8))[0] == (pointer if returned and writes_name else 0)
    assert freed == ([pointer if writes_name else 0] if not returned and has_output else [])


def test_original_code_and_security_policy_preserved():
    before, after = pefile.PE(str(SOURCE)), pefile.PE(str(IMAGE))
    a, b = bytearray(before.sections[0].get_data()), bytearray(after.sections[0].get_data())
    for rva, size in [(r, 5) for r in CALLS] + [(FAILURE, 7)]:
        at = rva - before.sections[0].VirtualAddress
        a[at:at+size] = b[at:at+size]
    assert a == b
    assert before.OPTIONAL_HEADER.DllCharacteristics == after.OPTIONAL_HEADER.DllCharacteristics
    assert before.OPTIONAL_HEADER.AddressOfEntryPoint == after.OPTIONAL_HEADER.AddressOfEntryPoint
    old = [(e.struct.BeginAddress,e.struct.EndAddress,e.struct.UnwindData) for e in before.DIRECTORY_ENTRY_EXCEPTION]
    new = [(e.struct.BeginAddress,e.struct.EndAddress,e.struct.UnwindData) for e in after.DIRECTORY_ENTRY_EXCEPTION]
    assert new[:-2] == old
    assert new == sorted(new)
    for e, frame in zip(after.DIRECTORY_ENTRY_EXCEPTION[-2:], (0x62, 0xC2)):
        assert after.get_data(e.struct.UnwindData,8) == bytes([1,4,1,0,4,frame,0,0])
    assert not any(s.Characteristics & 0x20000000 and s.Characteristics & 0x80000000 for s in after.sections)
    assert after.OPTIONAL_HEADER.DATA_DIRECTORY[4].VirtualAddress == 0
    assert after.OPTIONAL_HEADER.DATA_DIRECTORY[4].Size == 0
    assert after.OPTIONAL_HEADER.CheckSum == after.generate_checksum()
    old_imports = [(e.dll, [(i.name,i.ordinal,i.address) for i in e.imports]) for e in before.DIRECTORY_ENTRY_IMPORT]
    new_imports = [(e.dll, [(i.name,i.ordinal,i.address) for i in e.imports]) for e in after.DIRECTORY_ENTRY_IMPORT]
    assert new_imports[:-1] == old_imports
    assert new_imports[-1][0] == b'OLEAUT32.dll'


def test_unknown_and_already_patched_inputs_are_rejected():
    from patch_service_554 import patch_bytes
    original = SOURCE.read_bytes()
    changed = bytearray(original)
    changed[-1] ^= 1
    for raw in (bytes(changed), IMAGE.read_bytes()):
        with pytest.raises(ValueError, match='verified unmodified'):
            patch_bytes(raw)
